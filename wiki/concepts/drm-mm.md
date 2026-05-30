## Definition

`drm_mm` 是 DRM core 里的 range allocator。它管理一个由 driver 定义的抽象地址范围，并用调用者自己拥有的 `struct drm_mm_node` 追踪已经分配出去的 subrange。

核心结构主要是两个：

- `struct drm_mm` - 一个 linear range 的 allocator state。Driver 可以把它 embed 到更大的 memory-manager object 里。
- `struct drm_mm_node` - 这个 range 里的一段 allocated block。Driver 自己 allocate 或 embed 这些 node；`drm_mm` 不替 driver 分配 node memory。

概念上，`drm_mm` 解决的是 non-overlapping interval allocation，不是 backing memory ownership。这个 range 可以代表 GPU virtual address space、VRAM/GTT pages、`mmap()` fake-offset space，或者其他 driver-defined linear resource。

## Why It Matters

`drm_mm` 给 DRM driver 提供了一套通用 allocator，用来处理 GPU 场景里常见的 placement 问题：alignment constraints、range restrictions、top-down / bottom-up placement、pre-reserved firmware ranges，以及可选的 driver-specific color adjustment，例如插入 guard pages 或表达其他 placement restrictions。

它的 public contract 刻意保持很小：用 `drm_mm_init()` 初始化一个 range，insert 或 reserve 调用者拥有的 node，remove node，并在需要时 iterate allocated nodes 或 holes。实现内部维护了几套 search structures，但 caller 应该使用 helper，而不是直接依赖这些 internals。

一个值得记住的实现细节是：allocator 按 address order 维护 nodes，把 holes 作为 metadata 挂在相邻 node 上，并维护 red-black trees 来做 interval lookup 和按 size/address 的 hole search。这些 tree 解释了为什么不同 insertion mode 可以找 best、low、high 或 recently evicted holes，但它们不是主要 API surface。

## Supporting Evidence

- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:55-100`: overview 把 `drm_mm` 描述成一个简单的 DRM range allocator，点名 `drm_mm` 和 `drm_mm_node` 是 main data structures，说明 driver 可以 embed 两者，并且 `drm_mm` 本身不分配 node memory。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:68-94`: 支持 preallocated blocks reservation、alignment 和 range restrictions、color adjustment、top-down / bottom-up allocation，以及 iteration helpers。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:96-99`: `drm_mm` 内部不是 thread-safe；driver 需要用自己的 lock 保护 modification。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_mm.h:148-180`: `struct drm_mm_node` 表示一个 allocated block，对外暴露 `color`、`start`、`size`，其他部分应通过 helper 间接访问。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_mm.h:182-216`: `struct drm_mm` 是 DRM allocator，带可选 `color_adjust` callback 和 private lists / trees，包括 `hole_stack`、`head_node`、`interval_tree`、`holes_size`、`holes_addr`。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `include/drm/drm_mm.h:59-146`: insertion modes 描述了按 smallest fitting hole、lowest address、highest address、most recent eviction 搜索的行为。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:921-954`: `drm_mm_init()` 初始化 managed range 和内部 hole tracking。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:500-613`: `drm_mm_insert_node_in_range()` 搜索合适 hole，应用 range/alignment/color constraints，插入 node，并更新 hole metadata。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/drm_mm.c:621-650`: `drm_mm_remove_node()` 移除 allocated node，并 merge free-hole metadata。
- Linux `028ef9c96e96197026887c0f092424679298aae8`, `drivers/gpu/drm/ttm/ttm_range_manager.c:68-111`, `drivers/gpu/drm/ttm/ttm_range_manager.c:198`: TTM 把 `drm_mm` 用作 resource manager allocation 的 page-range allocator。

## Related Pages

- [[wiki/projects/linux-drm-amdgpu]]
- [[wiki/concepts/drm-vma-offset]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/index]]

## Open Questions

None yet.
