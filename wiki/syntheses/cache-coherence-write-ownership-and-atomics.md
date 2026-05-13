# Cache Coherence Write Ownership And Atomics

## Question

在 cache coherence 下，如果两个 core 都从 `x = 0` 出发并发写入，例如 Core A 想写 `0 -> 1`，Core B 想写 `0 -> 2`，A 先获得写入优先权之后 B 应该怎么处理？这和普通 store、atomic read-modify-write、x86 上 `atomic.load`/`atomic.store` 的实现，以及 coherence 是否只针对单个地址或 cache line 有什么关系？

## Answer

在 coherent cacheable memory 上，写入不是直接修改一个可以被多个 core 同时当作最新版本的共享副本。一个 core 写 cache line 前通常要先获得 writable ownership，例如 MESI-like 协议中的 exclusive 或 modified 状态。如果本 core 已经拥有可写状态，普通 store 可以直接更新本地 cache line；如果只有 shared 副本或没有该 line，就需要发起 read-for-ownership 或 invalidate 请求，让其它副本失效、更新，或经过目录/仲裁点确认后再写。

因此，在 `x = 0`、Core A 写 `1`、Core B 写 `2` 的例子中，如果 A 赢得仲裁，B 不能把自己本地基于 `0` 的副本当作另一个已提交的最新版本继续发布。B 的 shared 副本会被失效，或者 B 的写请求会等待、重试、排队，直到它自己获得该 cache line 的 writable ownership。若 B 随后获得 ownership 并执行普通 store，coherence order 可以表现为：

```text
A: x = 1
B: x = 2
```

这时最终值是 `2`。这不是硬件 rollback，而是 B 的 store 被排在 A 的 store 之后。

普通的 read-then-write update 不能自动获得 atomic RMW 语义。例如：

```c
tmp = x;
x = tmp + 2;
```

如果 Core B 先读到 `0`，Core A 随后写入 `1`，B 再写入 `2`，硬件通常不会自动把 B 的计算重做成基于 `1` 的结果。这是 lost update 问题，需要锁、atomic read-modify-write，或 CAS loop 解决。

Atomic RMW 的语义更强。`atomic compare_exchange` 如果期望旧值是 `0`，那么 A 成功把 `0` 改成 `1` 后，B 的 `0 -> 2` CAS 不能也成功；B 会看到当前值已经不是 `0`，CAS 失败，是否重试由软件决定。`atomic exchange` 不要求旧值仍然是 `0`，所以可以在 A 之后成功写入 `2`。`atomic fetch_add` 或 `atomic inc` 则必须以不可分割的 read-modify-write 方式执行，不能拆成一个普通 load 加一个普通 store，让其它 core 的成功写入插入到读和写之间。

可以把 atomic RMW 近似理解为：

```text
obtain exclusive ownership or reservation
read current value under that ownership/reservation
compute new value
write new value
complete one indivisible RMW operation
```

具体实现可能是 cache-line ownership 加 RMW 序列化、LL/SC reservation、locked instruction、AMO，或在特殊情况下退化到更重的 bus lock。这里的关键不是普通软件锁，而是硬件保证同一地址上的另一个成功写入不能插入这个 RMW 的 read 和 write 之间。

在 x86 上，许多 atomic load/store 的代码生成也体现了 coherence 与 ordering 的分工。对硬件支持大小和对齐的 coherent memory，普通 aligned `mov` load/store 已经通过 cache coherence 获得 per-location atomicity 和可见性基础。因此 `atomic.load` 通常可以编译成普通 `mov`，`memory_order_relaxed` 或 `memory_order_release` 的 `atomic.store` 通常也可以编译成普通 `mov`。

但是 C++ 默认的 `atomic.store` 是 `memory_order_seq_cst`。在 x86 上，seq_cst store 常见实现是带内存操作数的 `xchg`，或普通 `mov` 加 `mfence`。这主要是为了满足 sequential consistency 的 ordering 要求，尤其是提供 StoreLoad 屏障，防止后续 load 在该 store 对其它 core 全局可见之前被观察为先发生。`xchg` 不是因为普通 aligned store 在 coherent cache 下不原子，而是因为它隐含 locked 语义并可充当强屏障。

最后，cache coherence 本身主要是 per-location 或 per-cache-line 的保证。它保证同一个位置的多个缓存副本不会永久分裂成多个互相冲突的最新版本，并为同一位置的写提供所有 core 都能遵守的顺序。它不单独保证不同 cache line 之间的可见顺序。例如一个 core 写 `data = 42` 再写 `flag = 1`，另一个 core 看到 `flag = 1` 时是否一定看到 `data = 42`，取决于 memory ordering 规则、barrier、锁、release/acquire 或 ISA 的一致性模型，而不是 cache coherence 单独完成。

## Evidence

- This page is a provisional synthesis from the cache coherence discussion on 2026-05-13. No dedicated raw architecture source has been ingested yet.
- [[wiki/concepts/cache-coherence]] defines coherence as the per-location or cache-line foundation for shared cached memory, while separating it from cross-location memory ordering.
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]] motivates why coherent ordinary cacheable memory is preferable to relying only on compiler-recognized concurrent variables and special broadcast instructions.

## Follow-Ups

1. Ingest architecture-specific source notes for x86 memory ordering and locked instruction semantics.
2. Add a concrete comparison of x86 `seq_cst store` implementations such as `xchg` versus `mov` plus `mfence`.
3. Add a source-backed note distinguishing MESI/MOESI states from language-level atomic ordering.

## Related Pages

- [[wiki/concepts/cache-coherence]]
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]]
- [[wiki/index]]
