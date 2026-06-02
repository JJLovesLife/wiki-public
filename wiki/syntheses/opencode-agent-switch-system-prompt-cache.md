---
type: synthesis
title: OpenCode Agent Switch System Prompt Cache
created_on: 2026-06-02
evidence_maturity: inspection-backed, conversation-derived
repo: opencode
repo_commit: 1afa9e32c9ebde43fc94782c883b422a3628daff
---

# OpenCode Agent Switch System Prompt Cache

## Question

OpenCode 在 session 中间发生 `agent switch` 时，尤其是 `plan_exit` 从 `plan` 切到 `build`，会怎样处理前面的 messages、`system prompt`、`prompt cache` 和 LLM context coherence？如果是训练一个新的 model + 专门的 harness，timeline-style multiple `system` messages 是否会是更好的 protocol？

## Answer

### 当前 OpenCode 行为

OpenCode 不是把第一条 `system prompt` 持久化后再修改。`system prompt` 是 per request assembled：每次 LLM request 都根据当前 `agent`、model、environment、instructions、skills、user system 等重新拼出来。

每条 user message 会记录当时的 `agent`。Assistant loop 后续选择哪个 agent，关键看 last user message 的 `agent` field。也就是说，ordinary `agent switch` 本质上是 append 一条带新 `agent` 的 user message，而不是 rewrite old messages。

`plan_exit` 也是这个模式。`plan` agent 调用 `plan_exit` tool 后，OpenCode 会问用户是否 switch to `build`。用户选择 Yes 后，OpenCode 在同一个 session 里 append 一条 synthetic user message：

```text
agent: "build"
text: "The plan at ... has been approved, you can now edit files. Execute the plan"
```

前面的 plan-mode user/assistant/tool messages 仍然保留在 session history 中。除非后续触发正常的 truncation、compaction 或 overflow handling，否则 build 轮 LLM request 仍会看到这些 prior messages。

OpenCode 还会在一些 plan-to-build transition 中注入 `BUILD_SWITCH` reminder，大意是 operational mode 已经从 plan 变成 build，read-only mode 不再适用，允许 edit files、run shell commands 和使用 tools。

### Prompt Cache 影响

由于 OpenCode 会用新的 `agent` 重新 assemble 当前 request 的 leading `system prompt`，`plan -> build` 通常会改变 request prefix。对于依赖 prefix identity 的 provider prompt cache，这会导致旧的 plan-mode cache entry 不能命中新的 build request。

这不是 provider cache 被 global cleared，而是新的 request prefix 和旧的 prefix 不一样，所以旧 cache entry 对这次 request 没用。如果之后切回同一个 agent，并且 ephemeral cache 还没过期、prefix 又足够一致，才可能重新命中。

在 inspected code 里，OpenCode 的 provider transform 对 Claude/Anthropic-like paths 和部分 compatible providers 会显式加 cache hints。策略大致是给 first two system messages 和 last two non-system messages 加 provider cache metadata。因此 `system prompt` stability 对 cache hit rate 很重要。

### Context Coherence 影响

当前方案很 pragmatic，但对 LLM 来说不是最干净的 context design。`plan_exit` 后，build 轮可能呈现成：

```text
system: build mode, you can edit
history assistant: I am in plan/read-only mode and cannot edit files
synthetic user: plan approved, execute the plan
assistant: ...
```

模型通常能靠 latest `system prompt` 和 synthetic transition message 理解现在处于 build mode，但旧 transcript 里仍然有 plan-mode 下合理、build-mode 下过时的 behavior。这会带来 low-grade context noise：

1. Input tokens 会花在 obsolete operational constraints 上。
2. Model 需要推断 earlier assistant behavior 是 historical context，而不是 current instruction。
3. Leading `system prompt` 变化会降低 prompt cache locality。

当前设计的好处是简单、UI/session continuity 好，并且不会丢失 planning conversation 的细节。代价是 cache locality 和 instruction timeline cleanliness 都不是最优。

### 更干净的 Agent Switch 设计

最 general 的 clean design 是在 `agent switch boundary` 做 handoff compaction。`plan -> build` 时，runtime 只把 approved plan artifact、关键 constraints、user approval 和必要 context 传给 build，而不是把完整 plan-mode transcript 原样塞给 build agent。

可以有几种形态：

1. New linked build session：用 final plan + approval seed 一个新的 build session。
2. Same-session compaction：保留 UI storage 的完整历史，但 LLM context 里用 synthetic summary 代替前面 plan details。
3. Hybrid handoff：full history 仍可查，但 build request 从 compacted handoff summary 开始。

另一个方案是 timeline-style transcript，在 mode switch 的位置插入新的 `system` control frame：

```text
system: plan mode; do not edit
user: make a plan
assistant: planning response
system: switch to build mode; previous plan-mode constraints no longer apply
assistant: implementation response
```

这个方案比“把 build system 放到最前面，然后后面跟 plan-mode history”更符合时间线，也更 prompt-cache-friendly。因为 plan-mode prefix 可以保持 byte-identical，build transition 只是 append 到后面。

但是对 today’s multi-provider OpenCode 来说，它有 portability risk：OpenAI-style APIs 可能接受 middle `system`/`developer` messages，但 Anthropic-like APIs 通常更接近 top-level system，Gemini/Bedrock/AI SDK/native adapters 也可能 merge、hoist、drop 或 reinterpret system messages。即使 provider 接受 middle `system`，model 也未必稳定地把它理解成 scoped control frame，而可能把所有 system-level text 当作仍然 active 的 high-priority instruction。

所以在今天的 provider landscape 下，boundary summary / compaction 比依赖 middle-system semantics 更 robust。

### 如果训练 New Model + Harness

如果 model 和 harness 是一起为 agent runtime 训练的，timeline-style multiple `system` messages 会变得很有吸引力，甚至可能是更 native 的 protocol。关键是 harness 明确定义：`system` message 是 scoped control frame，而不是 timeless global instruction。

理想 transcript 可以长这样：

```text
policy: immutable safety/platform rules
system: plan mode applies from here
user/assistant/tool history
system: build mode applies from here; previous plan-mode constraints expire
assistant/tool history
```

这种 protocol 的优势：

1. `agent mode`、tool availability、permission state、sandbox/environment changes 都能成为 auditable transcript events。
2. `prompt cache` 更友好，因为 mode transition 是 append control frame，不是 rewrite first system prompt。
3. Model 可以学会 old agent constraints explain old behavior，但不一定 govern current step。
4. Harness 可以训练 explicit override rules：newer mutable mode frames supersede older mutable mode frames；immutable policy frames 仍然优先级更高，不能被 later agent/system frames 覆盖。

关键设计点是区分 immutable policy 和 mutable runtime state。不能训练成“后面的 system 永远覆盖前面的所有 instruction”，否则会引入 safety risk。更安全的 hierarchy 是：

```text
policy/developer: immutable or high-priority constraints
system/runtime: mutable agent mode, tool set, sandbox state, permission grants
user: task intent
assistant/tool: ordinary history and effects
```

在这种 trained protocol 里，middle-of-transcript control frames 不只是 workaround，而可能是 multi-agent session 的更好 representation：它保留 cache-friendly prefix，又让 mode switch 在 transcript 中可审计、可解释、可训练。

## Evidence

Evidence maturity：OpenCode 当前行为是 inspection-backed，基于 `opencode` commit `1afa9e32c9ebde43fc94782c883b422a3628daff`；设计判断和 future harness 部分是 conversation-derived。

- `packages/opencode/src/session/llm/request.ts`：每次 request 从 `input.agent.prompt` 或 provider default prompt 开始 assemble system text，然后拼接 dynamic system fragments 和 user system text，再放进发给 model 的 messages。
- `packages/opencode/src/session/prompt.ts`：创建 user message 时写入 `agent` field；当 current session agent 不同时发布 `AgentSwitched`；assistant loop 后续根据 last user message 的 agent 获取 agent info 并创建 assistant message。
- `packages/opencode/src/tool/plan.ts`：`plan_exit` ask user 是否 switch to build；Yes 后 append synthetic user message，`agent: "build"`，仍在 same session。
- `packages/opencode/src/session/reminders.ts`：处理 plan/build reminders，包括 plan-to-build transition 中的 build-switch reminder。
- `packages/opencode/src/session/prompt/build-switch.txt`：明确说 operational mode changed from plan to build，read-only mode no longer applies。
- `packages/opencode/src/provider/transform.ts`：对 Anthropic/Claude-like provider path 应用 cache hints，涉及 early system messages 和 recent non-system messages。

相关 wiki evidence：

- [[wiki/projects/opencode]] 是 OpenCode project hub。
- [[wiki/inspections/opencode-session-concurrent-prompt-instances]] 提供 session prompt loop 和并发边界的背景。

本页没有 ingest provider official docs。关于 middle `system` messages 的 provider-specific support 仍需要 source-backed follow-up。

## Follow-Ups

1. Inspect OpenCode 的 AI SDK transform 和 native LLM adapter，确认不同 providers 对 middle `system` messages 是 preserve、merge、hoist、drop 还是 reject。
2. Measure `plan -> build` transition 的 `cache_read` / `cache_write`，覆盖 Anthropic、OpenAI-compatible、gateway 等 provider path。
3. Prototype plan-to-build compaction handoff，对比 current full-history approach 的 build quality、token usage 和 prompt-cache hit rate。
4. Ingest provider docs，整理 system/developer message ordering semantics 和 prompt cache prefix requirements。

## Related Pages

- [[wiki/index]]
- [[wiki/projects/opencode]]
- [[wiki/inspections/opencode-session-concurrent-prompt-instances]]
- [[wiki/syntheses/managed-agents-harness-sandbox-separation]]
