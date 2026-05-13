# CPU Store Buffer, L1 Cache, And Pipeline

## Question

CPU 中的 store buffer 是什么？它和 L1 cache 有什么区别？为什么需要它？它主要是流水线造成的，还是乱序执行的产物？

## Answer

Store buffer 是每个 CPU core 私有的、临时保存 store operation 的队列。一个 store 的地址和数据准备好之后，不一定能立刻写进 L1 D-cache 或让其它 core 看到；它可能需要等待 cache line writable ownership、等待 store miss 的 read-for-ownership、等待 invalidation/ack、等待 cache port、等待更早的 store，或者等待 memory-ordering 规则允许它对外可见。Store buffer 就是在这段时间里保存该 store 的地方。

它和 L1 cache 的区别是：L1 D-cache 是 cache line 的存储结构，带 tag、state、replacement、coherence state，服务普通 load/store hit；store buffer 是 store 指令的临时队列，通常保存 address、data、byte mask、age/order 等信息。L1 cache 保存的是可被 coherence protocol 管理的 cache-line 副本；store buffer 保存的是本 core 尚未完全 drain 到 cache/coherence domain 的写入。其它 core 一般不能直接从你的 store buffer 读值；同一个 core 的后续 load 如果命中同地址，可以通过 store-to-load forwarding 从 store buffer 取到自己的未 drain 写入。

严格说，store buffer entry 本身通常不算 cache coherence protocol 管理的 cache-line 副本。Coherence 管的是各级 coherent cache 或 coherent memory system 中某个 cache line 的 ownership、invalidation、update 和观察顺序；store buffer 是本 core 的私有写入队列，不会像 L1 line 那样对其它 core 提供 Shared/Exclusive/Modified 副本。因此，其它 core 不会通过 coherence snoop 直接把你的 store buffer 当成一个可读 cache 副本。

但 store buffer 不能绕开 coherence。当 entry 要 drain 成全局可见写入时，它必须获得或使用该 cache line 的 writable ownership，并按该 ISA 的 memory ordering 规则与其它 store/load/fence 排序。从软件可见语义看，store buffer 的存在会影响“什么时候可见”和“哪些重排结果允许”，但最终一旦写入进入 coherent cache/memory domain，就必须落入 coherence order。可以概括为：store buffer 里的 pending store 尚未完全进入 coherence domain；drain 过程必须遵守 coherence。

Store buffer 的主要用途是把 store instruction 的执行/退休和真正完成 cache/coherence 写入解耦。写入比寄存器 ALU operation 慢得多：如果 line 已经在本 core 的 L1 里并处于 Modified/Exclusive 状态，drain 可能很快；如果 line 缺失或只处于 Shared 状态，就要先发起 ownership 请求并让其它副本失效。没有 store buffer，流水线常常会在每个 store 上等待这些动作完成，吞吐会很差。

它也帮助维持 precise state 和 speculation 边界。乱序 CPU 不能让一个 speculative store 在指令确认不会 fault、不会被 branch mispredict 冲掉之前修改全局可见的 cache 状态。因此乱序设计通常有 store queue/load-store queue 来保存尚未退休的 store，并在退休后让 store 进入或变成可 drain 的 store buffer entry。不同资料会把这些结构统称为 store buffer，或者把 speculative store queue 和 retired store buffer 分开说。

所以，store buffer 不是单纯的乱序执行产物。更根本的原因是：流水线 CPU 面对 cache/coherence/memory 的写入延迟，需要一个弹性缓冲来避免 store 把整个 pipeline 卡住。早期或简单的 in-order pipelined CPU 也可以有 write buffer/store buffer。乱序执行让它更重要，并额外引入了 speculative store、precise exception、memory disambiguation、store-to-load forwarding 等复杂性。

对 memory ordering 来说，store buffer 解释了为什么“本 core 的 store 已经执行/退休”不必等于“其它 core 已经能看到”。例如经典 store-buffering litmus：

```text
Initial: x = 0, y = 0

Core 0: x = 1; r1 = y
Core 1: y = 1; r2 = x
```

如果两个 store 都暂时停在各自 core 的 store buffer 里，后续 load 可以先从 cache/coherence domain 读到旧值，于是 `r1 = 0, r2 = 0` 在允许 StoreLoad 重排的模型里可能出现。x86 TSO 也允许这种结果，但通常要求单个 core 的 stores 以 FIFO 顺序对外 drain；更弱的 ISA 可以允许更多重排。Fence、locked operation 或更强的 memory-ordering primitive 通常会约束或等待 store buffer drain。

同地址的 `store X = 1; load X` 是另一个容易混淆的情况。如果 store 地址和数据已经在 store buffer 或 store queue 中，后面的 load 通常会通过 store-to-load forwarding 直接读到自己的 `1`，而不是等这个 store drain 到 L1 再从 L1 读。之后另一个 core 获得该 cache line 的 ownership 并写入 `X = 2`，可能会 invalidate 本 core 的 L1 copy，但这不自动破坏已经从本 core store buffer forward 出来的 load 结果。该 load 可以被解释为在 coherence order 中读到了本 core较早的 `X = 1`，而另一个 core 的 `X = 2` 排在后面；retirement 时间晚于 invalidation 并不等于 load 的内存读取点也晚于 invalidation。

Cache coherence 的“读最新值”不是按现实物理时间或 instruction retirement 时间定义的。它通常要求同一 cache line 或 location 的写入存在一个所有 core 都能遵守的 coherence order，并要求 load 返回一个在该架构 memory model 下合法的写入值。对 `store X = 1; load X` 来说，load 从同 core 的 older store forwarding 到 `1`，可以对应为 load 的内存读取事件发生在 `B: store X = 2` 之前，或者至少读取了程序序中必须先于它的 local store。即使现实中 `B: store X = 2` 的 ownership/invalidation 消息在 A 的 load retirement 前完成，也不自动让 `A: load X -> 1` 变成违反 coherence 的“没读最新值”。

换句话说，硬件要保证最后暴露给软件的执行结果能映射到一个合法的抽象顺序，而不是让每条 load 在退休瞬间重新按墙钟时间读取一次全系统最新值。如果某个实现让 `B: store X = 2` 已经在 coherence order 中排在 `A: load X` 的读取事件之前，并且 memory model 又不允许 A 的 load 仍读 `1`，那才需要通过 replay、squash 或更保守的执行来避免暴露这个结果。

需要 replay 或 flush 的典型情况不是“别的 core 后来 invalidate 了这条 line”，而是本 core 的投机执行违反了本 core 必须维护的依赖或 ordering。例如乱序 CPU 先执行了一个 load，后来发现前面有一个同地址 store，本应从该 store forward；或者发现 store address disambiguation 猜错；或者某些强 ordering 场景要求更保守处理。这时 CPU 会 replay/load squash 或 pipeline flush。外部 invalidation 只说明本 core 的 cache line 副本失效；它不等于所有已经完成取值、且在内存模型中可合法排序的 load 都必须重做。

因此要区分两种“invalidate”。Coherence invalidation 是让某个 cache line 副本失效，例如 A 的 L1 不能再持有 `X` 的旧副本；load replay/squash 是处理器内部撤销一条投机 load 的执行结果。前者可能发生而后者不发生。对于 `A: store X = 1; load X -> 1` 这种同地址、从 older local store forwarding 的情况，外部 `B: store X = 2` 造成的 cache-line invalidation 通常只影响 A 后续再访问 `X` 时要重新取 line，不会自动撤销已经合法 forward 到 `1` 的 load。

一个 spin-loop 例子能说明同地址 store-load 和同步语义的区别：

```c
while (true) {
  waiting = true;
  while (waiting) {
    // spin
  }
  // do something
}
```

如果编译器确实每次都生成 memory access，那么 `waiting = true` 后面的第一次 `load waiting` 是同地址 store-load。CPU 通常不需要在这条 load 前 drain store buffer；它可以从本 core 的 older `store waiting = true` 做 store-to-load forwarding，或者至少等待这个 older store 的地址/数据确定后再执行 load。因此第一次 load 会看到自己的 `true`，而不是为了“读最新值”强制等 store 对其它 core 可见。

如果这个 store entry 还在 store buffer 或 store queue 里，后续若干次同地址 spin loads 也可能继续从它 forward 到 `true`。这不违反 coherence，因为这些 load 在本 core 的程序序中确实位于 `store waiting = true` 之后；在 store 还没有 drain 之前，处理器允许本 core 先读到自己的写入。乱序执行和分支预测还可能让有限个后续循环迭代的 loads 提前进入窗口并取到这个 forwarded value。

但 forwarding 不是把某次 load 的结果复制后无限复用。每条 load 执行时都会检查当前仍然存在的 older matching store entry。等 `store waiting = true` drain 到 coherent cache/memory domain 并从 store buffer 中移除后，后面的 loads 就没有这个 entry 可以 forward；它们要从 L1/coherence path 取值。如果另一个 core 的 `waiting = false` 在 A 的 store 之后进入 coherence order，它会 invalidate 或更新 A 的相关 cache line，A 后续真正访问 L1 时不能继续命中旧的 `true` 副本。处理器可以通过乱序执行、分支预测或 loop speculation 让有限个后续迭代的 loads 已经在 store drain 前执行并 forward 到 `true`，但这只是窗口内已执行的动态 load，不是一个可以让未来 load 永远跳过 L1 的机制。

`load Y; do something; load Y` 通常没有类似 store-to-load forwarding 的架构必要性。没有 older matching store 时，第二个 load 正常走 load pipeline，探测 store queue 发现无匹配后从 L1/coherence path 取值；如果 cache line 仍有效并在 L1，就 L1 hit。如果期间有外部 store 使该 line invalid，第二个 load 就不能合法命中旧 line。某些研究或特定实现可能做 load value prediction、load elimination 或稳定 load 优化，但这类机制必须能被 store/snoop/invalidation 或后续验证约束；它不是普通 store buffer forwarding，也不是软件可依赖的语义。

还有一种可能的微架构解释是：load queue 会记录尚未 retire 的 in-flight loads，并监听或接收与这些 load 地址相关的 coherence invalidation/snoop；如果某条投机 load 在架构上还不允许提交，而期间相关 cache line 被外部写入 invalidated，处理器可以用 load replay、machine clear 或 pipeline squash 来避免暴露不合法结果。这个模型和“后续新 load 没有 store-buffer entry 可 forward，于是重新从 L1/coherence path 取值”的模型并不矛盾：前者处理已经提前执行但尚未 retire 的动态 loads，后者描述 store entry drain 之后未来新 loads 的正常取值路径。

本页把这两种说法都标记为讨论中的候选解释。它们最初都来自本次 LLM 对话中的推理；当前 web search 对“store-to-load forwarding 只来自仍存在的 older store-buffer/store-queue entry，entry drain 后不再 forward”有更直接的公开材料支持，而“load queue 监听 invalidation 并据此冲刷”的具体实现细节仍需要更强的厂商手册、论文或实测证据确认。无论采用哪种解释，结论都不是“spin loop 会永远读到之前 store 的值”：要么 store entry 消失后后续 load 重新走 L1/coherence path，要么已经投机执行的相关 load 会在 invalidation/order-violation 检测下被 replay 或 squash。

还有一种 race 是 lost wakeup：如果另一个 core 的 `waiting = false` 在 A 的 `waiting = true` 真正对外可见之前已经发生，而 A 的 `true` 后来才 drain，那么 coherence order 可以把 `false` 排在 `true` 前面，最终值就是 `true`。A 后续一直读到 `true` 并不是硬件没有读取 L1 最新值，而是这个协议本身允许 A 的 later store 覆盖了 B 的 earlier clear。要避免这类问题，需要清晰的 atomic handshake、atomic exchange、condition variable/futex，或在特定低层协议中使用 full barrier 让 `waiting = true` 对外可见后再检查条件。

之后 spin loop 中的后续 loads 不再是紧跟那个 store 的同一条 load；它们会反复读取 coherent cache/memory domain 中当前可见的值。如果另一个 core 写 `waiting = false`，coherence 会让 A 的相关 cache line 失效或更新，A 后续某次重新取值时才能看到 `false` 并退出。是否需要 barrier 不取决于“同地址 store 后 load 必须 drain store buffer”，而取决于语言和 ISA 的同步语义：在 C/C++ 中普通共享变量会造成 data race，正确写法应使用 atomic；如果 `waiting` 只是轮询一个 flag，常见最低要求是 `store(true, memory_order_relaxed)` 和循环中的 `load(memory_order_acquire)` 或 `load(memory_order_relaxed)`，具体取决于退出后是否要看到另一个线程在写 `false` 前发布的数据。Acquire/release 或 fence 用来约束跨地址可见顺序，不是为了让同地址 load 看见自己的 store。

## Evidence

- This page is a provisional architecture synthesis from the 2026-05-13 store-buffer discussion. No dedicated raw architecture source has been ingested yet.
- [[wiki/concepts/cache-coherence]] defines coherent cacheable memory as requiring writable cache-line ownership for writes, which is the condition a store buffer often waits for before draining a store into L1/coherence state.
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]] explains why a core usually needs writable ownership before updating a coherent cache line, and why memory ordering is separate from per-location coherence.
- The key boundary captured here is that pending store-buffer entries are core-private state before they drain, while drained stores must still join the coherent cache line's ordering and ownership rules.
- Same-address store-to-load forwarding lets a later load read an older local store before the store drains to coherent cache state; a later external invalidation of the cache line does not by itself invalidate that forwarded read.
- Coherence and memory consistency are defined over legal abstract ordering and read-from relations, not over the wall-clock time at which a load retires.
- Intel's Optimization Reference Manual documents store forwarding as a load/store datapath optimization, and public discussions of Intel memory ordering describe stores as becoming globally visible when they commit from the store buffer to L1 D-cache; after that, store-to-load forwarding no longer finds that store-buffer entry.
- StuffedCow's x86 memory-disambiguation measurements describe the common mechanism as each load checking the store queue for an older same-address store, otherwise reading from the memory system.
- The load-queue invalidation/replay explanation is recorded as a plausible implementation mechanism from the discussion, not yet as a source-backed claim; it needs vendor documentation, architecture-manual wording, or targeted measurements before being treated as confirmed for a specific CPU family.

## Follow-Ups

1. Ingest architecture-specific source notes for x86 TSO, Arm, or RISC-V memory ordering and store-buffer terminology.
2. Distinguish store buffer, store queue, load-store queue, write-combining buffer, and dirty eviction/writeback buffer using vendor documentation.
3. Add litmus-test examples showing which outcomes are allowed by x86 TSO versus weaker memory models.
4. Find source-backed details on whether and how specific CPU families use load-queue snoop/invalidation tracking to replay or squash in-flight loads.

## Related Pages

- [[wiki/concepts/cache-coherence]]
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]]
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]]
- [[wiki/index]]
