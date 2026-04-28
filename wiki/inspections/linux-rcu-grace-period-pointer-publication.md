---
type: inspection
title: "linux RCU: 指针发布、grace period 与旧对象回收的关系"
repo: linux
repo_commit: 028ef9c96e96197026887c0f092424679298aae8
inspected_on: 2026-04-23
scope_paths:
  - Documentation/RCU/whatisRCU.rst
  - Documentation/RCU/rcu.rst
  - Documentation/RCU/Design/Requirements/Requirements.rst
  - include/linux/rcupdate.h
  - kernel/rcu/tree.c
  - kernel/rcu/tree_plugin.h
  - kernel/rcu/tiny.c
---

## Question

我对 Linux RCU 的这个理解对不对？

RCU 把“更新可见”和“旧对象回收”拆成两步。RCU 写操作，会先原子发布新指针，但是不能认为已经旧指针已经没人引用了，立刻进行回收。而是需要继续等待所有的 CPU 经过一次 Quiescent State, 因为经过 Quiescent State 的一定已经把旧的引用丢弃了。在这之后就可以认为旧指针不再会有人读取了。

## Answer

你的总结抓住了 Linux RCU 最核心的机制：RCU 确实把“更新对后续 reader 可见”和“旧对象真正回收”拆成两步。更新方先把新版本对象初始化好，再用 `rcu_assign_pointer()` 原子地发布新指针；这一步完成后，新的 reader 只能拿到新指针，但旧的 reader 仍然可能保留旧对象引用，因此此时还不能回收旧对象。

接下来更新方要等待一个 grace period。对同步接口来说是 `synchronize_rcu()`；对异步接口来说是 `call_rcu()` 注册一个 callback，等 grace period 结束后再执行回收。Linux 文档对 grace period 的精确定义是：等待所有在更新发生之前就已经存在的 RCU read-side critical section 结束，而不是等待更新之后才开始的新 reader。

你那句“等待所有 CPU 经过一次 Quiescent State”在非抢占式 RCU 的直觉上基本成立，但更准确的源码口径是：RCU 用 quiescent state 作为判据，证明当前 grace period 已经不再需要等待某个 CPU 或某个被抢占挂起的 reader。对 `TREE_RCU` 来说，grace period 开始时会给当前在线 CPU 建立 `qsmask` 等待位；CPU 一旦报告了属于本次 grace period 的 quiescent state，自己的等待位就会被清掉。等整棵 `rcu_node` 树上的等待位都清空，并且没有 preempted reader 仍在阻塞，grace period 才算真正完成。

因此，更严谨地说，Linux RCU 保证的不是“旧指针已经没人引用，所以立刻 free”，而是“旧对象从共享结构中移除后，要等所有先前可能持有它的 reader 全部退出；quiescent state 和 blocked-reader bookkeeping 是内核用来证明这件事的实现机制”。在 `PREEMPT_RCU` 下，这一点尤其重要，因为 reader 可能在 read-side critical section 中被抢占，此时不光要看 CPU 是否经过 quiescent state，还要跟踪这些被挂起的任务是否排空。

## Trace

1. `Documentation/RCU/whatisRCU.rst` 把 RCU 更新明确拆成 removal 和 reclamation 两阶段：先把旧对象从数据结构中移除或替换，再等 pre-existing readers 完成，最后才安全回收旧对象。
2. 同一文档把五个核心 API 列出来：`rcu_read_lock()` / `rcu_read_unlock()`、`synchronize_rcu()` / `call_rcu()`、`rcu_assign_pointer()`、`rcu_dereference()`。这正对应“reader 访问旧对象”“writer 发布新对象”“reclaimer 延后回收”的三方分工。
3. `rcu_assign_pointer()` 在 `include/linux/rcupdate.h` 中实现为 store-release 风格的发布操作，保证对象初始化先于指针可见性；所以 reader 要么看到旧对象，要么看到新对象，不该看到半初始化的新对象。
4. `rcu_read_lock()` 的注释说明：如果别的 CPU 此时调用 `synchronize_rcu()` 或 `call_rcu()`，它们必须等当前已存在的 read-side critical section 结束；但 callback 可以和之后新开始的 reader 并发执行。这和“只等更新前已经存在的 reader”完全一致。
5. `Documentation/RCU/rcu.rst` 进一步解释了经典直觉：在 non-preemptible RCU 中，一旦某个 CPU 被观察到发生 context switch、进入 user mode 或 idle loop，就能推断它不可能还停留在之前的 RCU critical section 中，因此这些状态被视为 quiescent state。
6. `kernel/rcu/tree.c` 的 `rcu_gp_init()` 启动新 grace period 时，会把各层 `rcu_node` 的 `qsmask` 初始化为当前在线 CPU 的等待集合；也就是说，当前这次 GP 从一开始就显式记录“还在等谁”。
7. CPU 侧的 `note_gp_changes()` / `__note_gp_changes()` 发现新 grace period 后，会根据 `rnp->qsmask` 为本 CPU 设置 `cpu_no_qs` / `core_needs_qs` 等状态，表示本 CPU 在这次 GP 中尚未交卷。
8. 当 CPU 经过 quiescent state 后，`rcu_qs()` 会把本 CPU 的 `cpu_no_qs` 标记清掉；随后 `rcu_check_quiescent_state()` 调用 `rcu_report_qs_rdp()` 把这一事实向上汇报。
9. `rcu_report_qs_rdp()` 和 `rcu_report_qs_rnp()` 会逐层清除 `qsmask` 中对应 CPU 的等待位；如果一路清到根节点且 `qsmask` 归零，说明这次 grace period 等待的 CPU 侧 quiescent states 已全部满足。
10. 但在 `PREEMPT_RCU` 下，还不能只看 CPU。`tree_plugin.h` 说明：如果任务在 RCU read-side critical section 中被 context switch 掉，RCU 会把它挂到 `blkd_tasks` 链表，当前 grace period 必须等这些 predating readers 从链表中排空后才能结束。
11. 因此 `tree.c` 检查 grace period 完成条件时，不仅要求根节点 `qsmask == 0`，还要求 `!rcu_preempt_blocked_readers_cgp(rnp)`。这就是 Linux 当前实现里“所有旧 reader 已结束”的真实判据。
12. 对回收路径，`Documentation/RCU/whatisRCU.rst` 明确写着 `call_rcu()` 会在 grace period 结束后调用回调；示例里先 `rcu_assign_pointer(gbl_foo, new_fp)` 发布新对象，再 `call_rcu(&old_fp->rcu, foo_reclaim)` 延迟释放旧对象。
13. `kernel/rcu/tiny.c` 还给了一个极简版本的直观模型：在 UP + TINY_RCU 下，`call_rcu()` 只是把 callback 排队，`synchronize_rcu()` 只需推进一个 grace-period 序号；这进一步说明“发布”和“回收”在接口语义上就是两步，而不是一次原地更新。

## Evidence

- `Documentation/RCU/whatisRCU.rst:79-110`：把更新拆成 removal / reclamation，两者之间要等待所有先前 reader 完成。
- `Documentation/RCU/whatisRCU.rst:148-154`：列出核心 API：read-side、grace-period wait / callback、pointer publish、pointer dereference。
- `Documentation/RCU/whatisRCU.rst:202-239`：`synchronize_rcu()` 等待所有 pre-existing read-side critical sections，`call_rcu()` 是其异步 callback 版本。
- `Documentation/RCU/whatisRCU.rst:261-270`：`rcu_assign_pointer()` 具备 store-release 语义，先完成对象初始化，再发布指针。
- `Documentation/RCU/whatisRCU.rst:537-580`：`call_rcu()` 示例展示“先发布新指针，再延后回收旧对象”。
- `Documentation/RCU/rcu.rst:6-13`：RCU 的两段式 destructive update 概念说明。
- `Documentation/RCU/rcu.rst:29-47`：quiescent state 的经典解释，以及 preemptible RCU 需要 CPU-local counter / 额外跟踪。
- `Documentation/RCU/Design/Requirements/Requirements.rst:853-856`：quiescent state 的更精确定义，是 RCU 知道某线程不可能仍处于本次 GP 之前 reader 的状态点。
- `include/linux/rcupdate.h:570-579`：`rcu_assign_pointer()` 宏本体使用 `smp_store_release()` 发布新指针。
- `include/linux/rcupdate.h:803-825`：`rcu_read_lock()` 注释说明 `synchronize_rcu()` / `call_rcu()` 只等待并发于调用时的旧 reader，不等待之后新开始的 reader。
- `kernel/rcu/tree.c:1804-1998`：`rcu_gp_init()` 启动新 GP，初始化各层 `qsmask`，为当前在线 CPU 建立等待集合。
- `kernel/rcu/tree.c:1273-1320`：`__note_gp_changes()` 为当前 CPU 设置是否需要为当前 GP 报告 quiescent state。
- `kernel/rcu/tree.c:2498-2521`：`rcu_check_quiescent_state()` 在 CPU 已经过 quiescent state 时调用 `rcu_report_qs_rdp()`。
- `kernel/rcu/tree.c:2442-2487`：`rcu_report_qs_rdp()` 把某 CPU 的 quiescent state 向上报告。
- `kernel/rcu/tree.c:2339-2393`：`rcu_report_qs_rnp()` 逐层清除 `qsmask`；最后一个等待者清空根节点后推进 GP 完成。
- `kernel/rcu/tree.c:2018-2020`：当前 GP 的完成条件之一是根节点 `qsmask` 清零且没有 blocked readers。
- `kernel/rcu/tree_plugin.h:282-290`：`PREEMPT_RCU` 下的 quiescent state 不等价于“当前 task 一定不在 critical section”，还要考虑被阻塞 reader。
- `kernel/rcu/tree_plugin.h:312-320`：任务若在 read-side critical section 中被切走，会进入 `blkd_tasks` 跟踪，当前 GP 需等其排空。
- `kernel/rcu/tree_plugin.h:381-383`：`rcu_preempt_blocked_readers_cgp()` 用 `gp_tasks` 判断是否仍有被抢占 reader 阻塞当前 GP。
- `kernel/rcu/tiny.c:129-183`：TINY_RCU 下的 `synchronize_rcu()` / `call_rcu()` 极简实现，直观展示 grace period 与 deferred callback 的关系。

## Uncertainty

None noted. 需要注意的是，“每个 CPU 经过一次 quiescent state”是帮助建立直觉的说法，但在 Linux 当前 `TREE_RCU` 尤其是 `PREEMPT_RCU` 实现里，更准确的完成条件是“所有等待位清空，且没有 preempted reader 仍在阻塞当前 grace period”。

## Related Pages

- [[wiki/inspections/linux-rcu-child-reference-lifetime]]
- [[wiki/index]]
