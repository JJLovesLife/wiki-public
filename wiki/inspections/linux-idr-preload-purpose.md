---
type: inspection
title: "linux idr_preload(): what it preloads, why it exists, and how it avoids sleeping allocation under spinlock"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-04-22
scope_paths:
  - include/linux/idr.h
  - lib/idr.c
  - lib/radix-tree.c
  - drivers/gpu/drm/drm_gem.c
---

## Question

`idr_preload` 是什么，为什么 `idr_alloc()` 常常要在 `spin_lock()` 外先 preload，它和可能睡眠的内存分配有什么关系？

## Answer

`idr_preload()` 是给下一次 `idr_alloc()` 预先准备 `IDR` 内部节点内存的辅助路径。它预分配的不是 caller 的对象，也不是一个已经保留好的 ID，而是 `IDR` / radix-tree 为插入新 ID 可能需要的新内部结构。

之所以需要它，是因为 `idr_alloc()` 经常在 caller 自己的锁保护下执行。`lib/idr.c` 也明确把并发修改的同步责任留给 caller。很多 call site 会在 `spin_lock()` 下做 `idr_alloc()`，以便串行化对同一个 `idr` 的修改；但如果这次分配需要把树长高、或者补新的内部节点，内部分配可能走会阻塞的内存分配路径，这和 `spin_lock()` 的“不能睡眠”约束冲突。

因此常见模式是：锁外 `idr_preload(GFP_KERNEL)`，锁内 `idr_alloc(..., GFP_NOWAIT)`，解锁后 `idr_preload_end()`。这样把“可能阻塞的内存准备”挪到锁外，把锁内路径缩成 non-blocking allocate + tree insertion。

这里的“sleep”更准确地说是 “may block”。像 `GFP_KERNEL` 这样的分配如果当场拿不到对象，allocator 可能进入 reclaim / waiting path，并让当前 task 被调度出去；而持有 `spin_lock()` 时不允许发生这种 blocking 行为。相反，`GFP_NOWAIT` 不会阻塞，但如果现场确实需要新节点、而 preload pool 里又没有可用节点，`idr_alloc()` 仍然可能返回 `-ENOMEM`。

`idr_preload()` 还有一个比“提前 `kmalloc`”更具体的实现细节：它把节点填进 per-CPU preload pool，并在返回时保持 preemption disabled，直到 `idr_preload_end()` 为止。这样后续 `idr_alloc(..., GFP_NOWAIT)` 还在同一个 CPU 上执行，`radix_tree_node_alloc()` 才能从当前 CPU 的 preload pool 里把这些节点拿出来用。所以它的 contract 不只是“先 malloc 一下”，而是“先把当前 CPU 的 preload pool 填好，并在真正分配完成前别迁走”。

## Trace

1. `lib/idr.c` 的 `idr_alloc()` 注释明确说，修改 `idr` 的同步由 caller 自己负责，而且分配失败会返回 `-ENOMEM`。
2. `lib/radix-tree.c` 定义了 `IDR_PRELOAD_SIZE`，并维护一个 per-CPU 的 `radix_tree_preloads` pool，说明 preload 不是随便分一块内存，而是给 `IDR` 内部节点准备一组专用缓存。
3. `__radix_tree_preload()` 会在锁外用 caller 提供的 `gfp_mask` 循环分配 `radix_tree_node`，并把它们塞进当前 CPU 的 preload pool。
4. `radix_tree_node_alloc()` 的注释直接要求 caller 已经做过 preallocation，并且当前执行流被 pin 在当前 CPU 上。后续当 `idr_alloc()` 走 non-blocking 分配路径时，它会先尝试一次 non-blocking `kmem_cache_alloc()`；如果失败，就从 `this_cpu_ptr(&radix_tree_preloads)` 取节点。这就是 preload 节点被消费的地方。
5. `idr_preload()` 本身只是对 `__radix_tree_preload(..., IDR_PRELOAD_SIZE)` 的封装；它的注释明确说返回时 preemption disabled，而 `idr_preload_end()` 通过 `local_unlock(&radix_tree_preloads.lock)` 结束这个区间。
6. `drivers/gpu/drm/drm_gem.c` 给出了标准 call pattern：先 `idr_preload(GFP_KERNEL)`，然后在 `table_lock` 这个 spinlock 内调用 `idr_alloc(&file_priv->object_idr, NULL, 1, 0, GFP_NOWAIT)`，最后解锁并 `idr_preload_end()`。

## Evidence

- `lib/idr.c:62-81`：`idr_alloc()` 的 API 注释说明 caller 负责同步，并且失败会返回 `-ENOMEM`。
- `lib/radix-tree.c:55-63`：定义 `IDR_PRELOAD_SIZE` 和 per-CPU `radix_tree_preloads`，说明 preload 有固定的节点预算和专门缓存。
- `lib/radix-tree.c:322-351`：`__radix_tree_preload()` 用给定 `gfp_mask` 分配 `radix_tree_node`，并把节点塞进当前 CPU 的 preload pool。
- `lib/radix-tree.c:232-273`：`radix_tree_node_alloc()` 注释要求 caller 已完成 preallocation 且 pin 在当前 CPU；non-blocking 路径下会从 `this_cpu_ptr(&radix_tree_preloads)` 消费预分配节点。
- `lib/radix-tree.c:1463-1473`：`idr_preload()` 的注释直接写明它是 “preload for idr_alloc()”，并且返回时 preemption disabled，直到 `idr_preload_end()`。
- `include/linux/idr.h:184-192`：`idr_preload_end()` 的注释要求每次 `idr_preload()` 都要成对结束，实际实现是 `local_unlock(&radix_tree_preloads.lock)`。
- `drivers/gpu/drm/drm_gem.c:492-502`：真实 call site 先 preload，再在 spinlock 内 `idr_alloc(..., GFP_NOWAIT)`，最后 `idr_preload_end()`。

## Uncertainty

None noted. 这里的 “sleep” 采用 kernel 常见口径，实际更准确的是 “may block”；某次具体的 `GFP_KERNEL` 分配也可能因为当场就有空闲对象而立刻返回，不一定真的发生调度切换。

## Related Pages

- [[wiki/index]]
