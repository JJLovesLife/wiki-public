---
type: inspection
title: "linux RCU: RCU-published structures with refcounted child objects"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-04-29
scope_paths:
  - drivers/dma-buf/dma-resv.c
  - include/linux/dma-resv.h
  - include/linux/dma-fence.h
  - drivers/dma-buf/dma-fence.c
  - include/linux/kref.h
  - Documentation/RCU/whatisRCU.rst
  - Documentation/RCU/rcuref.rst
---

## Question

RCU 发布的父结构里如果包含 refcounted 子对象指针，reader 和 writer 应该怎样配合？以 `dma_resv_list` 里的 `dma_fence` 为例，为什么 writer 要先发布新 list，再 drop 已删除 fence 的引用，而 reader 又要在 RCU read-side 中用 `kref_get_unless_zero()` 抢引用？

## Answer

这种模式要把两个生命周期分开看：父级 lookup structure 的可见性由 RCU 保护，子对象的长期使用由引用计数保护。RCU 让 reader 可以无锁地找到当前 published 父结构和其中的子指针；引用计数让 reader 在离开 RCU read-side 之后还能安全使用子对象。

在 `dma_resv` 中，`obj->fences` 是 RCU 发布的 `struct dma_resv_list`，而 `table[]` 里存的是 `struct dma_fence` 指针和 usage 编码。writer 扩容或清理 list 时，会把仍未 signaled 的 fence 复制到新 list 的有效区间，把已经 signaled 的 fence 暂存在新数组尾部，然后先执行 `rcu_assign_pointer(obj->fences, new)`，最后再 `dma_fence_put()` 那些 signaled fence。

这个顺序的核心不是“必须等 RCU grace period 才能 put”，而是“不能在子对象仍从当前 published lookup structure 可达时，先释放父结构持有的那份引用”。发布新 list 后，新 reader 不会再通过 `obj->fences` 找到被删除的 signaled fence；已经拿到旧 list 的 reader 仍受 RCU 保护，可以尝试 `dma_fence_get_rcu()`。如果 writer 的 `put` 已经把 refcount 降到 0，`kref_get_unless_zero()` 会失败，reader 会重启到新的 RCU 视图。

这个模式还要求被 RCU lookup 的子对象在 refcount 归零后不能立即让 RCU reader UAF。`dma_fence` 的默认释放路径最终调用 `kfree_rcu(fence, rcu)`，所以旧 reader 在 RCU read-side 中仍能安全访问 refcount 字段并失败返回。若子对象只用普通 refcount 且 refcount 到 0 立即 `kfree()`，则不能采用这种“发布新父结构后马上 put 子引用”的模式；需要把 `put` 延后到 grace period 之后，或改变 lookup/locking 规则。

这里的 “RCU-safe” 不是说旧 reader 在没有真实 fence 引用时还能随意使用整个子对象；它只保证 lookup 和 `get_unless_zero` 这段窗口不会因为内存立即回收而 UAF。`dma_fence` 的注释明确说 callback list / timestamp 等状态需要持有真实 fence 引用，而不能只靠 `rcu_read_lock()` 访问。因此 reader 成功 get 后才能把 fence 带出 RCU read-side；get 失败时只能重启或放弃，不能继续使用那个 child。

总结规则：RCU 保护“找到指针并尝试取得引用”的窗口，refcount 保护“取得引用后的使用期”。writer 需要先从当前 published lookup structure 中 unlink 子对象，再 drop 可能是最后一个的引用；如果还允许旧 RCU reader 看到旧父结构，则子对象释放路径也必须对 RCU lookup 安全。

更一般地说，`kfree_rcu(parent)` 只延迟释放父结构那块内存，不会自动延迟释放 `parent->child` 指向的对象。若 child 只是普通 refcounted 对象，且最后一次 `put` 会立即 `kfree(child)`，writer 就不能在旧父结构还可能被 RCU reader 看到时立即 drop 父结构持有的 child 引用。可选模式是：要么把 child 的 finalization 也延迟到 grace period 之后（例如用 `call_rcu()` 回调同时释放旧父结构并 `put` child，或者 `synchronize_rcu()` 后再 drop 初始引用），要么 child 自身的最终释放路径使用 RCU-safe reclamation。Linux 的 `Documentation/RCU/rcuref.rst` 把这两类分别展示成 listing C 和 listing B：listing C 延迟删除方的初始引用，允许 reader 找到对象后无条件 get；listing B 允许删除方在移除后立即 drop 引用，但 reader 必须用 `atomic_inc_not_zero()`/`kref_get_unless_zero()`，且对象最终通过 `call_rcu()` 回收。

### 时序对照

`dma_resv` 这种“立即 put + child RCU-safe release”的安全时序：

| 步骤 | 操作者 | 动作 | fence A 状态 | 结论 |
| --- | --- | --- | --- | --- |
| 1 | 旧 reader | 在 RCU read-side 中看到旧 list 和 A，还没 get | A refcount > 0 | A 仍从旧 list 可见 |
| 2 | writer | 发布不含 A 的新 list | 新 reader 找不到 A | A 已从当前 lookup set 移除 |
| 3 | writer | `dma_fence_put(A)` | 若归零则进入 `kfree_rcu(A)` | A 内存仍保留到 grace period 后 |
| 4 | 旧 reader | `dma_fence_get_rcu(A)` | 成功则持有真实引用；失败则重启 | 不会复活已归零对象，也不会 UAF |

只有父结构 `kfree_rcu()`、child 普通立即释放的危险时序：

| 步骤 | 操作者 | 动作 | child A 状态 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | 旧 reader | 在 RCU read-side 中看到旧 parent | A 仍被旧 parent 指向 | parent 受 RCU 保护 |
| 2 | writer | 发布新 parent，`kfree_rcu(old_parent)` | old parent 延迟释放 | 只保护 parent 内存 |
| 3 | writer | 立即 `child_put(A)` | 若归零则立即 `kfree(A)` | A 不受 parent 的 `kfree_rcu()` 保护 |
| 4 | 旧 reader | 继续访问 `old_parent->child` 或尝试 get A | A 可能已释放 | UAF |

延迟初始引用的保守安全时序：

| 步骤 | 操作者 | 动作 | child A 状态 | 结论 |
| --- | --- | --- | --- | --- |
| 1 | writer | 从 lookup structure 移除 A | 父/容器引用仍保留 | 新 reader 找不到 A |
| 2 | writer | `call_rcu()` 或 `synchronize_rcu()` | A refcount 仍非零 | 旧 reader 仍可完成 lookup + get |
| 3 | 旧 reader | 退出 RCU read-side，或已拿到真实引用 | 若拿到引用则自行 put | RCU lookup 窗口结束 |
| 4 | writer/callback | grace period 后 drop 初始引用 | 归零时可普通释放 | 不再有旧 RCU reader 触碰 A |

## Trace

1. `dma_resv_list` 是 RCU-published 父结构，`table[]` 存放 RCU 指针；`dma_resv_list_set()` 把 fence 指针和 usage 编码到同一个 entry 中。
2. `dma_resv_reserve_fences()` 分配新 list 时不额外 get fence，而是把旧 list 持有的引用转移到新 list。未 signaled fence 进入新 list 的有效区间，signaled fence 只暂存在尾部等待后续 put。
3. `new->num_fences = j` 只覆盖新数组前半部分，所以尾部 signaled fence 不再属于 reservation object 的有效 fence 集合。
4. writer 先用 `rcu_assign_pointer(obj->fences, new)` 发布新 list，再遍历尾部暂存区 `dma_fence_put()` signaled fence，最后用 `kfree_rcu(old, rcu)` 延迟释放旧 list。
5. unlocked iterator 在 RCU read-side 中读取 list entry，然后调用 `dma_fence_get_rcu()`。成功后 cursor 持有真实 fence 引用，函数可以释放 RCU read lock 并返回 fence 给调用者。
6. 如果 `dma_fence_get_rcu()` 失败，iterator 会 restart。外层还会检查 `dma_resv_fences_list(cursor->obj) != cursor->fences`，确保与 writer 并发修改重叠时切换到新的 RCU 视图。
7. `dma_fence_get_rcu()` 使用 `kref_get_unless_zero()`，它只在 refcount 非零时增加引用；这防止 reader 复活已经进入释放路径的 fence。
8. `kref_get_unless_zero()` 的注释说明它就是给“从 lookup structure 查对象，然后尝试加引用”的场景用的，但 RCU 版本需要对象内存本身在 lookup 窗口中仍安全。
9. `dma_fence_put()` 通过 `kref_put()` 进入 `dma_fence_release()`；默认 release 最终调用 `dma_fence_free()`，而 `dma_fence_free()` 使用 `kfree_rcu()` 延迟释放 fence 内存。
10. 因此，发布新 list 后立即 put 被删除 fence 是安全的：新 reader 不再能从当前 `obj->fences` 找到它，旧 reader 即使已经持有旧 list，也能在 RCU read-side 中安全地让 `kref_get_unless_zero()` 成功或失败。
11. `dma_fence` 只把 fence 内存释放延迟到 RCU grace period；它并不允许 RCU-only reader 使用所有 fence 内部状态。`dma_fence` 注释要求 callback list / timestamp 这类状态必须持有真实 fence 引用才能读。
12. RCU 文档还给出一个更保守的替代模式：删除方先从 lookup structure 移除对象，但把“删除初始引用/最后释放”推迟到 grace period 之后。这样 reader 只要在 RCU read-side 中找到对象，就能安全地取得长期引用；代价是 finalization 被 RCU callback 或 `synchronize_rcu()` 延后。
13. `dma_resv` 走的是更偏 listing B 的模式：signaled fence 从新 published list 的有效集合中移除后，writer 可以立即 `dma_fence_put()`；安全性来自 reader 的 `dma_fence_get_rcu()` 失败重试，以及 `dma_fence` 默认释放路径的 `kfree_rcu()`。

## Evidence

- `drivers/dma-buf/dma-resv.c:63-92`：`struct dma_resv_list` 的 `table[]` 是 RCU fence 指针数组，`dma_resv_list_entry()` / `dma_resv_list_set()` 负责解码和编码 fence 指针加 usage。
- `drivers/dma-buf/dma-resv.c:209-224`：`dma_resv_reserve_fences()` 明确说明旧 list 的 fence 引用 carried over 到新 list；未 signaled fence 用 `dma_resv_list_set()` 保留，signaled fence 用 `RCU_INIT_POINTER(new->table[--k], fence)` 暂存。
- `drivers/dma-buf/dma-resv.c:225-248`：`new->num_fences` 只包含未 signaled fence；随后先 `rcu_assign_pointer(obj->fences, new)`，再 `dma_fence_put()` 尾部 signaled fence，并 `kfree_rcu(old, rcu)`。
- `drivers/dma-buf/dma-resv.c:377-405`：unlocked iterator 在 RCU read-side 中读取 fence entry，并用 `dma_fence_get_rcu()` 取得真实引用；失败时 restart。
- `drivers/dma-buf/dma-resv.c:420-456`：`dma_resv_iter_first_unlocked()` / `dma_resv_iter_next_unlocked()` 在 RCU lock 下遍历，并在 list 指针变化时重启。
- `include/linux/dma-resv.h:274-287`：unlocked fence iterator 的文档说明它用 RCU 而不是 `dma_resv.lock`，并且 iterator 内部会持有 fence 引用、释放 RCU lock 后返回。
- `include/linux/dma-resv.h:321-328`：`dma_resv_lock()` 文档说明该锁只保护 writers，readers 会在 RCU 下与 writer 并发运行。
- `include/linux/dma-fence.h:289-318`：`dma_fence_get_rcu()` 用 `kref_get_unless_zero()` 在 RCU read lock 下尝试获取 fence 引用。
- `include/linux/dma-fence.h:320-351`：`dma_fence_get_rcu_safe()` 的注释说明 RCU lookup 中可能遇到 grace period 内的重分配问题，成功 get 后还要确认 RCU 指针仍匹配。
- `include/linux/dma-fence.h:75-82`：`dma_fence` 注释说明 callback list / timestamp 等内部状态必须持有真实 fence 引用才能读，不能只依赖 `rcu_read_lock()`。
- `include/linux/dma-fence.h:266-273`：`dma_fence_put()` 通过 `kref_put()` 调用 `dma_fence_release()`。
- `drivers/dma-buf/dma-fence.c:555-615`：默认 `dma_fence_release()` 在没有自定义 release 时调用 `dma_fence_free()`，而 `dma_fence_free()` 使用 `kfree_rcu(fence, rcu)`。
- `include/linux/kref.h:115-127`：`kref_get_unless_zero()` 的注释把它定位为 lookup structure 中查对象并加引用的辅助机制，并提醒 RCU implementations become tricky。
- `Documentation/RCU/whatisRCU.rst:943-958`：RCU read-side 中 `rcu_dereference()` 得到的引用可以视为临时阻止对象 type 改变的引用，并可用 `kref_get_unless_zero()` 取得长期引用。
- `Documentation/RCU/whatisRCU.rst:990-998`：传统 refcount 对象在 RCU 下使用时，最后引用触发的 finalization 必须等所有 `__rcu` 可见指针更新且经过 grace period 后运行。
- `Documentation/RCU/rcuref.rst:47-78`：listing B 说明 RCU lookup 下 reader 应使用 `atomic_inc_not_zero()`，对象 refcount 归零时通过 `call_rcu()` 延迟释放。
- `Documentation/RCU/rcuref.rst:86-126`：listing C 说明另一种选择是把删除方的初始引用 drop 延迟到 RCU callback，从而让找到对象的 reader 可以无条件增加引用。
- `Documentation/RCU/rcuref.rst:139-154`：如果删除路径允许睡眠，也可以用 `synchronize_rcu()` 后再 drop 初始引用并释放对象。

## Uncertainty

`dma_fence_ops.release` 可以由具体 fence 实现自定义；本页只确认默认 `dma_fence_free()` 使用 `kfree_rcu()`，并把“用于 RCU lookup 的 fence release 必须保持 RCU-safe lifetime”作为由该 lookup 模式要求出的约束。没有逐一审计所有自定义 fence release。

## Related Pages

- [[wiki/inspections/linux-rcu-grace-period-pointer-publication]]
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]]
- [[wiki/index]]
