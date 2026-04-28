---
type: inspection
title: "linux dma_resv: why shared asynchronous DMA buffers need per-buffer reservation objects"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-04-25
scope_paths:
  - include/linux/dma-resv.h
  - include/linux/dma-buf.h
  - drivers/gpu/drm/ttm/ttm_execbuf_util.c
  - drivers/gpu/drm/ttm/ttm_bo_vm.c
---

## Question

为什么 Linux 里的 `dma_resv` 存在，它解决的是哪类 DMA 同步问题？为什么 GPU、`dma-buf` 共享和 TTM 这类场景比很多“单驱动、请求级”的 DMA 用户更依赖它？

## Answer

`dma_resv` 不是“DMA 必备”的通用层，而是给“同一个 buffer 可能被多个主体异步、流水化、甚至迁移地访问”这种场景准备的每-buffer 同步对象。`include/linux/dma-resv.h` 把它定义成一个管理 `dma_fence` 的容器，并明确点出两个主要用途：跨驱动同步 `struct dma_buf` 访问，以及像 TTM 这样的 buffer memory manager 的驱动内部访问管理。

它之所以需要独立存在，是因为普通的“提交一个 DMA 请求然后等 completion”只能描述某个请求何时完成，不能集中表达“这块 buffer 现在挂着哪些未完成读写、哪些新访问必须等待、当前能不能迁移或重映射 backing storage”。`dma_resv` 通过一把 `ww_mutex` 和一组按 usage 分类的 `dma_fence`，把这些信息挂在 buffer 本身上，而不是挂在某个单独队列或某次提交上。

这也是为什么 `dma_resv` 更常见于 GPU、`dma-buf` 共享和 TTM 这类场景：同一块对象可能被 CPU、GPU 队列、显示引擎、其他 importer 或 exporter、以及内核内存管理代码交替或并发使用，而且访问往往是异步且可流水化的。此时需要的是 buffer-level 的协调，而不只是 request-level 的完成通知。相对地，`dma-buf` 注释也明确写了：有些只暴露同步 userspace API、没有跨驱动流水线的驱动并不会为访问设置 fences，例子就是 `v4l`。这说明不是“凡是 DMA 都需要 `dma_resv`”，而是“凡是共享、异步、需要隐式同步或可迁移的 buffer 往往需要它”。

如果把它和日常“单驱动管理一个 DMA ring 或 queue”的模式对照，可以把区别概括成：前者主要靠队列所有权和 completion 协调一次请求；后者需要把未完成访问记录在 buffer 本身上，让后来者能统一查询依赖、等待旧作业、追加新 fence，并在移动 buffer 前阻止并发 mapping。这个 inspection 没有追一个具体网卡驱动，但 Linux 的 `dma_buf`/`dma_resv` 接口已经清楚表明，`dma_resv` 的设计中心是共享 buffer 的长期协调，而不是所有 DMA 请求的通用 completion 包装。

## Trace

1. `struct dma_resv` 的注释先定义了它的职责：它是“管理一个 buffer 上 fences 的对象”，主要用于跨驱动同步 `dma_buf` 访问，以及像 TTM 这样的 buffer memory manager 的驱动内部协调。
2. 同一个注释还给出关键实现形态：`dma_resv` 内部既有更新侧使用的 `ww_mutex`，也有挂 fence 的数组；而且 `dma_resv_add_fence()` 往往发生在“已经不能失败”的提交后半段，所以调用者必须先用 `dma_resv_reserve_fences()` 预留槽位。
3. `enum dma_resv_usage` 把 fence 分成 `KERNEL`、`WRITE`、`READ`、`BOOKKEEP` 四类，并且定义了 usage 的包含关系。也就是说，`dma_resv` 不是一个简单的 “busy bit”，而是一个带访问语义的每-buffer 依赖表。
4. `struct dma_buf.resv` 的注释把这种依赖表用到了跨驱动共享 buffer 上：支持 implicit sync 的驱动必须在读写访问后往 `resv` 上添加对应的 read/write fence；dynamic importer 在允许底层存储被设备访问前必须遵守 write fences；而某些只提供同步 API 的驱动则可以完全不设置 fence。
5. `dma_buf` 相关注释还把 `resv` 和“buffer 会动”这件事绑定在一起：attachment 列表受 `resv` 保护，`move_notify` 在持有 `resv` 锁时调用，而 `dma_buf_map_attachment()` / `dma_buf_unmap_attachment()` 也必须在持锁状态下执行，以避免 mapping 和迁移并发交错。
6. TTM 的 `ttm_eu_reserve_buffers()` / `ttm_eu_fence_buffer_objects()` 给了一个驱动内部的具体用法：先按 `ww_mutex` 规则保留一组 BO，再为每个 BO 预留 fence 槽位，提交后把新的 read/write fence 挂回各自的 `bo->base.resv`，最后解锁。这正是“每-buffer 记录未完成访问”的典型流程。
7. `ttm_bo_vm_reserve()` 进一步说明，BO reservation 有时会等待 GPU，因此要被视为可能触发长等待的操作。这里的 reservation 之所以重要，不是因为锁本身复杂，而是因为它站在异步硬件访问和可重启 fault path 的交界处。

## Evidence

- `include/linux/dma-resv.h:139-178`：`struct dma_resv` 的总体定义，明确它是 buffer 的 fence 容器，并列出跨驱动 `dma_buf` 同步与 TTM 这类驱动内 memory manager 两大用途。
- `include/linux/dma-resv.h:157-177`：`dma_resv` 内的 `ww_mutex` 既保护 fence 更新，也可保护 placement 等 buffer-object 状态；`dma_resv_add_fence()` 可能发生在 “point of no return” 之后，因此需要 `dma_resv_reserve_fences()` 先预留槽位。
- `include/linux/dma-resv.h:53-116`：`DMA_RESV_USAGE_KERNEL` / `WRITE` / `READ` / `BOOKKEEP` 的语义和包含关系，说明 `dma_resv` 表达的是访问类型和依赖，而不是单一忙闲位。
- `include/linux/dma-resv.h:321-339`, `include/linux/dma-resv.h:349-367`, `include/linux/dma-resv.h:409-465`：`dma_resv` 的 writer-side 锁是 `ww_mutex`，支持死锁回退路径，适合一次保留多个 buffer。
- `include/linux/dma-buf.h:313-315`：`dma_buf` 的 attachment 列表受 `resv` 锁保护。
- `include/linux/dma-buf.h:372-417`：`struct dma_buf.resv` 的 implicit synchronization 规则，要求驱动为 read/write access 添加对应 fences，并明确指出某些只提供同步 userspace API 的驱动不会设置 fences，例子是 `v4l`。
- `include/linux/dma-buf.h:449-477`：`move_notify` 与 attachment mapping 必须在持有 `resv` 锁时执行，用来避免 buffer 迁移和映射并发冲突。
- `drivers/gpu/drm/ttm/ttm_execbuf_util.c:76-159`：TTM 在一次验证/提交路径中保留多个 BO、预留 fence 槽位、提交后添加 read/write fence，并在每个 BO 上解锁，展示 `dma_resv` 的每-buffer 协调方式。
- `drivers/gpu/drm/ttm/ttm_bo_vm.c:98-149`：VM fault path 明确把 BO reservation 视为可能等待 GPU 的长等待操作，并围绕 `dma_resv` 锁做 retryable reserve。

## Uncertainty

`dma_resv` 在 Linux `dma-buf` / TTM 接口里的设计目的没有明显歧义。这里和“典型网卡 DMA”做的对照是概念性总结，而不是基于某个具体 NIC 驱动的逐行 call trace。

## Related Pages

- [[wiki/inspections/linux-rcu-child-reference-lifetime]]
- [[wiki/index]]
