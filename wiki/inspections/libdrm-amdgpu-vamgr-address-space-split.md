---
type: inspection
title: "libdrm amdgpu_vamgr.c GPU VA split: canonical low/high halves, 32-bit buckets, AMDGPU_VA_RANGE_REPLAYABLE, va_base_required"
repo: libdrm
repo_commit: 8de45ef60d69472a0f8ba898f91250dac88bb81f
inspected_on: 2026-04-21
scope_paths:
  - amdgpu/amdgpu_vamgr.c
  - amdgpu/amdgpu_internal.h
  - amdgpu/amdgpu_device.c
  - amdgpu/amdgpu.h
  - include/drm/amdgpu_drm.h
---

## Question

`amdgpu_vamgr.c` 为什么把 GPU VA 拆成 `low/high x 32-bit/rest` 四个 manager，它们是怎么被选中的，以及 `va_base_required` 有什么用？

## Answer

`amdgpu_vamgr.c` 实际上不是维护一个统一的 GPU VA free list，而是维护四个 `amdgpu_bo_va_mgr`：

- `vamgr_32`：low canonical half 里的前 4 GiB window。
- `vamgr_low`：low canonical half 里除这 4 GiB 之外的剩余空间。
- `vamgr_high_32`：high canonical half 里的前 4 GiB window。
- `vamgr_high`：high canonical half 里除这 4 GiB 之外的剩余空间。

这样拆有两个正交原因。第一，KMD 通过 `virtual_address_offset/max` 和 `high_va_offset/max` 给 userspace 两段可用 GPU VA；`amdgpu_internal.h` 的注释也直接说明 `low/high` split 是因为 64-bit canonical addressing 中间会有一个 hole。第二，每一段 canonical space 又再切出一个 4 GiB window，对应 `AMDGPU_VA_RANGE_32_BIT` 需求；注释里给出的动机是有些程序不能处理跨 32-bit 地址空间的 VA，所以 libdrm 单独保留了 32-bit-constrained pool。

分配时，`AMDGPU_VA_RANGE_HIGH` 和 `AMDGPU_VA_RANGE_32_BIT` 两个 flag 先决定从四个 bucket 里的哪一个开始找；如果 caller 没强制 `32_BIT`，而选中的 non-32-bit bucket 分配失败，libdrm 会 fallback 到同侧的 32-bit bucket。每个 bucket 本身就是一个 hole-list allocator：默认从低地址向上找第一块能放下的洞，`AMDGPU_VA_RANGE_REPLAYABLE` 则改成从高地址向下找。这个 top-down policy 不是随便选的；从引入它的 commit message 看，目的是把 capture/replay 用的 buffer 尽量和普通分配隔开，减少普通分配占掉 replay 时所需 VA 的概率，从而提高 recapture / replay 成功率。

`va_base_required` 是 fixed-base mode。caller 给一个非零地址时，allocator 不再自己选地址，而是要求 `[va_base_required, va_base_required + size)` 必须完整落在某个 hole 里，并且 base 还要满足 alignment。这个机制本身是 generic 的；实际很适合 capture/replay 或 recapture 场景，例如 RenderDoc 一类工具需要尽量复现原先的 GPU VA layout。不过这个 repo snapshot 里只看得到 API 和 allocator 语义，看不到具体的 RenderDoc call site。

## Trace

1. `drm_amdgpu_info_device` 同时暴露了 low half 的 `virtual_address_offset/max`、high half 的 `high_va_offset/max`，以及统一的 `virtual_address_alignment`。
2. `amdgpu_device_initialize()` 在 `amdgpu_query_gpu_info_init()` 之后，把这五个字段传给 `amdgpu_va_manager_init()`。
3. `struct amdgpu_va_manager` 里固定有四个 sub-manager：`vamgr_low`、`vamgr_32`、`vamgr_high`、`vamgr_high_32`。紧挨着的注释直接解释了这两个拆分维度：`32bit` 是为了兼容某些程序，`low/high` 是因为 canonical address hole。
4. `amdgpu_va_manager_init()` 用 `0x100000000ULL` 这个 4 GiB 边界把 low half 切成两块：`[low_va_offset, min(low_va_max, 4GiB))` 给 `vamgr_32`，剩余的 `[min(low_va_max, 4GiB), max(low_va_max, 4GiB))` 给 `vamgr_low`。
5. 对 high half，代码不是拿绝对的 `4GiB`，而是先用 `(high_va_offset & ~0xffffffffULL)` 对齐到 high canonical segment 的 4 GiB base，再切出这个 canonical half 里的第一个 4 GiB window 给 `vamgr_high_32`，其余给 `vamgr_high`。
6. 每个 `amdgpu_bo_va_mgr` 初始化时只有一个 hole，范围就是 `[start, max)`；后续 allocation/free 都只是在这个 hole list 上 split / merge。
7. `amdgpu_va_range_alloc2()` 先根据 `AMDGPU_VA_RANGE_HIGH` 和 `AMDGPU_VA_RANGE_32_BIT` 选 bucket。如果 high bucket 根本没初始化成功，代码会直接清掉 `AMDGPU_VA_RANGE_HIGH`。如果 caller 没要求 `32_BIT` 且第一次分配失败，则 fallback 到同侧的 32-bit bucket。
8. `amdgpu_vamgr_find_va()` 会先把 `alignment` 和 `size` 向 manager 的默认 alignment 对齐；如果 `base_required` 不满足 alignment，直接返回 `-EINVAL`。
9. hole list 的顺序是“高地址在前，低地址在后”。默认路径用 reverse iteration，所以 placement policy 实际是从低地址向上找；`AMDGPU_VA_RANGE_REPLAYABLE` 则走正向 iteration，并从 hole 顶部扣空间，相当于从高地址往下分配。
10. `AMDGPU_VA_RANGE_REPLAYABLE` / `search_from_top` 是后加的 capture/replay 支持。引入它的 commit message 明确写到：普通分配和 capture/replay buffer 会共享同一 VA allocator，容易让 replay 需要复现的地址先被别的内部 buffer 占掉；因此把 replayable allocation 推到地址空间顶部，尽量降低它对 non-replayable allocation 的影响，也降低 non-replayable allocation 挤占 replay 地址的风险。
11. `base_required != 0` 时，不再做 first-fit / top-down placement，只检查指定地址是否完整落在某个 hole 内；找不到就返回 `-ENOMEM`。
12. `amdgpu_vamgr_subtract_hole()` 负责在分配时缩短、切开、或删除 hole；`amdgpu_vamgr_free_va()` 则在释放时尝试向上下相邻 hole 合并。

## Evidence

- `include/drm/amdgpu_drm.h:1391-1443`：kernel-facing device info 同时包含 `virtual_address_offset/max`、`high_va_offset/high_va_max` 和 `virtual_address_alignment`。
- `amdgpu/amdgpu_device.c:241-252`：device 初始化时把 low/high VA range 和 alignment 一起传给 `amdgpu_va_manager_init()`。
- `amdgpu/amdgpu_internal.h:52-75`：`amdgpu_bo_va_mgr` 的 hole list 顺序注释是“高地址在前，低地址在后”；`amdgpu_va_manager` 固定包含四个 sub-manager，旁边注释直接说明了 `32bit` 与 canonical-hole 这两个拆分原因。
- `amdgpu/amdgpu_vamgr.c:44-60`：每个 sub-manager 初始化时只创建一个覆盖 `[start, max)` 的 hole。
- `amdgpu/amdgpu_vamgr.c:100-165`：`amdgpu_vamgr_find_va()` 实现了 alignment 处理、`base_required` exact-match 逻辑，以及 normal / replayable 两种搜索方向。
- `amdgpu/amdgpu_vamgr.c:238-299`：`amdgpu_va_range_alloc2()` 依据 `AMDGPU_VA_RANGE_HIGH` 和 `AMDGPU_VA_RANGE_32_BIT` 选择 bucket，并在 non-32-bit 失败时 fallback 到对应的 32-bit bucket。
- `git show 085ee3e488b48453a3ed82ae3b95dbcb6920a8c6`：引入 `AMDGPU_VA_RANGE_REPLAYABLE` 的提交标题是 `amdgpu: Add vamgr for capture/replay.`；提交说明明确说 top-down allocation 是为了把 capture/replay buffer 与 normal allocation 分开，降低地址冲突风险。
- `amdgpu/amdgpu_vamgr.c:251-253`：当 high VA manager 未初始化时，代码会清掉 `AMDGPU_VA_RANGE_HIGH`。
- `amdgpu/amdgpu_vamgr.c:325-350`：`amdgpu_va_manager_init()` 把 low/high 两段 VA 各自切成一个 4 GiB window 和剩余空间，映射到四个 sub-manager。
- `amdgpu/amdgpu_vamgr.c:72-98`：分配命中后，hole 会被缩短、切开或删除。
- `amdgpu/amdgpu_vamgr.c:167-220`：释放时会尝试与相邻 hole 合并。
- `amdgpu/amdgpu.h:1368-1485`：公开 API 定义了 `AMDGPU_VA_RANGE_32_BIT`、`AMDGPU_VA_RANGE_HIGH`、`AMDGPU_VA_RANGE_REPLAYABLE`，并把 `va_base_required` 描述为 caller-specified required VA base。

## Uncertainty

- `va_base_required` 的 fixed-base 语义在本 repo 里有明确证据，但“RenderDoc recapture”只是一个合理的外部使用场景示例，不是这个 snapshot 内能直接 trace 到的 call site。

## Related Pages

- [[wiki/index]]
