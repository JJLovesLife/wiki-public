LGA 1700 中超过 1100+ 的阵脚是供电/地等电源相关的

overview 总结

1100+ 电源 / GND
    核心供电 VCCCore
    核显供电 VCCGT
    其他比如 system agent, 总线, PCIe之类的 VCCIN_AUX
    内存供电 VDD2
    核心的 1.05V 1.8V, 一些比如睡眠模式、调试等其他的供电
    开尔文检测
    高速数据线都要四周用 GND 包围，就算用菱形布局，比例也是接近 1:1 所以总共一半以上都是 GND
32 DMI -> PCH
16 PCIe x4
64 PCIe x16
50 DDI A-E
152 memory DQ (data)
40 memory DQS (byte mask)
108 memory addr-related
100+ others

引脚信号名

**电压相关**
- RSVD: 空点
- VSS: 地
- _SENSE: 该后缀是用于 开尔文连接 进行 远端电压检测，大概就是说在高电流，导线电阻导致的压降会很大。通过另一根低电流导线的低压降，电源模块就可以对比压差来提高输出抵消导线压降。

- VCCCore / VSS 主要的核心可变电压
- VCCGT / VSSGT 是核显使用的电压
- VCCIN_AUX / VSSIN_AUX 是辅助模块的 1.8V 电压
- VCC1P05_PROC 是其他辅助模块的  1.05V 电压
- VCC1P8_PROC 1.8V
- VDD2 内存电压
- VDD2_DDR5_SENSE 应该是DDR5的 sense
- DDR_VREF_CA\[3:0]: 内存电压反馈给 CPU

- VCCST_PWRGD / VCCST_PWRGD_SX 这两个用来指示相关电源是否正常（启用）和电源休眠模式 Sx 相关
- PROCPWRGD 接PCH南桥，应该是一些电压检测

Msic 电压
- VCC_CFG_PU_OUT: 给 CFG 用的，可能是一些时序不同

**测试相关**
- PROC_TDI & PROC_TDI & PROC_TMS: JTAG 测试相关
- RSVD_TP: 用于测试使用，一般是空点，或者连接到测试点
- PCH_TRIGIN / PCH_TRIGOUT: debug 接PCH南桥
- PROC_PREQ# / PROC_PRDY#: 开启 probe mode 接PCH南桥
- EAR#
- PROC_JTAG_TRST# / PROC_TMS / PROC_TDO / PROC_TDI / PROC_TCK
- BPM#\[3:0]: 调试用断点信息

**其他**
- THERMTRIP#: 过热报警，接PCH南桥
- PROCHOT#: 高温
- CATERR#: 错误报警
- SKTOCC#: 监测CPU是否插入
- CFG\[17:0]: 控制比如说 PCIe / Graphic PCIe 的引脚顺序调换, PCIe 是 x16 还是 2x8

**PCH**
(通常又叫做南桥)
- DMI_(RX|TX)(P|N)\[7:0] (32 pins): DMI x8 PCH 和 CPU 通讯数据线
- PROC_AUD(IN|OUT|CLK): display audio, 接PCH南桥
- (clock) RTC_CLK: PCH传入实时时钟相关
- (clock) NSSC_CLK_D(P|N): 38.4 MHz bus clock input
- (clock) BCLK_(P|N): 100MHz bus clock input
_和具体数据不太相关的_
- PM_SYNC / PM_DOWN: 电源管理相关
- RESET#: 南桥触发重置

**PCH-PCIe**
- (clock) PCI_BCLKP / PCI_BCLKN: PCIe 基准频率 100MHz 接PCH南桥
    然后 PCH 再输出 CLK -> PCIe 插槽 REFCLK+ / REFCLK- pin

**PCIe**
- PCIE_X4_TXP\[3:0] / PCIE_X4_TXN\[3:0] (8 pins): PCIe x4, 4对差分对(1对两个针脚), CPU -> PCIe，走线接到 PCIe 插槽上
- PCIE_X4_RXP\[3:0] / PCIE_X4_RXN\[3:0] (8 pins): 同上 PCIe -> CPU
- PCIE_X16_(TX/RX)(P/N)\[15:0] (64 pins): 共64针脚

**DDI视频输出**
- DDI(A-E)_TX(P|N)\[3:0] + DDI(A-E)_AUX(P|N) (50 pins): 5组DDI数据线，每组是一个 x4 TX + 1x AUX. 5组分别是给不同协议用的，比如 A组用于笔记本 eDP, B/C 用于 DP/HDMI，最多两个插口 D组用于 Type-C E组比较少用到，不用的会置空。
    也有可能 D组是第三个接口，E 组是 Type-C 不关键，有需要可以查阅一下官方文档确认下
    AUX 好像是 DP 协议用到的一组半双工双向通讯差分线
    比如在给出的开源实现中，B组接到了 HDMI 接口，B组AUX 留空
    - PCH -- HDMI HPD
    - PCH -- HDMI SCL/SDA
    从这里可以看出，HDMI的插拔、协商是由PCH负责的，尽管数据传输是由CPU负责
- 有一个音频输出见 PCH PROC_AUD 应该是某些协议？

**内存**
全都是直连到内存插槽
- DDR(0-3)_DQS(P|N)\[0-4] (40 pins)
  DDR(0-1)_DQS(P|N)\[0-8] (36 pins)
    时钟沿差分信号
    如果是 (DDR4) x2 通道, 每个通道 9 bits
    如果是 (DDR5) x4 通道, 每个通道 5 bits (1bit 支持 ECC 可以不连)
- DDR(0-1)_DQ\[0-8]\[0-7] (144 pins)
  DDR(0-3)_DQ\[0-3]\[0-7] + DDR(0-3)_DQ4\[0-3] (144 pins)
  虽然都是 144 pins 但是四通道和双通道有几个针脚不是同一个，所以总共有 152 pins
    数据线
    DDR4 x2 通道, 每个通道 8字节 + 1字节 ECC 共 72 bits (144 pins)
    DDR5 x4 通道, 每个通道 4字节 + 4 bits ECC 共 36 bits (144 pins)
DDR4 + DDR5 共用108 pins (有些不重叠)
(DDR4 86 pins)
- DDR0|1_PAR (2 pins): parity check for cmd & addr
- DDR0|1_ODT\[3:0] (8 pins): 是否开启 On Die Termination (ODT) 控制阻抗匹配电阻开关 (1 per rank)
- DDR0|1_M\[16:0] (34 pins): 地址线 + 传命令使得 op-code
- DDR0|1_CS\[3:0] (8 pins): chip select (1 per rank)
- (clock) DDR0|1_CLK(P|N)\[3:0] (16 pins): clock (1 per rank)
- DDR0|1_CKE\[3:0] (8 pins): clock enable (1 per rank)
- DDR0|1_BG(0,1) (4 pins): which bank group
- DDR0|1_BA(0,1) (4 pins): bank address
- DDR0|1_ACT# (2 pins): high 表示为命令模式
(DDR5 100 pins)
- DDR(0-3)_CA\[12:0] (52 pins): 地址+命令混合
- (clock) DDR(0-3)_CLK(P|N)\[3:0] (32 pins): clock (1 per rank)
- DDR(0-3)_CS\[3:0] (16 pins): chip select (1 per rank)
---
- DDR0|1_ALERT#
- DDR_VTT_CTL
---
这个连到 VDD2
- DDR_VREF_CA\[3:0]

**Super I/O**
(笔记本上叫做EC)
- EC_PECI: EC 和 CPU 交互电源、温控等信息的串行数据线


### DDR4 内存条引脚
- VDD: 供电
- VTT: 其他各种供电

- DM_n: 正常一次写入 8字节 * 8脉冲，DM_n 允许一个脉冲只写入某几个字节。（这是一个主板+内存条+CPU三种都支持才能启用的功能）
- DBI_n: 和 DM_n 复用引脚，用于翻转数据线上的 bit 从而减少传输耗能，降低能耗。
- Event_n: 高温报警
- RESET_n: as name

94 GND
26 VDD
2 VTT
5 VPP
1 VDDSPD
1 VREFCA
9 DM/DBI
18 DQS P|N
64 DQ
17 Addr
2 BA
2 BG
2 CS
4 CK0|1 P|N
2 CKE
2 ODT
8 CB
3 SA
2 SDA/SCL
5 OTHERS
17 NC
2 unknown

## 参考嘉力创EDA主板开源实现: [X86电脑主板](https://oshwhub.com/oshwhub/dian-nao-zhu-ban)

```
VCC_SENSE / VSS_SENSE
& VCCGT_SENSE / VSSGT_SENSE
& VCC1P05_PROC
  -> 主 PWM 电源管理芯片
# 注意这个实现中 VCCIN_AUX 的那块电源管理芯片有一个单相的 sense 反馈，
# 但是 VCCGT 的电源管理芯片没有 sense 反馈， VCCGT_SENSE 是接入的主电源管理芯片
# 然后 VCCGT 的电源管理芯片有一个 PWM 针脚是从 主电源管理芯片连过来的
# 而 AUX_IN 似乎没有这个
VCCIN_AUX
& VCCIN_AUX_SENSE / VSSIN_AUX_SENSE -> 另一个单独的 PWM 单相电源管理芯片（CPU左上一圈左下那个电感对应的）

# 这几个电源管理芯片使用通过管理两个 MOS 管开关把 12V 降压成对应的电压 VCCCore / VCCGT / VCCIN_AUX

VCCCore / VDD2 -> Super I/O (类似 EC) # 用于监测

VIDSOUT / VIDSCK / VIDALERT# -> 主 PWM 电源管理芯片 # 用于 CPU 和电源芯片协议通讯

VSSGT -> 显卡的单独的 PWM 单相电源管理芯片（CPU左上一圈右上那个电感对应的）

VDD2 由内存条边上的电感对应的电源管理芯片从 5V 降压得到

# 这两个用来指示相关电源是否正常（启用）和电源休眠模式 Sx 相关
VCCST_PWRGD # 根据 主 PWM 芯片计算出来 1.05V 是否正常工作
VCCST_PWRGD_SX <- 连接到 南桥

# 连接电容用于滤波
VCCIN_AUX_FLTR / VCCIN_AUX_EDGECAP / VDD2_EDGECAP

# 这几个似乎不是前面那种同步整流，没有大的 MOS 管和电容、电感
一个单独的电源芯片从 3.3V -> VCC1P05_PROC
VCC1P05_PROC -> 南桥 # 反馈
VCC1P8_PROC

PROCHOT# -> 主电源管理芯片

CPU PCIe x4 -> not connected
CPU PCIe x16 -> PCIe x16 插槽
PCH PCIe -> x1 网卡 / x1 插槽 / x4 SSD (PCIe)
PCH SATA -> x1 SSD (SATA) / x1 插槽 2个
    SSD M.2 同时支持 SATA / PCIe 通过一个 muxer switch 接到 PCH PCIe x4 / SATA x1

PCH SPI -> BIOS
  CPU 内部 System Agent 判断地址是 memory 还是 BIOS, 如果是 BIOS, 通过 PCH 内部的 SPI 和 BIOS 交互。
  这里不是我以前想的，类似 Ben Eater 6502 那种通过地址线上做一些 demuxer 电路来实现某些地址连到 BIOS。毕竟这种在高速通路下肯定不合适。
```

内存条
```
DM_n -- VDD2 # 应该是这个主板不支持 DM_n 功能，但是好像连到 VDD2 也不是推荐的屏蔽方式。
```

VCCIN_AUX_SENSE 电路设计
```
CPU -- AUX_SENSE_P
CPU -- AUX_SENSE_N
AUX_SENSE_N -- 100 Ω -- GND
AUX_SENSE_N -- 10 kΩ -- PWN 电源 FB 引脚
PWN 电源 FB 引脚 -- 15.8 kΩ -- AUX_SENSE_P
PWN 电源 FB 引脚 -- 4700 pF -- 7.5 kΩ -- AUX_SENSE_P
AUX_SENSE_P -- 100 Ω -- VCCIN_AUX_CPU -- 0.22 μH (0.6 mΩ) -- MOSFET_1 (S) -- PWN 电源 PH 引脚
PWN 电源 BOOT 引脚 -- 2.2 Ω -- 220 nF -- MOSFET_1 (S) -- 2.2 Ω -- 220 nF -- GND
PWN 电源 UG 引脚 -- MOSFET_1 (G)
MOSFET_1 (S) -- MOSFET_2 (D) -- MOSFET_2 (S) -- GND
PWN 电源 LG 引脚 -- MOSFET_2 (G)
12V -- MOSFET_1 (D)
VCCIN_AUX_CPU -- 并联一堆 22 μF -- GND
VCCIN_AUX_CPU -- CPU
VCCIN_AUX_CPU -- 2 * 220 μF -- GND
VCCIN_AUX_CPU -- ISEN_SHORT /NI 1 -- ISEN1N_AUX -- ... --- 主 CPU PWN 电源 ISENN_AUX 引脚
MOSFET_1 (S) -- ISEN_SHORT /NI 2 -- ISEN1P_AUX -- ... --- 主 CPU PWN 电源 ISENP_AUX 引脚
```
