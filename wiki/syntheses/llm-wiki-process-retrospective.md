# LLM Wiki Process Retrospective

## Question

我们已经践行 LLM wiki 一段时间后，流程上有什么可以改进？尤其是 Karpathy 原来提出的方案，和这个 vault 实际使用方式之间有哪些差别值得吸收进后续流程？

## Answer

核心结论：Karpathy 的主张仍然成立，也就是把知识维护成一个会积累的 wiki，而不是每次 query 都从 raw documents 重新 RAG。但是这个 vault 的实际形态已经从“source ingest 为主”演化成了三条并行主线：source ingest、code inspection、durable discussion synthesis。这个演化是合理的，尤其适合技术研究和代码追踪，但需要把 code-as-source、证据成熟度、source debt、follow-up 回收、索引扩展策略和页面形状显式化。

当前最值得改进的是：不要把所有 durable pages 都当成同一种可信度。这个 vault 里有三类页面：有 raw source 支撑的 source-backed 页面，有 repo commit 和代码路径支撑的 inspection-backed 页面，还有从对话推理沉淀出来但暂时缺少外部 source 的 provisional synthesis。第三类很有价值，但应该被明确标记为“待补 source”或“conversation-derived”，否则随着时间推移很难区分哪些结论已经被文档或代码锚定，哪些只是当时讨论中的合理推理。

用户后续反馈进一步说明：这个 vault 的主要负载不是论文、文章或网页阅读，而是开源项目源码阅读笔记。对这类内容，`source` 更多是某个 repo 的一个 commit snapshot，加上被追踪到的文件、函数、调用链和测试路径，而不是一个可以复制进 `sources/files/` 的单一文档。因此，流程语言里应该明确区分 `document source` 和 `code source`。前者走 ingest，后者走 inspect；两者都可以作为 evidence，但保存方式不同。

另一个实际差异是讨论形态。很多有价值的沉淀来自多轮 LLM 讨论，并不是一开始就有一个清晰问题，也不一定能自然压缩成单个 Q&A。现有 synthesis page 的 `## Question` / `## Answer` 形状适合明确问题，但不完全适合 exploratory discussion。后续可以允许 synthesis 的 `Question` 扩展为“讨论入口”或“主题上下文”，并在 `Answer` 里保留更像 `Context -> Claims -> Takeaways -> Remaining Doubts` 的结构，而不是强行伪装成一个单问单答。

Karpathy 原方案和实际使用的主要差异如下：

| Karpathy 原方案 | 这个 vault 的实际做法 | 建议 |
|---|---|---|
| 以 immutable raw sources + wiki + schema 为三层架构 | 基本保留三层架构，并新增 `wiki/inspections/` 作为代码调查层 | 保留 `Inspect` 作为一等 workflow，不要把代码调查伪装成 source note |
| 主要操作是 ingest、query、lint | 实际多了 inspect，并且 inspect 页面数量已经超过 source note | 让 inspection provenance 更严格：commit、scope_paths、关键路径、uncertainty 都必须持续维护 |
| Ingest 一个 source 可能更新 10-15 个页面 | 实际更偏最小更新，只在概念明显稳定时创建 concept page | 继续避免 page explosion，但当同一主题出现 3 个以上 synthesis/inspection 时，优先创建或更新 concept hub |
| `log.md` 作为 chronological history | 这个 vault 用 Git history 替代 `log.md` | 保持 Git 为 canonical history，但在 recency-sensitive query 中明确读取 `git log` |
| `index.md` 是中等规模下的主导航 | 当前 flat index 仍可用，但 inspections 和 syntheses 已经开始变长 | 当某一 section 超过约 12-15 页时，按主题分组或增加 hub page |
| Wiki 以 document sources 为自然入口 | 实际常以 repo、driver、subsystem、相关项目组为入口 | 增加 repo/project hub，把同一 repo 或相关 repos 的 inspections 聚合起来 |
| Query 常能表达成一个明确问题 | 实际讨论经常是多轮探索，结论不是单个 Q&A | 允许 discussion synthesis 使用更灵活的上下文、结论和不确定性结构 |
| Lint 关注 contradictions、orphans、stale claims、missing cross-references、concept gaps | 现在已有结构和链接健康脚本，但 semantic lint 还不够制度化 | 增加周期性 semantic lint：专门回收 Follow-Ups、Open Questions、provisional claims 和 source debt |
| 人在 ingest 中读 summary、检查 emphasis、指导 LLM | 实际上很多页面由对话直接沉淀，人工 review checkpoint 不总是显式 | 对 broad source、schema change、长期 synthesis 加一个短 review checkpoint |

具体流程改进建议：

1. 增加“证据成熟度”分类。给 synthesis 或 answer 至少在正文中标明它是 `source-backed`、`inspection-backed`、`conversation-derived`、还是 `needs-source`。如果以后愿意改 schema，可以把它做成 frontmatter 字段。
2. 把 source debt 当成一等维护对象。凡是 Evidence 里写着“no dedicated raw source has been ingested yet”的页面，都应该在 lint 或 retrospective 中被收集，形成后续 ingest 队列。
3. Query 保存为 synthesis 前，先判断保存理由。值得保存的条件可以是：问题会复现、连接了多个页面、纠正了误解、形成了可复用模型，或者引出了明确 follow-up。
4. Inspect 继续独立于 Ingest。代码调查的 raw truth 是 repo snapshot，而不是 `sources/files/`。因此 inspection page 应该优先保证 repo commit、scope_paths、line evidence、uncertainty 和 related inspections，而不是强行创建 raw source 文件。
5. 对代码 inspection 增加 freshness 习惯。如果用户后来问同一 repo 的同一主题，应先检查已有 inspection 的 `repo_commit` 是否仍是目标版本；如果不是，要么更新原页，要么新建带新 commit 的 inspection。
6. 给 repo 级知识增加 hub。与其让 `index.md` 只按 page type 列表增长，不如在 Linux DRM/amdgpu、Mesa RADV、libdrm、OpenCode、agent architecture 等自然主题下建立 hub page 或 index 分组。
7. 为 discussion synthesis 放宽 Q&A 模型。保留 `## Question` 作为兼容入口，但允许它写成“讨论从哪里开始”；在 `## Answer` 中使用 context、claims、model、tradeoffs、open doubts 等更适合多轮讨论的结构。
8. 定期做 follow-up lint。结构性 health check 负责 broken links 和 page shape；semantic lint 应负责检查 Follow-Ups、Open Questions、provisional synthesis、孤立概念和 stale inspection。
9. 让 index 从 catalog 慢慢变成 map。当前 `wiki/index.md` 是完整目录，这很好；下一阶段应该在 CPU/cache、GPU/DRM、agent architecture、wiki operations 等主题聚集处增加 hub 或分组，避免只有长列表。
10. 保持最小页面策略。不是每个名词都需要 entity/concept page。这个 vault 目前没有 entity page 是合理的，因为主要内容是技术机制而不是人物、组织或地点。
11. 将 Git history 纳入 query workflow。Karpathy 的 `log.md` 可直接被 LLM 读；Git history 需要主动读取。涉及“最近做过什么”、“这个结论何时形成”、“有没有后续修正”的问题，应默认读最近 commits。
12. 把流程复盘本身周期化。每积累一批 source、inspection 或 synthesis 后，做一次小型 retrospective，比等到 schema 已经不适合时再大改更安全。

可以考虑提升进 `AGENTS.md` 的硬规则：

1. Query workflow 增加一步：保存 synthesis 时标明 evidence maturity，并在缺少 raw source 时留下 source debt。
2. Lint workflow 增加一步：扫描 Follow-Ups、Open Questions、provisional synthesis 和 stale inspection commits。
3. Inspect workflow 增加一步：如果已有同主题 inspection，先比较 repo 和 commit，再决定 update 还是新建。
4. Index workflow 增加一步：当 section 过长时，优先按主题创建 hub 或局部分组，而不是无限增长 flat list。
5. Page shape 增加弹性：synthesis 不必总是假装成单一 Q&A，允许保存多轮讨论的 context、claims、takeaways 和 remaining doubts。

## Evidence

- [[wiki/sources/karpathy-llm-wiki]] 总结了 Karpathy 的核心模式：immutable raw sources、LLM-owned wiki、schema，以及 ingest、query、lint 三类操作。
- [[AGENTS]] 已经把这个 vault 的实际结构扩展为 `wiki/sources/`、`wiki/inspections/`、`wiki/concepts/`、`wiki/entities/`、`wiki/syntheses/`，并明确 Git history 替代 `log.md`。
- [[wiki/index]] 目前列出 5 个 source notes、11 个 inspections、6 个 concepts、0 个 entities、8 个 syntheses，说明实际增长重心已经明显偏向 code inspection 和 query synthesis。
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]]、[[wiki/syntheses/cache-coherence-write-ownership-and-atomics]]、[[wiki/syntheses/cache-coherence-broadcast-scope]] 都明确保留了“no dedicated raw source has been ingested yet”的证据缺口，是 source debt 的具体例子。
- [[wiki/inspections/linux-amdgpu-vm-pte-update-synchronization]] 和 [[wiki/inspections/opencode-session-revert-two-layer-semantics]] 展示了 inspection workflow 的价值：它们把跨文件代码追踪、repo commit、scope_paths、line evidence 和 uncertainty 保存成 durable pages。
- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]] 和 `scripts/obsidian-wiki-health.sh` 已经提供结构性 health check，但它们主要覆盖 links、orphans、dead ends、frontmatter 和 required headings，不会自动解决 semantic source debt 或 stale claims。
- Recent Git history shows repeated `inspect:`, `synthesize:`, `concept:`, `ingest:`, and `schema:` commits, which supports treating Git as the chronological operational layer rather than maintaining a separate `log.md`.
- User feedback on 2026-05-30 clarified that the dominant use case is preserving open-source code-reading notes, where the effective source is often a repo snapshot rather than a standalone raw document. The same feedback also noted that many valuable LLM discussion outputs are multi-turn exploratory structures rather than clean single-question answers.

## Follow-Ups

1. Revisit the new [[AGENTS]] evidence-maturity and discussion-synthesis rules after a few more pages are created under the adjusted workflow.
2. Create a lightweight source-debt ledger or further automate source-debt harvesting in the lint workflow.
3. Revisit the cache-coherence syntheses after ingesting architecture-specific memory-model sources.
4. Consider grouping `wiki/index.md` by topic once any section becomes difficult to scan.
5. Run a semantic lint pass focused on Follow-Ups and Open Questions, not just link health.
6. Add the first repo/project hub pages when the next code-reading pass touches Linux DRM/amdgpu, Mesa RADV, libdrm, or OpenCode.
7. Convert or annotate older synthesis pages only when they are next materially edited; do not bulk-migrate just for shape consistency.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/karpathy-llm-wiki]]
- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]]
- [[wiki/syntheses/cpu-cache-coherence-vs-special-concurrent-instructions]]
- [[wiki/inspections/linux-amdgpu-vm-pte-update-synchronization]]
- [[AGENTS]]
