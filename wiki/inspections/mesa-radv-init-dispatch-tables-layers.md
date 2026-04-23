---
type: inspection
title: "RADV 的 init_dispatch_tables 如何用内部 layer 组织 device dispatch"
repo: mesa
repo_commit: 8418351c7c56f06312d1bbb285ce776b41f6790b
inspected_on: 2026-04-20
scope_paths:
  - src/amd/vulkan/radv_device.c
  - src/amd/vulkan/radv_device.h
  - src/amd/vulkan/layers/radv_annotate_layer_gen.py
  - src/amd/vulkan/layers/radv_sqtt_layer.c
  - src/amd/vulkan/layers/radv_rra_layer.c
  - src/amd/vulkan/layers/radv_rmv_layer.c
  - src/amd/vulkan/layers/radv_ctx_roll_layer.c
  - src/amd/vulkan/layers/radv_metro_exodus.c
  - src/amd/vulkan/layers/radv_rage2.c
  - src/amd/vulkan/layers/radv_quantic_dream.c
  - src/amd/vulkan/layers/radv_no_mans_sky.c
  - src/amd/vulkan/layers/radv_strange_brigade.c
---

## Question

`radv_device.c` 里的 `init_dispatch_tables()` 在做什么？RADV 内部这些 dispatch layer 大概分别起什么作用？

## Answer

`init_dispatch_tables()` 可以看作 RADV 在 `VkDevice` 内部实现的一套轻量 layer 机制。它先把主 dispatch table 和若干 layer-specific dispatch table 组织起来，再根据当前 `instance` / `device` 的 debug、trace、应用兼容配置，选择性插入中间层，最后把底层实现补齐到 `radv`、`wsi` 和 `vk_common` 的 entrypoints。

这个设计和 Vulkan loader/layer 的思路很像：默认走基础驱动实现；如果开启特定调试或 trace 功能，就在中间插入额外层做注释、采样、追踪、兼容修正或导出分析数据。

但要注意，`device->layer_dispatch.annotate/app/rgp/...` 这些表不是“该层自己的函数集合”。`add_entrypoints()` 会把新插入层的 entrypoints 复制进所有已经启用、且优先级更高的表里；最后 `radv` / `wsi` / `vk_common` 也会补进所有已使用的表。因此每张 `layer_dispatch.<name>` 实际上表示“从这一层继续往下转发时要调用的 next-lower chain”。例如 `device->layer_dispatch.rgp.QueueSubmit2()` 调到的是 RGP 之下剩余的链条，而不是再次回到 RGP 自己。

几层的职责可以粗看成：

- `annotate`：给大量 `Cmd*` 命令加 annotation，方便调试和 hang / ctx-roll 分析。
- `app`：按游戏名启用的兼容修正层，只修特定应用的错误调用或异常行为。
- `rgp`：给 RGP / SQTT 做性能 trace，包裹 `present`，并在 graphics/compute queue 且相关 trace 开关打开时记录 `submit`、marker、timestamp 等。
- `rra`：给光追分析抓取加速结构和 ray history，用于导出 `.rra` 捕获。
- `rmv`：在非 Windows 且开启 `VK_TRACE_MODE_RMV` 时插入，给显存分析记录 memory trace 相关事件。
- `ctx_roll`：在 submit / present 周围 dump context roll 相关命令流。
- `device`：链底，最终落到 `radv_device_entrypoints`、`wsi_device_entrypoints`、`vk_common_device_entrypoints`。

## Trace

1. `radv_CreateDevice()` 在 `vk_device_init()` 之后立刻调用 `init_dispatch_tables()`，说明这些 dispatch table 是 logical device 初始化的一部分。
2. `radv_device.h` 里定义了 `enum radv_dispatch_table` 和 `struct radv_layer_dispatch_tables`，明确 RADV 维护了主表和多张 layer 表。
3. `init_dispatch_tables()` 先把这些表地址装进 `dispatch_table_builder`，然后根据 `trace_mode`、`debug_flags`、`drirc.debug.app_layer` 等条件调用 `add_entrypoints()`。
4. `add_entrypoints()` 不是只往“当前层自己的表”里填函数；它会把新层 entrypoints 合并进所有已经启用、且优先级更高的表，所以每张 `layer_dispatch.<name>` 都是在保存该层以下的 forwarding chain。
5. 最后 `init_dispatch_tables()` 再统一加入 `radv_device_entrypoints`、`wsi_device_entrypoints`、`vk_common_device_entrypoints`，而且这些基础 entrypoints 也会被补进所有已使用的 layer 表，确保中间层 forward 时总能落回基础实现。

## Evidence

- `src/amd/vulkan/radv_device.c:744-811`：`dispatch_table_builder`、`add_entrypoints()` 和 `init_dispatch_tables()` 的核心实现，展示了 RADV 如何按条件拼装内部 dispatch layer；`add_entrypoints()` 会把新层复制进所有已启用的更高层表，`rmv` 还受 `#ifndef _WIN32` 平台保护。
- `src/amd/vulkan/radv_device.c:1173-1185`：`radv_CreateDevice()` 先做 `vk_device_init()`，再调用 `init_dispatch_tables()`。
- `src/amd/vulkan/radv_device.h:39-57`：定义 `RADV_DEVICE_DISPATCH_TABLE`、`RADV_ANNOTATE_DISPATCH_TABLE`、`RADV_APP_DISPATCH_TABLE`、`RADV_RGP_DISPATCH_TABLE`、`RADV_RRA_DISPATCH_TABLE`、`RADV_RMV_DISPATCH_TABLE`、`RADV_CTX_ROLL_DISPATCH_TABLE` 以及对应的 layer dispatch 存储。
- `src/amd/vulkan/layers/radv_annotate_layer_gen.py:33-46`：`annotate` 层会在转发前调用 `radv_cmd_buffer_annotate()`，说明它的核心作用是给命令流打注释。
- `src/amd/vulkan/layers/radv_sqtt_layer.c:648-765`：`rgp` / `sqtt` 层会包裹 `QueuePresentKHR`、`QueueSubmit2` 等入口，但 `QueueSubmit2` 的 queue-event / timestamp / trace 逻辑还受 queue 类型、`device->sqtt_enabled`、`radv_sqtt_queue_events_enabled()`、`instance->vk.trace_per_submit` 等条件约束。
- `src/amd/vulkan/layers/radv_rra_layer.c:13-70`：`rra` 层会在 present 前后处理 trace 导出、ray history 和 acceleration structure 生命周期数据。
- `src/amd/vulkan/layers/radv_rmv_layer.c:14-63`：`rmv` 层会记录 `present`、`flush/invalidate mapped memory`、`debug object name` 等 memory trace 事件。
- `src/amd/vulkan/layers/radv_ctx_roll_layer.c:12-52`：`ctx_roll` 层围绕 `QueueSubmit2` / `QueuePresentKHR` dump 和收尾 context roll 数据。
- `src/amd/vulkan/layers/radv_metro_exodus.c:11-20`、`radv_rage2.c:13-39`、`radv_quantic_dream.c:9-18`、`radv_no_mans_sky.c:12-34`、`radv_strange_brigade.c:12-30`：`app` 层不是通用调试层，而是按游戏启用的兼容修正层。

## Uncertainty

None noted.

## Related Pages

- [[wiki/index]]
- [[wiki/inspections/mesa-radv-graphics-queue-family-detection]]
