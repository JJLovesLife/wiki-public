---
type: inspection
title: "linux amdgpu GPUVM PTE/TLB synchronization versus CPU shootdown"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-05-22
scope_paths:
  - drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_sync.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_cs.c
  - drivers/gpu/drm/amd/amdgpu/amdgpu_ids.c
---

## Question

amdgpu 更新或清除 GPUVM PTE 时，如何避免正在运行的 GPU work 继续使用旧 translation？这个模型和 CPU page table update + TLB shootdown 有什么差异？

## Answer

普通 amdgpu BO/GPUVM 路径不是把正确性建立在“GPU wave 和 PTE writer 并发运行，之后靠 TLB flush 收敛”上。它主要在 GPU job submission boundary 上建立顺序：旧 job 可以继续使用旧 mapping 跑完；driver 在清 PTE 前等待这些已经提交的 same-VM job；PTE update/clear 完成后，后续 CS 再等待对应 page-table update fence，并在需要时通过 VMID/TLB flush 后执行。

clear/unmap 的关键同步点是 VM root BO 的 `dma_resv`。amdgpu 在清 PTE 前用 `amdgpu_sync_resv(..., AMDGPU_SYNC_EQ_OWNER, vm)` 收集同一个 VM owner 的已提交 fence。可以把它类比成“等待这个同步点之前已经提交、可能使用旧 PTE 的 GPU jobs 完成”，然后才清除 mapping。

后续新 job 不能绕过这次 unmap。CS VM handling 会先处理 freed mapping、moved BO、PDE/PTE update，并把相关 `bo_va->last_pt_update` 和 `vm->last_update` 加入 job sync。也就是说，同步点之后提交的 GPU work 要么看到 mapping 已经被清掉，要么等待清 PTE 的 VM update 完成。

TLB flush 是另一层顺序控制。PTE memory update 完成并不自动说明所有 VMID/TLB 都已经丢弃旧 translation；amdgpu 用 VM `tlb_seq` 记录“这个 VM 的 translation state 已经更新”。VMID 分配或复用时会比较 VMID 已 flush 的 sequence 和当前 `tlb_seq`；如果落后，后续 job 会被标记为需要 VM flush，ring submission 时再发出 VM flush。需要保护 page-table object lifetime 的场景还可以创建 TLB fence，避免下级 page table 在 flush 前被释放。

这和 CPU 的常规模型不同。CPU page-table update 允许多个 CPU core 在短时间内继续持有旧 TLB entry，OS 通过 IPI/shootdown 让相关 core 精确 invalidate 并确认完成。CPU core 可中断、page fault 精确可恢复，TLB shootdown 是 CPU MMU/OS memory management 的基础协议。

GPU 的传统执行模型则更像“提交 job -> 异步执行 -> fence 完成”。driver 通常在 job boundary 控制力最强，而不是在某个 running wave 中间精确打断所有 CU、VM hub、TLB/cache/page walker 和 graphics/compute/SDMA/media engine 并等待逐个确认。因此，对普通 GEM/BO GPUVM mapping，amdgpu 选择 job/fence 粒度的 quiescent point 和 VMID/TLB sequence，而不是 CPU-style fine-grained shootdown。

理论上 GPU 可以设计得更接近 CPU shootdown，但代价是显著增加硬件和驱动复杂度：需要精确 invalidate acknowledgement、running wave 的可恢复 fault/replay、跨 engine 一致语义，以及安全释放旧 page table page 和 backing memory 的 lifetime 规则。现代 GPU 在 SVM/HMM/PASID/retry-fault compute 场景里有更细机制，但那是专门路径，不等价于普通 BO GPUVM mapping 的 CPU process address-space semantics。

## Trace

1. clear path 在清 PTE 前同步 same-VM submissions。`amdgpu_vm_bo_update(clear=true)` 和 `amdgpu_vm_clear_freed()` 都使用 `amdgpu_sync_resv()` 从 VM root BO reservation object 中收集 fence。
2. `AMDGPU_SYNC_EQ_OWNER` 只保留同 owner fence；普通 CS job 的 fence owner 是当前 `amdgpu_vm`，所以 clear path 等到的是这个 VM 里已经提交、可能使用旧 mapping 的 jobs。
3. 清 PTE 的 VM update 会产生 page-table update fence。后续 CS VM handling 会先完成 freed/moved/mapping update，再把 `bo_va->last_pt_update` 或 `vm->last_update` 加入 sync，阻止新 job 抢在 VM update 前运行。
4. 普通 CS submit 会把 job fence 添加回已锁对象的 `dma_resv`。因为 CS 准备阶段会锁 VM root PD，后续 unmap path 能从 VM root BO reservation object 看到同步点之前提交的 same-VM work。
5. TLB invalidation 通过 VM `tlb_seq` 和 VMID flushed state 表达。PTE update 需要 flush 时会递增或安排递增 `tlb_seq`；VMID 分配/复用时发现 flushed sequence 落后，就把 job 标为需要 VM flush。
6. 这个顺序形成的是 job-boundary quiescence：旧 job 完成后 PTE 才被清掉，新 job 等 page-table update 和 VMID/TLB flush 后再运行。

## Evidence

- `drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c:1278-1286`: `amdgpu_vm_bo_update(clear=true)` 在 unmap 前同步同 VM command submissions。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c:1548-1575`: `amdgpu_vm_clear_freed()` 清 freed mappings 前同步 same-VM submissions，然后调用 `amdgpu_vm_update_range()` 清 PTE。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_sync.c:181-224`: `amdgpu_sync_resv()` 的 owner-based filtering；`AMDGPU_SYNC_EQ_OWNER` 保留 same-owner fences。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_cs.c:1093-1177`: CS VM handling 先清 freed mappings、更新 per-BO PT、处理 moved BO、更新 PDE，并 sync 到 `bo_va->last_pt_update` 和 `vm->last_update`。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_cs.c:1339-1355`: user job submit 后，CS path 把 gang job fences 添加到 locked object 的 reservation object。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c:1050-1081`: `amdgpu_vm_tlb_flush()` 更新 VM TLB sequence，并在需要 TLB fence 时保证 page-table object 不会早于 flush 被释放。
- `drivers/gpu/drm/amd/amdgpu/amdgpu_ids.c:256-307` and `drivers/gpu/drm/amd/amdgpu/amdgpu_ids.c:321-366`: VMID grab path 比较 VMID flushed state 和 `amdgpu_vm_tlb_seq(vm)`，必要时把 job 标为 `vm_needs_flush`。
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]: background on `dma_resv` as a per-buffer fence container with owner/usage-scoped synchronization.
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]]: related amdgpu example of using fences to create a quiescent point before memory-management-visible state changes.

## Uncertainty

这篇笔记只覆盖普通 GEM/BO GPUVM PTE/TLB synchronization model。KFD/SVM/HMM、replayable fault、user queue 以及具体 ASIC VM hub 的更细路径可能补充额外同步语义，但不改变这里对普通 BO mapping path 的结论。

## Related Pages

- [[wiki/projects/linux-drm-amdgpu]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]]
- [[wiki/inspections/linux-amdgpu-userq-bo-mmap-vs-eviction-manager]]
- [[wiki/index]]
