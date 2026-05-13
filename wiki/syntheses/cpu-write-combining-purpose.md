# CPU Write Combining Purpose

## Question

什么是 CPU write combining？它的目的是什么？为什么要发明这个？

## Answer

CPU write combining 是一种把多个相邻或同一 cache-line 范围内的小 store 先暂存在 write-combining buffer 中，再合并成更大写事务一次性发出的机制。它最常见于 write-combining memory type、uncacheable-like device aperture、framebuffer、PCIe BAR、GPU/显示设备映射内存、以及一些 non-temporal streaming store 路径。

它要解决的问题是：CPU 的普通 store 通常很小，例如 1、4、8、16、32 bytes，但外部内存总线、PCIe、显存 aperture 或 device interconnect 更喜欢 cache-line 大小或 burst 形式的连续写。如果每个小 store 都立刻变成一次独立外部事务，带宽会很差，事务头开销很高，device side 也会看到大量细碎写入。Write combining 把这些小写入收集起来，等 buffer 满、遇到 fence、遇到冲突访问、被调度刷出，或发生其它 drain 条件时，再发出更少、更大的写事务。

它的核心目的有三个：提高顺序写带宽，减少总线或互连事务数量，避免污染普通 cache。比如软件往 framebuffer 顺序写像素，常常只需要把数据推给显示/GPU memory，并不希望 CPU 把这些 framebuffer line 当作普通 cacheable data 带进 L1/L2，再参与正常替换和 coherence。Write combining 允许 CPU 以接近 streaming 的方式高吞吐写出，而不是用慢速 strongly uncacheable 单次写，也不是用普通 write-back cache 去缓存一大段之后很少再读的数据。

它之所以被发明，是因为早期如果设备内存或 framebuffer 被标成 uncacheable，每个 CPU store 往往都要以很强顺序、很小粒度地真正送到外部设备，性能极差；但如果把这些区域标成普通 cacheable，又可能产生 cache pollution、错误的设备可见性语义、或不适合 MMIO/device memory 的 coherence 行为。Write combining 是两者之间的折中：对读取和细粒度同步不友好，但对单向、连续、大量写入非常高效。

它和普通 store buffer 容易混淆，但不是同一个概念。Store buffer 是普通 store pipeline 的每 core 私有队列，用来把 store 执行/退休和写入 coherent cache/memory domain 解耦；write-combining buffer 更强调把多个写入按地址合并成较大外部写事务，尤其面向 weakly ordered、non-cacheable 或 streaming-write 路径。一个具体 CPU 可以在实现上复用或相邻放置这些结构，但软件语义上要区分：store buffer 主要解释普通 cacheable store 的延迟与可见性，write combining 主要解释为什么连续写 device/framebuffer/streaming memory 可以变快但排序更弱。

Write combining 的代价是 ordering 和可见性更弱。写入可能暂存在 CPU 内部一段时间，设备或其它 agent 不一定马上看见；多个 write-combining writes 的外部到达顺序也可能只在特定边界上受保证。因此写 device register、doorbell、descriptor ring 等协议时，通常需要按照平台规则使用 fence、flush、uncached/strongly ordered access，或驱动框架提供的 barrier，确保前面的 bulk data writes 已经到达，再发出通知设备开始读取的 doorbell write。

一个直观类比是：store buffer 像收银台后面等待入账的单据队列；write combining 像快递打包站，把同一条街上的多个小包裹打成一车发出。它牺牲了“每个小包裹立刻单独送达”的可观察性，换来了更高吞吐和更低运输开销。

## Evidence

- This page is a provisional architecture synthesis from the 2026-05-13 write-combining discussion. No dedicated raw architecture source has been ingested yet.
- [[wiki/syntheses/cpu-store-buffer-l1-cache-pipeline-ooo]] distinguishes ordinary store buffers from cache/coherence state and previously listed write-combining buffers as a follow-up distinction.
- [[wiki/concepts/cache-coherence]] defines ordinary coherent cacheable memory as cache-line ownership based; write combining is important partly because device/framebuffer/streaming writes often should not behave like ordinary coherent cacheable data.
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]] explains why ordinary cacheable stores join coherent ownership and ordering rules, which contrasts with weakly ordered write-combining paths.

## Follow-Ups

1. Ingest architecture-specific sources for x86 PAT/MTRR memory types, Arm device/normal non-cacheable memory attributes, and non-temporal store write-combining behavior.
2. Add concrete examples for framebuffer writes, PCIe BAR writes, GPU ring buffers, and descriptor-doorbell ordering.
3. Distinguish write-combining buffers from dirty eviction/writeback buffers and from posted writes in PCIe.

## Related Pages

- [[wiki/syntheses/cpu-store-buffer-l1-cache-pipeline-ooo]]
- [[wiki/concepts/cache-coherence]]
- [[wiki/syntheses/cache-coherence-write-ownership-and-atomics]]
- [[wiki/index]]
