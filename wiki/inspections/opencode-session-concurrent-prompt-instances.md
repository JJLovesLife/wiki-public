---
type: inspection
title: "opencode session prompts are only serialized within one instance"
repo: opencode
repo_commit: 1afa9e32c9ebde43fc94782c883b422a3628daff
inspected_on: 2026-05-31
scope_paths:
  - packages/opencode/src/session/run-state.ts
  - packages/opencode/src/effect/runner.ts
  - packages/opencode/src/session/status.ts
  - packages/opencode/src/session/prompt.ts
  - packages/opencode/src/session/session.ts
  - packages/core/src/session/sql.ts
  - packages/core/src/session/projector.ts
---

## Question

多个 opencode instance 或进程同时对同一个 session 执行新的 prompt 时，会不会有 session lock 防止并发？如果没有，会发生什么？

## Answer

OpenCode 对同一个 session 的 prompt 执行有进程内同步，但没有看到跨进程、进程级或 OS 文件锁级别的 session lock。

在单个 opencode instance 内，`SessionRunState` 为每个 `sessionID` 维护一个内存 `Runner`。普通 prompt 进入 `SessionPrompt.loop()` 后会调用 `state.ensureRunning(sessionID, ...)`。如果同一个 session 已经在跑，`Runner.ensureRunning()` 不会启动第二个 run，而是等待已有 run 的 `Deferred` 完成。`Runner` 的状态保存在进程内 `SynchronizedRef` 中，状态机包括 `Idle`、`Running`、`Shell`、`ShellThenRun`。这使同一个 instance 内的普通 prompt run loop 被串行化或复用。

这个同步边界不跨进程。`SessionRunState` 和 `SessionStatus` 都基于 `InstanceState` 内存状态；`SessionStatus` 还会发布 busy/idle 事件，但它本身不是共享锁，也不写入持久化 lock row。如果两个独立 opencode instance 同时指向同一个 DB 和同一个 session，它们各自会有自己的 `SessionRunState` map，因此都会认为本进程内没有正在运行的 runner，并可能同时启动各自的 LLM run loop。

实际结果通常不是数据库物理损坏，而是 session 业务语义竞态：两个 prompt 都可能先写入 user message；两个 run loop 都会从 DB 读取 compacted message stream，选择各自看到的 latest user/assistant 状态，然后分别生成 assistant message、tool parts、patch parts 或 shell/tool side effects。SQLite/Drizzle 的单条写入、message/part 主键和 projector upsert 能降低存储层冲突，但不能保证“同一个 session 同一时间只有一个 agent 推进对话”。因此可能出现重复 assistant 回复、交错 tool call、上下文选择非预期、文件编辑互相覆盖或 patch/revert 历史混乱。

## Trace

1. HTTP prompt 入口最终调用 `SessionPrompt.prompt(...)`，该函数先读取 session、清理 pending revert，然后调用 `createUserMessage(input)` 创建 user message，并 `sessions.touch(input.sessionID)` 更新时间。
2. `createUserMessage()` 构造 `SessionLegacy.User`，再调用 `sessions.updateMessage(info)` 和 `sessions.updatePart(part)` 发布 message/part update 事件；这些事件由 projector 写入 DB。
3. 如果 `input.noReply` 不是 true，`SessionPrompt.prompt()` 进入 `loop({ sessionID })`。
4. `loop()` 调用 `state.ensureRunning(input.sessionID, lastAssistant(input.sessionID), runLoop(input.sessionID))`。这是单 instance 内普通 prompt 的同步点。
5. `SessionRunState` 的 `state` 是 `InstanceState.make(...)` 创建的内存对象，包含 `new Map<SessionID, Runner<...>>()` 和当前 scope；`runner(sessionID, ...)` 从这个 map 取现有 runner 或创建新 runner。
6. `Runner.ensureRunning()` 在 `Running` 或 `ShellThenRun` 时等待已有 `run.done`；在 `Shell` 时记录一个 pending run；只有 `Idle` 时才 fork 新 work。这防止单 instance 内同一 session 的多个普通 run loop 并发执行。
7. `Runner.startShell()` 更严格：非 `Idle` 时直接失败为 `RunnerBusy`，再被 `SessionRunState.startShell()` 映射为 `Session.BusyError`。
8. `SessionStatus` 只在内存 map 里记录非 idle 状态，并通过 `EventV2Bridge` 发布 `session.status` 和 deprecated `session.idle` 事件；idle 时删除 map 项。
9. DB schema 中 `session`、`message`、`part` 表只有普通主键和索引；没有 session-level lock table、lease column 或 busy owner 字段。
10. projector 对 message/part update 使用 `insert(...).onConflictDoUpdate(...)`，说明它是事件投影式写入，不是围绕整个 prompt run 的互斥事务。
11. 因此，两个进程的同一 session 并发 prompt 会绕过彼此的 `SessionRunState`，各自写入消息并各自运行 processor/LLM/tool loop。

## Evidence

- `packages/opencode/src/session/run-state.ts:35-49`：`SessionRunState` 的 state 由 `InstanceState.make(...)` 创建，内部是进程内 `Map<SessionID, Runner<...>>()`。
- `packages/opencode/src/session/run-state.ts:52-69`：`runner(sessionID, ...)` 只在当前 state map 中复用或创建 runner。
- `packages/opencode/src/session/run-state.ts:71-75`：`assertNotBusy()` 只检查当前进程 state map 中的 runner busy 状态。
- `packages/opencode/src/session/run-state.ts:88-105`：`ensureRunning()` 和 `startShell()` 委托给当前进程中的 runner；shell busy 被转换成 `Session.BusyError`。
- `packages/opencode/src/effect/runner.ts:33-38`：`Runner` 状态机只有内存状态 `Idle`、`Running`、`Shell`、`ShellThenRun`。
- `packages/opencode/src/effect/runner.ts:115-138`：`ensureRunning()` 在已有 run 时等待 `st.run.done`，只有 idle 时启动新 run。
- `packages/opencode/src/effect/runner.ts:140-169`：`startShell()` 非 idle 时返回 `RunnerBusy`。
- `packages/opencode/src/session/status.ts:64-86`：`SessionStatus` 也是 `InstanceState` 内存 map，负责 publish status events，但不是持久化锁。
- `packages/opencode/src/session/prompt.ts:697-724`：`createUserMessage()` 为 prompt 创建新的 `SessionLegacy.User` message。
- `packages/opencode/src/session/prompt.ts:1123-1124`：user message 和 parts 通过 `sessions.updateMessage()` / `sessions.updatePart()` 写入事件流。
- `packages/opencode/src/session/prompt.ts:1218-1237`：`SessionPrompt.prompt()` 先创建 user message，再在需要回复时进入 `loop()`。
- `packages/opencode/src/session/prompt.ts:1505-1508`：普通 prompt loop 的同步点是 `state.ensureRunning(...)`。
- `packages/opencode/src/session/prompt.ts:1255-1264`：run loop 每轮设置 busy，然后从 DB 读取 compacted message stream 并计算 latest user/assistant/tasks。
- `packages/core/src/session/sql.ts:16-92`：`session`、`message`、`part` 表定义没有跨进程 session lock/lease 字段；message 和 part 使用各自 id 作为主键。
- `packages/core/src/session/projector.ts:297-309`：message update projector 对 `MessageTable.id` 做 insert/upsert。
- `packages/core/src/session/projector.ts:347-364`：part update projector 对 `PartTable.id` 做 insert/upsert，并增减 usage。

## Uncertainty

The inspection did not reproduce two live opencode server processes against one DB. The conclusion is based on code structure in the inspected snapshot: the visible session busy/run state is process-local, while persistence paths do not expose a durable session lock. SQLite may still serialize individual writes or return transient database-busy errors depending on connection settings and timing, but that would be storage-level contention rather than intended session-level prompt serialization.

## Related Pages

- [[wiki/inspections/opencode-session-revert-two-layer-semantics]]
- [[wiki/syntheses/opencode-workspace-syncevent-sync]]
- [[wiki/index]]
