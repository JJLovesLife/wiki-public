## Definition

Intel LGA 1700 插座可以从系统连接关系上粗分为几类信号：大量供电和地引脚、CPU 到 PCH 的 DMI 与管理信号、CPU 直出的 PCIe 与 DDI 高速接口、直连内存插槽的 DDR 信号、测试/调试信号，以及温度、错误、插座占用和配置 strap 等控制信号。

这个视角的重点不是枚举 1700 个 pad，而是建立主板设计时的功能地图：哪些线承载电源，哪些线连接 PCH，哪些线直接去 PCIe/显示/内存插槽，哪些线只是上电、调试、热管理或配置所需。

## Why It Matters

LGA 1700 看起来是“CPU 引脚表”，但主板实现上它实际约束了整机拓扑。CPU 供电 rail、远端 sense、内存通道、PCIe 插槽、显示接口、PCH 互连、BIOS 访问路径和 Super I/O/EC 监测都能从插座信号分组中看出来。

把引脚按功能分组后，更容易判断一个开源主板设计的取舍。例如 CPU 直出的 `PCIE_X16` 适合接显卡插槽，CPU 直出的 `PCIE_X4` 可以接高速设备但也可能未连接；PCH 侧 PCIe/SATA 则承担网卡、M.2、SATA 插槽等平台 I/O。类似地，DDI 数据线可能从 CPU 直出，但 HDMI 的 HPD 和 SCL/SDA 协商线仍可能由 PCH 负责。

## Supporting Evidence

- [[wiki/sources/intel-lga1700-learning-notes]] records an overview estimate: `1100+` power/GND-related pins, `32` DMI pins, `16` CPU PCIe x4 pins, `64` CPU PCIe x16 pins, `50` DDI pins, `152` memory DQ pins, `40` memory DQS pins, `108` memory address-related pins, and `100+` other pins.
- [[wiki/sources/intel-lga1700-learning-notes]] groups power-related names including `VCCCore`, `VSS`, `VCCGT`, `VSSGT`, `VCCIN_AUX`, `VSSIN_AUX`, `VCC1P05_PROC`, `VCC1P8_PROC`, `VDD2`, `VDD2_DDR5_SENSE`, `DDR_VREF_CA[3:0]`, `VCCST_PWRGD`, `VCCST_PWRGD_SX`, `PROCPWRGD`, and `_SENSE` suffixes.
- [[wiki/sources/intel-lga1700-learning-notes]] identifies CPU-PCH links and management signals such as `DMI_(RX|TX)(P|N)[7:0]`, `PROC_AUD(IN|OUT|CLK)`, `RTC_CLK`, `NSSC_CLK_D(P|N)`, `BCLK_(P|N)`, `PM_SYNC`, `PM_DOWN`, and `RESET#`.
- [[wiki/sources/intel-lga1700-learning-notes]] records CPU direct interfaces: `PCIE_X4_TX/RX` as 4 differential lanes, `PCIE_X16_TX/RX` as 16 differential lanes, and `DDI(A-E)_TX(P|N)[3:0]` plus `DDI(A-E)_AUX(P|N)` as five display groups.
- [[wiki/sources/intel-lga1700-learning-notes]] describes DDR memory signals as direct-to-slot connections, including DDR4-style `DQ`, `DQS`, `M`, `PAR`, `ODT`, `CS`, `CLK`, `CKE`, `BG`, `BA`, and `ACT#`, plus DDR5-style `CA`, `CLK`, and `CS` grouping.
- [[wiki/sources/intel-lga1700-learning-notes]] uses a referenced open X86 motherboard implementation to illustrate board-level routing choices: CPU x16 to a PCIe x16 slot, CPU x4 not connected, PCH PCIe to a network controller/x1 slot/x4 SSD, PCH SATA to SATA storage, and a muxed M.2 path supporting both SATA and PCIe.
- [[wiki/sources/intel-lga1700-learning-notes]] notes that BIOS access is mediated by the CPU System Agent and PCH SPI path rather than by external 6502-style address-line demultiplexing.
- [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]] gives the related power-feedback interpretation for `_SENSE` pins and the `VCCIN_AUX_SENSE` buck feedback example.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/intel-lga1700-learning-notes]]
- [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]]

## Open Questions

- The current source is a user learning-note snapshot, not an Intel datasheet or design guide. Pin counts and DDR4/DDR5 group interpretations should be checked against the official platform documentation before being treated as normative.
- The DDI A-E mapping, especially which groups are normally used for eDP, DP/HDMI, Type-C, or optional ports, remains platform-design dependent and should be confirmed against official docs or a specific board schematic.
- The referenced open X86 motherboard files have not yet been archived into `sources/files/`, so board-level routing examples are evidence from the learning note rather than independently ingested CAD source files.
