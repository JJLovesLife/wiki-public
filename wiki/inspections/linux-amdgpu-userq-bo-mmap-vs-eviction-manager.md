---
type: inspection
title: "linux amdgpu userq BO references: mmap fault synchronization versus eviction manager"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-05-09
scope_paths:
  - drivers/gpu/drm/amd/amdgpu/amdgpu_gem.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_object.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_eviction_fence.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_userq.c
  - drivers/gpu/drm/drm_gem_ttm_helper.c
  - drivers/gpu/drm/ttm/ttm_bo.c
  - drivers/gpu/drm/ttm/ttm_bo_vm.c
  - include/drm/drm_vma_manager.h
  - include/linux/dma-resv.h
---

## Question

为什么普通 CPU `mmap` 已经可以引用 BO 时不需要 eviction manager，而 user queue 引用 BO 时需要 eviction manager？BO move 时这两类 userspace 依赖分别怎么同步？

## Answer

这篇笔记只保留当前最重要的对照：CPU `mmap` 是 kernel-visible 的 BO 引用，user queue packet 里的 BO GPU VA 引用则基本是 userspace-owned 的运行时状态。前者可以由内核通过 MM fault 机制重新收口；后者不能靠 kernel 在 move 时扫描出来，所以需要 eviction manager 给 user queues 建一个显式的 quiescent point。

CPU `mmap` BO 时，`mmap()` 主要建立 VMA 和 fake offset 到 BO 的关系，不等于用户页表会永久指向同一份 backing。TTM 要 move BO 时，`ttm_bo_handle_move_mem()` 会先调用 `ttm_bo_unmap_virtual()`，后者通过 `drm_vma_node_unmap()` / `unmap_mapping_range()` zap 掉这个 BO 对应的 userspace PTE。之后 userspace 再访问该 mmap 地址会重新 fault 进 `amdgpu_gem_fault()`。

fault handler 是同步点。`amdgpu_gem_fault()` 先通过 `ttm_bo_vm_reserve()` 取得 BO 的 `dma_resv` lock；如果 move 正在持锁，fault 会 retry 或等待。拿到 reservation 后，`amdgpu_bo_fault_reserve_notify()` 可以在需要时把 BO 移到 CPU 可见 placement，`ttm_bo_vm_fault_reserved()` 还会等待 `DMA_RESV_USAGE_KERNEL` fences，以避免 CPU PTE 指向正在被 kernel memory-management copy/move 的数据。最后 fault path 再根据新的 BO backing 插入 PTE。因此 mmap 依赖的关键不是“CPU store 自动等 fence”，而是 BO move 能 zap PTE，把下一次 CPU 访问强制拉回 kernel fault path。

user queue 的问题不同。user queue 创建时，kernel 会验证 queue ring、RPTR、WPTR 这些 VA 已经属于当前 VM mapping；但队列运行后，userspace 可以直接往 queue ring 写 packet、更新 WPTR、ring doorbell，packet 里引用 BO 时使用的是 GPU VA。kernel 不会在每次 packet 写入时看到“这次引用了哪些 BO”，也不现实在 BO move 前扫描 user queue 来推导依赖。

所以 eviction manager 解决的是“user queue 可能仍在用旧 BO/VM 状态”这个 move 前 quiescence 问题。`amdgpu_gem_object_open()` 把当前 fd 的 eviction fence 挂到 BO `dma_resv` 的 `DMA_RESV_USAGE_BOOKKEEP` 上；当 TTM/VM move 或 validate 路径等待这个 fence 时，fence 的 `enable_signaling()` 会调度 `suspend_work`，进而 evict/suspend 该 fd 的 user queues。queues 停下后 eviction fence 被 signal，等待方才继续 move BO 或修复 VM/page table；restore 路径随后 validate VM 并换上一根新的 eviction fence，进入下一轮 active epoch。

这个模型可以类比成 RCU grace period：未 signal 的 eviction fence 表示“user queues 还处在可能引用旧 BO/VM 状态的 epoch”；等待这个 fence 等于请求进入 quiescent point；fence signal 表示 queue 已经停到足以让 BO move/VM validate 继续的位置。

## Trace

1. CPU mmap path: `amdgpu_gem_object_mmap()` 过滤 userptr/no-CPU-access BO 后调用 `drm_gem_ttm_mmap()`，最终 `ttm_bo_mmap_obj()` 把 BO 放进 `vma->vm_private_data` 并安装 fault ops。
2. BO move path: `ttm_bo_validate()` 需要换 placement 时进入 `ttm_bo_handle_move_mem()`；真正 move 前先调用 `ttm_bo_unmap_virtual()`。
3. PTE invalidation: `ttm_bo_unmap_virtual()` 调 `drm_vma_node_unmap()`，后者对 BO 的 fake mmap offset range 调 `unmap_mapping_range()`，把已有 userspace PTE zap 掉。
4. CPU refault: 下一次 CPU 访问这个 mmap 地址进入 `amdgpu_gem_fault()`；该路径先 `ttm_bo_vm_reserve()` BO，也就是拿 `dma_resv` lock。若 BO move 正在进行，fault 会在这里 retry/wait，而不是继续使用旧 PTE。
5. New backing: fault 持有 reservation 后，`amdgpu_bo_fault_reserve_notify()` 可把不可 CPU-visible 的 BO validate 到可见 placement；`ttm_bo_vm_fault_reserved()` 等 `DMA_RESV_USAGE_KERNEL` fences 并插入指向当前 backing 的 PTE。
6. User queue create path: `amdgpu_userq_create()` 只验证 queue ring、RPTR、WPTR VA 是否在 VM mapping 中。这说明 kernel 看到的是 queue 基础对象，不是之后每个 packet 会引用的全部 BO。
7. User queue move sync: `amdgpu_gem_object_open()` attach eviction fence；等待该 `BOOKKEEP` fence 会触发 `amdgpu_eviction_fence_enable_signaling()`，调度 suspend work，最后由 `amdgpu_userq_evict()` evict queues 并 signal fence。

## Evidence

- `drivers/gpu/drm/amd/amdgpu/amdgpu_gem.c:115-145`: amdgpu's mmap fault handler reserves the BO, calls `amdgpu_bo_fault_reserve_notify()`, then delegates PTE insertion to `ttm_bo_vm_fault_reserved()` before unlocking `dma_resv`.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_gem.c:226-272`: `amdgpu_gem_object_open()` locks the BO/VM state, creates or references `bo_va`, and attaches the fd's eviction fence to the BO.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_gem.c:367-385`: CPU mmap setup rejects userptr and no-CPU-access BOs, then delegates BO mmap setup to TTM.
- `drivers/gpu/drm/drm_gem_ttm_helper.c:101-118`: `drm_gem_ttm_mmap()` calls `ttm_bo_mmap_obj()` for TTM-backed GEM objects.
- `drivers/gpu/drm/ttm/ttm_bo_vm.c:488-511`: `ttm_bo_mmap_obj()` stores the BO in `vma->vm_private_data`, installs TTM fault ops when the driver did not override them, and marks the VMA as PFN-mapped IO memory.
- `drivers/gpu/drm/ttm/ttm_bo.c:120-158`: `ttm_bo_handle_move_mem()` calls `ttm_bo_unmap_virtual()` before invoking the driver move callback.
- `drivers/gpu/drm/ttm/ttm_bo.c:1049-1058`: `ttm_bo_unmap_virtual()` unmaps userspace mappings for this BO and frees IO memory mapping state.
- `include/drm/drm_vma_manager.h:209-227`: `drm_vma_node_unmap()` calls `unmap_mapping_range()` over the BO's fake mmap offset range.
- `drivers/gpu/drm/ttm/ttm_bo_vm.c:118-148`: `ttm_bo_vm_reserve()` tries to lock the BO reservation object from a retryable fault callback and may drop `mmap_lock` before waiting.
- `drivers/gpu/drm/ttm/ttm_bo_vm.c:183-203`: `ttm_bo_vm_fault_reserved()` first waits for buffer data in transit due to a pipelined move.
- `drivers/gpu/drm/ttm/ttm_bo_vm.c:258-280`: the fault helper inserts PFNs only after determining the BO's current backing resource.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_object.c:1352-1388`: `amdgpu_bo_fault_reserve_notify()` records CPU access and validates non-CPU-visible BOs into a CPU-visible placement before fault mapping.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_userq.c:824-831`: user queue creation validates queue, RPTR, and WPTR VAs against current VM mappings.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_eviction_fence.c:130-142`: waiting/callback setup for an eviction fence enables signaling by scheduling `suspend_work`.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_eviction_fence.c:197-217`: `amdgpu_eviction_fence_attach()` adds the current eviction fence to the BO reservation object as `DMA_RESV_USAGE_BOOKKEEP`.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_userq.c:1378-1396`: user queue eviction waits pending userq fence work, evicts all queues, signals the eviction fence, and schedules resume work unless the fd is closing.
- `include/linux/dma-resv.h:58-116`: `dma_resv` usage ordering separates `KERNEL`, `WRITE`, `READ`, and `BOOKKEEP`; `BOOKKEEP` is documented as no implicit sync.
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]]: details the eviction fence manager and BO move synchronization path.
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]: background on `dma_resv` as a per-buffer fence container with usage-scoped synchronization.

## Uncertainty

This note intentionally does not explain exactly how userspace decides which BOs a user queue packet uses, nor the full `USERQ_WAIT` / `USERQ_SIGNAL` dependency protocol. Those details are better saved for a later inspection after the BO/GEM create, GEM VA map, and basic user queue creation paths are clearer.

This inspection also does not analyze CPU/GPU cache coherency, explicit cache flushes, or domain-specific packet semantics for every hardware engine.

## Related Pages

- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/index]]
