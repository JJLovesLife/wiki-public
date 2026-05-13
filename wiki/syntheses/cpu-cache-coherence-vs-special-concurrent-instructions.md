# CPU Cache Coherence Vs Special Concurrent Instructions

## Question

想讨论的问题不是某个具体 ISA 的细节，而是：为什么通用 CPU 通常要为普通 cacheable memory 实现硬件 cache coherence，而不是把一致性问题交给编译器、语言或程序员，只在识别到 `并发变量` 时才使用特殊读写指令？

一个设想中的替代方案是：普通变量继续使用本地 cache；如果编译器识别出某个变量会被并发访问，就对这个变量生成专门指令。读取这个变量时，不直接相信本地 cache，而是广播一个请求，去其它核心或某个共享仲裁点拿这个变量的最新值。写入这个变量时，也使用专门写指令，可能需要把写入广播给其它核心，或者等所有需要这个变量的核心都被刷新、更新或失效之后，才认为写完成。

这个设想马上遇到几个问题。第一，如果多个其它核心都写过同一个变量，例如 B 和 C 都各自写了值，那么所谓 `最新值` 应该从谁那里拿？是否必须先存在一个全局顺序来决定 B 的写在前、C 的写在后，或者反过来？

第二，如果专门写指令确实要广播到所有核心才算完成，那么它本质上似乎已经在做一种显式的一致性协议。但如果系统没有使用特殊地址空间，也没有强制所有访问都必须使用这种专门指令，那么某些核心仍然可能用普通指令写这个地址。这时混用普通访问和专门访问会怎样？

具体例子是：变量 `x` 初始为 `0`，核心 D 用普通方式把 `x` 从 `0` 写成 `1`，核心 E 也用普通方式或没有被编译器识别出的方式把 `x` 从 `0` 写成 `2`。之后核心 A 执行一个所谓的原子读或 `读取最新值` 指令，它应该读到什么？如果它随机问到 D 并读到 `1`，那 E 本地 cache 里的 `2` 又应该怎么办？E 是否继续认为自己的 `2` 是最新的？如果允许这种情况，系统里就会同时存在多个互相冲突的最新版本。

## Answer

核心原因是：如果没有 cache coherence，`最新值` 这个概念本身就需要额外定义。多个核心可以同时在各自 cache 中持有同一地址的副本，并发写入时必须有一个仲裁机制决定这些写入的顺序。Cache coherence 正是在每个 cache line 层面提供这个仲裁和传播规则。

以变量 `x` 初始为 `0` 为例：

```text
D: x = 1
E: x = 2
A: read x
```

如果 D 和 E 都只在本地 cache 中写入，A 所谓的 `read latest x` 没有明确答案。D 可以认为 `1` 是最新值，E 可以认为 `2` 是最新值，A 如果随机读到 D 的 `1`，E 本地的 `2` 又没有被废止或排序。系统里就会同时存在多个互相冲突的 `最新版本`。

Coherence 协议解决的是这个 per-location 问题：同一个 cache line 的写权限在同一时刻必须被某个核心独占，或者经过一个能决定顺序的共享仲裁点。其它核心持有的旧副本会被失效、更新，或者在再次读取时重新获取。因此 D 和 E 的写入会进入某个所有核心都能遵守的顺序：要么 `x = 1` 在前、`x = 2` 在后，要么反过来。A 的读值取决于它在这个顺序中的位置，而不是取决于它碰巧问到了哪个核心。

所谓 `特殊并发变量指令` 并不能绕开这个问题。它最终仍然需要做以下事情之一：

1. 写入时通知其它持有该 cache line 的核心失效旧副本。
2. 写入时更新其它持有该 cache line 的核心副本。
3. 把并发变量放到某个全局仲裁点，所有特殊读写都经由那里完成。

第一种基本就是 invalidate-based coherence。第二种是 update-based coherence。第三种接近 uncached 或集中式目录访问，通常会牺牲大量性能。所以特殊指令不是替代 coherence，而是把 coherence 从透明硬件机制变成显式编程模型。

只依赖编译器识别 `并发变量` 也不够。真实系统里的共享内存不只来自源码里显式标注的 atomic 变量，还包括指针别名、共享库、FFI、`mmap`、shared memory、JIT、内核页表、用户态和内核态共享页、设备 DMA 相关内存，以及被锁保护的普通字段。例如：

```c
pthread_mutex_lock(&m);
x = 1;
pthread_mutex_unlock(&m);
```

这里 `x` 不是 atomic，但它仍然是跨核心共享数据。另一个核心拿到同一把锁之后应当能看到 `x = 1`。如果普通 store 只写本地 cache、不参与 coherence，那么锁本身也无法让被保护的数据可靠可见。

另一个关键问题是混用普通指令和特殊指令。如果某个地址既能被普通 store 写，也能被特殊 concurrent load/store 访问，那么语义很难定义：

```text
D: 普通 store x = 1，只进入 D 的本地 cache
E: 特殊 store x = 2，广播或发布给其它核心
A: 特殊 load x
```

A 应该读 `1` 还是 `2`？如果普通 store 不参与协议，A 可能永远看不到 D 的写入。如果普通 store 也必须参与协议，那就回到了普通 cache coherence。如果规定并发变量必须位于特殊地址空间，并禁止普通指令访问，那么可以定义语义，但会显著增加 ABI、编译器、运行时和程序员的负担，而且这个特殊地址空间内部仍然需要一套 coherence 或 serialization 规则。

因此，通用 CPU 通常选择在硬件层为普通 cacheable memory 提供 coherence。这样普通 load/store 可以享受 cache 性能，锁可以保护普通数据，atomic 可以建立同步关系，OS 可以迁移线程，编译器也不需要提前知道所有运行时共享关系。

需要区分的是，cache coherence 不等于完整 memory ordering。Coherence 主要保证同一个地址的写入顺序和可见性；不同地址之间的可见顺序仍然由 memory model、barrier、acquire/release、sequential consistency 等规则定义。换句话说，coherence 是共享内存语义的地基，atomic ordering 和同步原语是在这个地基上的更高层规则。

## Evidence

- This page is a provisional synthesis from the discussion on 2026-05-13. No dedicated raw source or architecture manual note has been ingested for this topic yet.
- The reasoning depends on distinguishing per-location coherence from broader memory ordering, and on the practical need for locks and ordinary shared data to work without compiler-perfect knowledge of all sharing relationships.
- [[wiki/concepts/cache-coherence]] captures the durable concept-level definition and links this question to later discussion of writable cache-line ownership, atomic read-modify-write operations, and x86 atomic store code generation.

## Follow-Ups

1. Add an architecture-specific source note for x86, Arm, or RISC-V memory model and cache coherence terminology.
2. Compare snooping, directory-based, invalidate-based, and update-based coherence protocols.
3. Clarify how atomic read-modify-write operations relate to cache-line ownership.
4. Explore non-coherent systems such as some GPU, accelerator, DMA, or embedded memory regions, where explicit flush/invalidate remains necessary.
5. Separate `coherence` from `consistency model` using concrete examples such as message passing with `data` and `flag`.

## Related Pages

- [[wiki/concepts/cache-coherence]]
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]]
- [[wiki/index]]
