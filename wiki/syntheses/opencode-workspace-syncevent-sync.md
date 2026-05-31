# OpenCode Workspace SyncEvent Synchronization

## Question

OpenCode 的 workspace、远端会话和 `SyncEvent` 是什么关系？同一个项目的多个 git workspace 如果共享同一个本地 DB，是否还需要真正意义上的同步？`SyncEvent` 到底同步的是 DB 还是别的东西？

## Answer

最准确的心智模型是：OpenCode 的 workspace 是一个执行环境抽象，`SyncEvent` 是跨不共享 DB 的 OpenCode 实例复制会话状态的事件日志协议。

本地多个 git worktree workspace 如果由同一个 OpenCode 安装或进程族管理，并且使用同一个 SQLite DB，它们不需要通过网络 `SyncEvent` 做状态同步。它们直接读写同一份 `session`、`message`、`part`、`event`、`event_sequence` 等表。SQLite WAL 和 busy timeout 处理的是本地 DB 并发访问，不是 OpenCode 的业务同步协议。

不过，即使没有发生跨实例同步，本地发布可同步事件时仍会写 `event` 和 `event_sequence`。这两张表是可重放事件日志和 per-session sequence fence：它们保存以后 replay、warp 或远端同步所需的历史，而不是说明当前一定正在和另一个 workspace 同步。

真正需要 `SyncEvent` 的场景是 remote workspace，或者任何不共享同一个 DB 的另一个 OpenCode 实例。remote workspace 通过 adapter 暴露 HTTP target，本地不能直接访问它的 SQLite DB，所以只能交换事件：远端把 `session.updated.1`、`message.updated.1`、`message.part.updated.1` 等同步事件通过 SSE 或 `/sync/history` 发回本地；本地 `replay` 后运行 projector，把自己的 DB 更新为同样的 session 当前状态。

因此同步的不是整个 DB，也不是表级复制：

```text
不是: DB A -> copy tables -> DB B
而是: event log entry -> HTTP/SSE -> replay -> projector updates local DB
```

`event` / `event_sequence` 是同步源日志；`session` / `message` / `part` 是从这些事件投影出来、供查询和 UI 使用的当前状态。对共享同一 DB 的本地 workspace，这些投影已经在同一 DB 内可见，不需要 remote sync。对不共享 DB 的 remote workspace，`SyncEvent` 是让另一边重建这些投影的载体。

需要额外区分的是，多个本地进程共享 DB 不等于共享内存事件流。一个进程内的 subscribers、SSE clients、`GlobalBus` listeners 不会天然收到另一个进程内存里刚 publish 的 event；但 DB 状态是共享的。`SyncEvent` 解决的是不同 DB 之间的会话状态复制，而不是本地多进程 pubsub。

OpenCode 的 workspace 目前可以是本地或远端 target：

```ts
type Target =
  | { type: "local"; directory: string }
  | { type: "remote"; url: string | URL; headers?: HeadersInit }
```

内置 `worktree` adapter 创建的是 local target：一个 git worktree 目录。这个目录的文件、shell cwd、未提交改动和运行进程是 workspace-local 的；它们不是通过 `SyncEvent` 同步的。`SyncEvent` 关注的是 session 事件：session 元数据、message、part、删除、部分 v2 session events 等。

`sessionWarp` 是这个机制的一个典型使用点。把 session 迁移到 remote workspace 时，本地会查询该 `sessionID` 的 `event` 历史，分批 POST 到目标 `/sync/replay`，让远端 replay 出同样的 session 状态；随后 `/sync/steal` 把 session 标记为属于目标 workspace。之后目标 workspace 继续产生的新 session events 再通过 SSE/history 回流。

## Evidence

- Evidence maturity: inspection-backed synthesis from `opencode` repository snapshot `1afa9e32c9ebde43fc94782c883b422a3628daff`, plus the 2026-05-31 discussion that motivated this page.
- `packages/core/src/database/database.ts:42-59` shows `Database.defaultLayer` uses the global OpenCode data path, normally `Global.Path.data/opencode.db`, unless `OPENCODE_DB` or channel-specific behavior overrides it.
- `packages/core/src/event/sql.ts:4-18` defines `event_sequence` and `event`, where each sync aggregate stores a latest `seq` and every event row stores `id`, `aggregate_id`, `seq`, `type`, and JSON `data`.
- `packages/core/src/event.ts:163-243` commits sync events: it checks the version, extracts the configured aggregate field, enforces sequence ordering, runs projectors, updates `event_sequence`, and inserts into `event`.
- `packages/core/src/event.ts:280-335` replays serialized sync events by mapping versioned wire types such as `session.updated.1` back to local definitions, then committing them with the provided `seq` and aggregate ID.
- `packages/core/src/session/legacy.ts:497-625` marks legacy session, message, and part events as sync events with `aggregate: "sessionID"` and `version: 1`.
- `packages/core/src/session/projector.ts:269-365` registers projectors that turn session/message/part events into `SessionTable`, `MessageTable`, and `PartTable` updates.
- `packages/opencode/src/control-plane/types.ts:30-39` defines workspace target shape as either local directory or remote URL/headers.
- `packages/opencode/src/control-plane/adapters/worktree.ts:89-95` makes the built-in worktree adapter return a local target directory, confirming local git workspace execution is directory based rather than remote sync based.
- `packages/opencode/src/control-plane/workspace.ts:329-397` implements `/sync/history` consumption for remote workspaces: it sends local aggregate sequence state, receives missing history rows, and replays them with `publish: true`.
- `packages/opencode/src/control-plane/workspace.ts:399-478` connects to remote `/global/event` over SSE and replays payloads whose type is `sync` and contain a serialized `syncEvent`.
- `packages/opencode/src/control-plane/workspace.ts:701-800` shows `sessionWarp` reading a session's local `event` history, POSTing batches to remote `/sync/replay`, then calling `/sync/steal` and updating the session workspace.
- `packages/opencode/src/server/routes/instance/httpapi/handlers/sync.ts:37-90` exposes replay and history endpoints that translate HTTP payloads into `EventV2.SerializedEvent` and return missing `EventTable` rows.

## Follow-Ups

1. Create a dedicated inspection page for OpenCode workspace sync with exact line anchors if this topic becomes a recurring code-reading target.
2. Inspect how UI clients bridge DB changes and in-memory event streams when two local OpenCode processes share one DB but not one `GlobalBus`.
3. Verify whether production deployments ever intentionally give multiple remote OpenCode instances access to the same SQLite path, and document the supported concurrency boundary.

## Related Pages

- [[wiki/index]]
- [[wiki/inspections/opencode-session-revert-two-layer-semantics]]
