# Linux DRM Amdgpu

## Overview

This project hub groups code-reading notes around Linux DRM GPU memory management, especially amdgpu BO/VM synchronization, TTM/dma-buf reservation objects, and adjacent userspace VA-management behavior in libdrm's amdgpu backend.

The current cluster is not a complete map of amdgpu. It is specifically about how buffer objects, GPU virtual addresses, mmap offsets, fences, and user queues interact when memory can be shared, moved, unmapped, or validated asynchronously.

## Repositories And Scope

- `linux` at `028ef9c96e96197026887c0f092424679298aae8`: DRM core, dma-buf, TTM, amdgpu GEM/VM/user queue paths, and RCU/dma_fence supporting mechanisms.
- `libdrm` at `8de45ef60d69472a0f8ba898f91250dac88bb81f`: amdgpu userspace VA allocator behavior in `amdgpu_vamgr.c`.

Primary scope:

- amdgpu BO move and GPUVM synchronization.
- User queue eviction fences as BO/VM quiescent points.
- `dma_resv` and `dma_fence` as shared-buffer synchronization infrastructure.
- DRM allocator helpers such as `drm_mm` and `drm_vma_offset`.
- libdrm amdgpu VA range allocation and capture/replay placement behavior.

Out of scope for now:

- Full KFD/SVM/HMM/replayable fault semantics.
- Full amdgpu command submission and scheduler architecture.
- Mesa RADV userspace driver behavior, except where later pages explicitly connect it to KMD/libdrm state.

## Reading Map

Start with the generic synchronization substrate:

- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]] explains why `dma_resv` exists as a per-buffer `ww_mutex` plus `dma_fence` container for shared, asynchronous, pipelined, and movable DMA buffers.

Then read the amdgpu user queue and BO move path:

- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]] traces how amdgpu attaches per-file eviction fences to BO `dma_resv` objects so TTM/VM memory-management operations can force user queues through a quiescent point.
- [[wiki/inspections/linux-amdgpu-userq-bo-mmap-vs-eviction-manager]] contrasts kernel-visible CPU mmap dependencies with userspace-owned user queue GPU VA references, explaining why mmap can rely on zap-and-refault while user queues need eviction-manager synchronization.

Then read GPUVM mapping update synchronization:

- [[wiki/inspections/linux-amdgpu-vm-pte-update-synchronization]] explains ordinary amdgpu GPUVM PTE/TLB synchronization as job/fence-boundary ordering rather than CPU-style fine-grained TLB shootdown.

Use these concept pages as background for allocator and mmap-offset terminology:

- [[wiki/concepts/drm-mm]] defines `drm_mm` as DRM's caller-owned-node range allocator for abstract address spaces and placement ranges.
- [[wiki/concepts/drm-vma-offset]] explains how DRM fake mmap offsets map back to BOs through `drm_vma_offset`, including per-file access checks.

Use the libdrm note for the userspace VA allocation side:

- [[wiki/inspections/libdrm-amdgpu-vamgr-address-space-split]] explains how libdrm splits amdgpu GPU VA space into low/high and 32-bit/rest buckets, plus `AMDGPU_VA_RANGE_REPLAYABLE` and fixed-base allocation behavior.

Related but not primary:

- [[wiki/inspections/linux-rcu-child-reference-lifetime]] uses `dma_resv_list` and `dma_fence` to explain RCU-published parent structures with refcounted child objects. It is useful background for the RCU/refcount lifetime model behind fence lists, but it belongs more broadly to the Linux RCU cluster.

## Evidence Base

- `linux` inspection pages are anchored to commit `028ef9c96e96197026887c0f092424679298aae8` and cite exact kernel paths such as `drivers/gpu/drm/amd/amdgpu/amdgpu_vm.c`, `amdgpu_eviction_fence.c`, `amdgpu_userq.c`, `include/linux/dma-resv.h`, and TTM/DRM helpers.
- `libdrm` inspection is anchored to commit `8de45ef60d69472a0f8ba898f91250dac88bb81f` and cites `amdgpu/amdgpu_vamgr.c`, `amdgpu_internal.h`, public amdgpu APIs, and the commit that introduced replayable VA allocation behavior.
- The evidence is inspection-backed rather than document-source-backed. The repo snapshots are the source of truth for code-derived claims.

## Open Questions

- How do KFD/SVM/HMM, replayable faults, and PASID paths change or bypass the ordinary GEM/BO GPUVM synchronization model?
- What is the full user queue dependency protocol around `USERQ_WAIT`, `USERQ_SIGNAL`, queue packet BO references, and explicit userspace synchronization?
- How do Mesa RADV, libdrm, and amdgpu KMD divide responsibility for GPU VA allocation, mapping, and queue exposure in current user queue paths?
- Why is `drm_vma_offset` organized around a per-device fake mmap offset namespace instead of a per-file namespace?

## Related Pages

- [[wiki/index]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]]
- [[wiki/inspections/linux-amdgpu-userq-bo-mmap-vs-eviction-manager]]
- [[wiki/inspections/linux-amdgpu-vm-pte-update-synchronization]]
- [[wiki/inspections/libdrm-amdgpu-vamgr-address-space-split]]
- [[wiki/concepts/drm-mm]]
- [[wiki/concepts/drm-vma-offset]]
