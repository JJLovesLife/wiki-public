## Definition

CPU 引脚名里带 `_SENSE` 的电源相关引脚，通常用于把 CPU 端实际电压反馈给主板上的电源控制芯片，实现开尔文连接式远端电压检测。典型形式是一对或多对 sense 线：例如 `VCC_SENSE` 采样 CPU 端电源电位，`VSS_SENSE` 采样 CPU 端回流/地电位；电源芯片用这两个低电流采样点的差值调节输出。

关键点是：`_SENSE` 引脚和它对应的供电或地引脚在 CPU 端属于同一个电气节点，或者在封装/基板/负载端被短接到同一电源域。它不是 CPU 内部 ADC 把电压“上报”给电源芯片，而是电源芯片通过高阻抗模拟检测引脚直接测量 CPU 端电压。

具体实现不一定都是电源芯片上的一对专用差分检测脚。有的主电源 rail 会把 `sense+` 和 `sense-` 分别接到 VR 控制器的独立远端检测输入；有的辅助 rail 则用外部电阻网络把远端正端和远端负端折算成一个单端 `FB` 电压，让只有 `FB` 引脚的控制环路也能参考 CPU 端电压。

开尔文连接把大电流供电路径和小电流检测路径分开。主供电引脚和电源/地平面承载 CPU 电流，会产生封装、插座、PCB 铜皮和过孔上的压降；`_SENSE` 线几乎不承载电流，因此自身压降很小，更接近 CPU 负载端的真实电压。

## Why It Matters

CPU 核心电压通常电压低、电流大，供电路径上的几十毫欧阻抗就可能造成明显压降。如果电源芯片只在 VR 输出端本地检测，CPU 端实际电压可能比目标值低；如果用远端 sense，电源芯片会提高或降低 VR 输出，使 CPU 端的 `VCC_SENSE - VSS_SENSE` 达到目标值。

这个机制也解释了为什么 `_SENSE` 网络在原理图上看起来“只是连回 CPU”，但布局上通常需要独立、低噪声、成对返回到 VR 控制器，而不是随意并入大电流铜皮。它的价值不在于传输功率，而在于让反馈环路看到负载端电压。

## VCCIN_AUX Example

以下根据用户提供的嘉立创 X86 电脑主板原理图片段整理：
```
CPU -- AUX_SENSE_P
CPU -- AUX_SENSE_N
AUX_SENSE_N -- 100 Ω -- GND
AUX_SENSE_N -- 10 kΩ -- PWM 电源 FB 引脚
PWM 电源 FB 引脚 -- 15.8 kΩ -- AUX_SENSE_P
PWM 电源 FB 引脚 -- 4700 pF -- 7.5 kΩ -- AUX_SENSE_P
AUX_SENSE_P -- 100 Ω -- VCCIN_AUX_CPU -- 0.22 μH (0.6 mΩ) -- MOSFET_1 (S) -- PWM 电源 PH 引脚
PWM 电源 BOOT 引脚 -- 2.2 Ω -- 220 nF -- MOSFET_1 (S) -- 2.2 Ω -- 220 nF -- GND
PWM 电源 UG 引脚 -- MOSFET_1 (G)
MOSFET_1 (S) -- MOSFET_2 (D) -- MOSFET_2 (S) -- GND
PWM 电源 LG 引脚 -- MOSFET_2 (G)
12V -- MOSFET_1 (D)
VCCIN_AUX_CPU -- 并联一堆 22 μF -- GND
VCCIN_AUX_CPU -- CPU
VCCIN_AUX_CPU -- 2 * 220 μF -- GND
VCCIN_AUX_CPU -- ISEN_SHORT /NI 1 -- ISEN1N_AUX -- ... --- 主 CPU PWM 电源 ISENN_AUX 引脚
MOSFET_1 (S) -- ISEN_SHORT /NI 2 -- ISEN1P_AUX -- ... --- 主 CPU PWM 电源 ISENP_AUX 引脚
```

用户提供的开源 X86 主板片段里，`VCCIN_AUX_CPU` 是一个从 `12V` 降压得到的辅助 CPU rail，而不是 CPU 自己生成的电压。

功率级是典型同步整流 buck。高边 MOSFET 的漏极接 `12V`，源极接开关节点/`PH`；低边 MOSFET 从同一开关节点拉到 GND。PWM/VR 控制器用 `UG`/`LG` 分别驱动高边和低边栅极。开关节点经过 `0.22 μH` 电感到 `VCCIN_AUX_CPU`，输出端再用多颗 `22 μF` 和 `220 μF` 电容到地滤波。

这个例子把功率路径和检测路径分得很清楚：`VCCIN_AUX_CPU` 通过电感、MOSFET 和输出电容供电给 CPU；`AUX_SENSE_P` 和 `AUX_SENSE_N` 则从 CPU 端作为低电流反馈线返回控制环路。`AUX_SENSE_P` 不是另一路供电输入，`AUX_SENSE_N` 也不是普通就近接地，而是参与反馈计算的远端参考点。

该 rail 没有把正、负 sense 分别接到两个独立的电压检测脚，而是用外部电阻把两者折算到单个 `FB` 引脚。`AUX_SENSE_P` 通过 `15.8 kΩ` 到 `FB`，`FB` 通过 `10 kΩ` 到 `AUX_SENSE_N`。忽略补偿支路和输入偏置时，直流上近似为：

```text
V_FB ~= (10 kΩ * V_AUX_SENSE_P + 15.8 kΩ * V_AUX_SENSE_N) / 25.8 kΩ
```

也就是说，`FB` 看到的是远端正端和远端负端之间的加权插值，而不是只看本地 `VCCIN_AUX_CPU` 对本地 GND。

`FB` 到 `AUX_SENSE_P` 的 `4700 pF` 串 `7.5 kΩ` 支路更像是环路补偿/前馈路径，用来改变动态响应。直流目标主要由 `15.8 kΩ` 和 `10 kΩ` 的分压关系决定。

这和某些 `VCC` 主 rail 上“正负 sense 分别进控制器两个独立引脚”的做法不同。两者目标都是让控制器参考 CPU 端电压。区别在于，一个是在控制器内部用差分远端检测放大器处理，另一个是在板级用电阻网络先把远端正负端转换成单端 `FB` 电压。

## Open-Circuit Protection

远端 sense 线如果开路，反馈输入可能悬空并让电源芯片误判输出电压，最危险的情况是误以为 CPU 端欠压，从而继续抬高 VR 输出。因此实际设计通常会加入开路保护或本地回退路径。

常见原则按高、低电位 sense 线分别处理：

- 对 `VCC_SENSE` 这类高端/正端检测线，开路保护通常让检测点弱连接、钳位或回退到本地 `VCC`/`VOUT`，避免 sense+ 悬空后被误读为低电压而导致 VR 过冲。
- 对 `VSS_SENSE` 这类低端/负端检测线，开路保护通常让检测点弱连接、钳位或回退到本地 `VSS`/GND，避免 sense- 悬空、被噪声抬高或失去参考后扭曲差分反馈。

实现方式可能是外部电阻、RC 滤波/限流、VR 控制器内部的 remote-sense open 检测，或这些机制的组合。具体电阻值、阈值和故障动作取决于 CPU 平台和电源芯片 datasheet；不能把某个主板上的保护拓扑直接当作所有平台的通用要求。

上面的 `VCCIN_AUX` 片段给出了一个很直观的外部保护做法：`AUX_SENSE_P` 通过 `100 Ω` 回退到本地 `VCCIN_AUX_CPU`，`AUX_SENSE_N` 通过 `100 Ω` 回退到本地 GND。这样 CPU 端 sense 连接正常时，反馈仍主要代表 CPU 端采样；如果 CPU sense 引脚、插座或细线开路，正端 sense 不会掉成悬空低电平，负端 sense 也不会失去地参考。

正负端的保护方向必须相反：正端开路时，安全回退点是本地输出 rail；负端开路时，安全回退点是本地地。把两者都拉向同一个方向会破坏反馈差值，甚至可能让控制器误判输出严重欠压或过压。

## Supporting Evidence

- User-provided LLM discussion, 2026-05-03: `_SENSE` pin 的作用是开尔文远端检测；`_SENSE` 与对应 CPU 供电/地节点在 CPU 端相连；检测由主板电源芯片完成，而不是 CPU 回报电压；开路保护需要区分 `VCC`/高端 sense 与 `VSS`/低端 sense 的安全偏置方向。
- OSHWHub project, `【全网首发】X86电脑主板`, https://oshwhub.com/oshwhub/dian-nao-zhu-ban, observed 2026-05-03: 这是一个公开的 X86 电脑主板工程页面，页面列出 GPL 3.0、附件 `开源资料.zip` 和工程成员；用户将其作为 CPU `_SENSE` 远端检测与开路保护的开源实现证据。该工程未下载到 `sources/files/`，因此这里不把它作为本地 raw source 管理。
- User-provided VCCIN_AUX schematic excerpt, 2026-05-04: 片段显示 `VCCIN_AUX_CPU` 由 `12V` 经高边/低边 MOSFET、`PH` 开关节点、`0.22 uH` 电感和输出电容构成同步降压；`AUX_SENSE_P` 通过 `100 Ω` 回退到本地 `VCCIN_AUX_CPU`，`AUX_SENSE_N` 通过 `100 Ω` 回退到 GND；`15.8 kΩ`/`10 kΩ` 网络把远端正负 sense 折算到 PWM/VR 控制器的单个 `FB` 引脚。

## Related Pages

- [[wiki/index]]

## Open Questions

- OSHWHub 工程的原始工程文件、VR 控制器型号、datasheet 阈值和 fault 动作尚未本地归档；当前 VCCIN_AUX 说明依据用户提供的原理图片段。
- 不同 CPU 平台可能对 remote sense、load-line、SVID/telemetry 和 fault handling 有额外规范，需要以对应平台设计指南和 VR 控制器 datasheet 为准。
