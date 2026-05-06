---
type: source
title: Intel LGA 1700 learning notes
author: jjshao
ingested_on: 2026-05-06
source_slug: intel-lga1700-learning-notes
local_file: sources/files/intel-lga1700-learning-notes-2026-05-06.md
---

# Intel LGA 1700 Learning Notes

## Summary

这份学习笔记围绕 Intel LGA 1700 CPU 插座引脚和一个嘉立创/立创开源 X86 主板实现整理。笔记先把 LGA 1700 引脚粗分为供电/地、DMI、PCIe、DDI 视频输出、内存数据/地址/命令、测试调试和其他控制信号，再结合开源主板观察 CPU 供电 rail、`_SENSE` 反馈、PCH 连接、PCIe/SATA 拓扑、BIOS SPI 路径和 DDR4 内存条引脚。

## Key Takeaways

- LGA 1700 的大部分引脚不是高速数据线，而是供电、地和电源相关信号；笔记估算超过 `1100+` 个引脚属于电源/GND 类。
- CPU 与 PCH 的核心互连是 `DMI_(RX|TX)(P|N)[7:0]`，即 DMI x8 的 32 个差分信号引脚；PCH 还参与时钟、电源管理、复位、HDMI 热插拔/协商、SATA、PCH PCIe 和 BIOS SPI 等功能。
- CPU 直出的高速接口包括 `PCIE_X16`、`PCIE_X4` 和多组 DDI 视频输出；在笔记引用的开源主板实现中，CPU x16 接到 PCIe x16 插槽，而 CPU x4 未连接。
- 内存引脚直接连接到内存插槽，DDR4 与 DDR5 在 DQ/DQS、地址/命令和时钟组织上有重叠也有差异；笔记特别记录了 DDR4 x2 通道与 DDR5 x4 通道的 DQ/DQS 和地址命令信号分组。
- `_SENSE` 后缀被解释为开尔文连接式远端电压检测；开源主板片段里的 `VCCIN_AUX_SENSE` 电路展示了 CPU 端 sense 点、同步 buck 功率级、FB 分压/补偿网络和本地回退电阻如何组成反馈环路。
- 笔记把传统“地址线经外部译码器访问 BIOS”的心智模型替换为现代平台路径：CPU 内部 System Agent 判断 BIOS 访问，再通过 PCH 内部 SPI 与 BIOS 交互。

## Implications For This Wiki

- 这份笔记适合成为 [[wiki/concepts/intel-lga1700-socket-signal-groups]] 的主要起点，用来记录 LGA 1700 插座信号大类，而不是把每个引脚名拆成独立页面。
- `_SENSE`、`VCCIN_AUX_SENSE` 和 buck 反馈片段应补充到 [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]]，作为已有 CPU remote sense 概念页的新证据来源。
- 嘉立创/立创开源 X86 主板目前只以用户笔记和公开页面链接的形式出现；若后续下载工程 zip、原理图或 PCB 文件，应另行保存到 `sources/files/`，再创建更可复核的 source note 或 inspection note。
- DDR4/DDR5 DIMM 引脚、DDI/HDMI/PCH 分工、PCH SPI BIOS 路径可以先作为本 source note 的局部知识保留，等后续资料积累后再沉淀为单独概念页。

## Related Pages

- [[wiki/index]]
- [[wiki/concepts/intel-lga1700-socket-signal-groups]]
- [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]]
