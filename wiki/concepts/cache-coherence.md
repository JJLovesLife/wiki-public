# Cache Coherence

## Definition

Cache coherence 是 CPU 在硬件层维护同一份内存位置的多个 cache 副本一致性的规则集合。实际协议通常以 cache line 为粒度工作；在 ISA、语言模型或并发语义里，则常把这个保证描述为 per-location coherence。

对一个 coherent memory location 来说，coherence 提供的是同一位置写入的共同排序点：两个 core 不能长期各自拥有互相冲突的“最新版本”。一个 core 想写入相关 cache line 前，通常必须先获得 writable ownership，例如 MESI-like protocol 里的 exclusive 或 modified 状态。

## Why It Matters

Coherence 是 ordinary shared memory 能用普通 cacheable load/store 工作的基础。它让 lock 可以保护普通 non-atomic field，让 atomic 可以在普通 cacheable memory 上建立 synchronization，也让 OS 可以迁移 thread，而不要求 compiler 预先知道所有 runtime sharing 关系。

Coherence 不等于完整的 memory consistency model。Coherence 主要约束同一个 location 或 cache line 的访问顺序；不同 location 之间，尤其是不同 cache line 之间的可见顺序，属于 memory ordering 的范围，需要由 barrier、acquire/release operation、sequential consistency，或者具体 ISA 的 ordering guarantee 来定义。

## Supporting Evidence

- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]] 说明 special concurrent-variable instruction 仍然需要 invalidation、update 或 central serialization 规则；这些规则本质上已经是在显式实现 coherence mechanism。
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]] 说明 writable cache-line ownership、ordinary store、atomic read-modify-write operation，以及 x86 atomic store code generation 如何和 coherence 分工。
- [[wiki/syntheses/cache-coherence-broadcast-scope]] 说明 coherence 不要求每次普通写入都广播给所有核心；通信通常发生在 ownership 转移、invalidation、dirty line request 或 writeback 等边界上。
- [[wiki/syntheses/cpu-store-buffer-l1-cache-pipeline-ooo]] 说明 store buffer 如何在 store 获得 writable ownership 并 drain 到 coherent L1 状态之前，暂存本 core 的 pending stores。

## Related Pages

- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]]
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]]
- [[wiki/syntheses/cache-coherence-broadcast-scope]]
- [[wiki/syntheses/cpu-store-buffer-l1-cache-pipeline-ooo]]
- [[wiki/index]]

## Open Questions

- 为 x86、Arm 或 RISC-V 的 cache coherence 和 memory ordering terminology 补充 architecture-specific source note。
- 用具体例子比较 invalidate-based、update-based、snooping 和 directory-based coherence protocol。
