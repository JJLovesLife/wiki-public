## Definition

`drm_vma_offset` 是 DRM helper layer，用来把 fake `mmap()` offset 映射回 buffer object 或其他 driver-owned memory region。它从 page-based fake offset space 里分配 offset，然后让 DRM mmap path 通过 `vma->vm_pgoff` / `pgoff` 找回对应 object。

它构建在 [[wiki/concepts/drm-mm]] 之上：`struct drm_vma_offset_manager` 里有一个 `struct drm_mm`，每个 `struct drm_vma_offset_node` 里有一个 `struct drm_mm_node`。在这个用途里，`drm_mm` 管理的 range 不是实际的 GPU 或 CPU address space，而是 fake file offsets 的 namespace；这些 offset 需要在对应 device `address_space` 里保持唯一。

这个 helper 还追踪 per-open-file access。仅仅 lookup 到 offset 并不够；mmap path 还会检查发起调用的 `struct drm_file` 是否已经被 allow 到这个 node 上。

## Why It Matters

GEM mmap 是一个 two-step protocol。首先 userspace 为 GEM object 取得一个 fake offset，例如通过 map-offset ioctl path。之后 userspace 在 DRM file descriptor 上用这个 offset 调用 `mmap()`。DRM core 再 lookup `drm_vma_offset_node`，把它转回 containing `drm_gem_object`，验证 calling file 的 access，然后 map object。

这把 object identity 和 file-descriptor-local handle 分开了。GEM handle 是 per `drm_file` 的，而 fake mmap offset 存在于 device 的 shared offset manager 里，并由 per-node allowed-file state 保护。因此 `drm_vma_offset` 同时需要一个偏 global 的 offset allocator 和显式 access checks。

Manager 文档也明确警告不要把它用于 VMEM object placement。它负责的是 linear userspace mmap offset namespace，不是 physical memory placement、GPU virtual-address allocation，也不是 BO residency。

## Supporting Evidence

- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:37-69`: vma offset manager 把 arbitrary driver-dependent memory regions 映射进 linear user address space，用 `drm_mm` 做 backend，不能用于 VMEM placement，使用 page-based addresses，并且按 open-file context 管理 access。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_vma_manager.h:32-42`: DRM 为 buffer objects 编造 offsets，让 mmap time 可以识别它们；同处也定义了 fake offset range constants。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_vma_manager.h:52-62`: `struct drm_vma_offset_node` embed `struct drm_mm_node`；`struct drm_vma_offset_manager` embed `struct drm_mm`。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:86-91`: manager initialization 初始化自己的 lock，并在传入的 page-offset range 上调用 `drm_mm_init()`。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:141-176`: locked lookup 遍历 manager 的 `drm_mm` interval tree，寻找覆盖 requested page range 的 best node，并返回 containing `drm_vma_offset_node`。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:202-217`: `drm_vma_offset_add()` 通过调用 `drm_mm_insert_node()` 从 manager 里分配 node。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:230-242`: `drm_vma_offset_remove()` 移除 embedded `drm_mm_node` 并清零。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_vma_manager.c:294-420`: `drm_vma_node_allow()`、`drm_vma_node_revoke()`、`drm_vma_node_is_allowed()` 维护并查询 per-node allowed `drm_file` tag set。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_device.h:348-349`: `struct drm_device` 拥有一个 `vma_offset_manager` pointer。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:153-170`: GEM initialization 分配 device `vma_offset_manager`，并用 `DRM_FILE_PAGE_OFFSET_START` 和 `DRM_FILE_PAGE_OFFSET_SIZE` 初始化它。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_gem.h:323-333`: 每个 `drm_gem_object` 都有 `vma_node`；driver 用 `drm_gem_create_mmap_offset()` 分配 mmap offset，用 `drm_vma_node_offset_addr()` 取回 offset，而 mapping 由带 access checks 的 `drm_gem_mmap()` 处理。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:437-458`: dumb-map-offset path 为 object 创建 fake mmap offset，并把 `drm_vma_node_offset_addr()` 返回给 userspace。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:582-606`: GEM fake mmap offsets 是通过 `dev->vma_offset_manager` 上的 `drm_vma_offset_add()` 分配的。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:1232-1279`: mmap lookup path 在 device vma manager 里按 exact offset 找到 GEM object，尽量取得 reference，并在 calling file 未通过 `drm_vma_node_is_allowed()` 时拒绝访问。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:1327-1360`: `drm_gem_mmap()` 使用 `vma->vm_pgoff` 作为 fake offset，lookup object，然后用 `drm_gem_mmap_obj()` 建立 mapping。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_gem.c:480-517`: GEM handle creation 通过 `drm_vma_node_allow()` 授予该 `drm_file` 对 object `vma_node` 的 access。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/ttm/ttm_device.h:245-248`: TTM 保存 `drm_vma_offset_manager` pointer，作为查找 mmap BO 的 address-space manager。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/ttm/ttm_bo.c:952-961`: TTM 从 device vma manager 为 device 或 sg buffer object 分配 vma offset。

## Related Pages

- [[wiki/projects/linux-drm-amdgpu]]
- [[wiki/concepts/drm-mm]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/index]]

## Open Questions

- `drm_device.vma_offset_manager` 是 per-device 的，而 `mmap()` 是通过 per-file-descriptor 的 `struct drm_file` 发起的。当前 evidence 只能说明 offset namespace 由 device 管理，并通过 `drm_vma_node_allow()` / `drm_vma_node_is_allowed()` 做 per-file access filtering；但为什么 fake mmap offset namespace 要按 device / `address_space` 管理，而不是 per fd 管理，还需要之后单独 inspection。
