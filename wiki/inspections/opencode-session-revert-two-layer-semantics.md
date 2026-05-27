---
type: inspection
title: "opencode session revert uses immediate file rollback and delayed message-db cleanup"
repo: opencode
repo_commit: 65ba1f6c138636e0e731905951845da2b76c9add
inspected_on: 2026-05-27
scope_paths:
  - packages/opencode/src/session/revert.ts
  - packages/opencode/src/session/session.ts
  - packages/opencode/src/session/projectors.ts
  - packages/opencode/src/session/processor.ts
  - packages/opencode/src/snapshot/index.ts
  - packages/opencode/src/cli/cmd/tui/routes/session/index.tsx
  - packages/app/src/pages/session.tsx
---

## Question

OpenCode 的 session revert 是什么时候 undo 文件修改，又是什么时候真正修改 messages DB？`session.revert` 在这个流程里代表什么状态？

## Answer

OpenCode 的 revert 分成两层：文件层 rollback 是实时发生的，messages DB 层的历史裁剪是延迟发生的。

当用户在 TUI 或 App 里点 `Revert` / `/undo` 时，前端调用 `session.revert` API。后端 `SessionRevert.revert()` 会立刻收集目标点之后的 `patch` parts，先用 `snap.track()` 记录当前工作区 snapshot，然后调用 `snap.revert(patches)` 把相关文件恢复到 patch 记录的 snapshot hash；如果文件在 snapshot 中不存在，则删除文件。这个动作会真实修改 worktree。

同一次 `session.revert` 调用还会把 `session.revert` 写进 DB。这个字段不是“已经提交删除历史”的标志，而是一个 pending revert 状态，记录当前 revert 边界，例如 `{ messageID, partID?, snapshot?, diff? }`。UI 根据它隐藏边界之后的消息，并展示 “N message reverted” / revert dock / restore 操作。

messages DB 的真正删除发生得更晚。用户进入 pending revert 后，可以继续 `/undo` 或 `/redo` 调整 revert 程度，也可以 `unrevert` 恢复到点击 revert 前的 snapshot。只有当用户继续发新 prompt、执行 shell、summarize 等需要从当前点继续会话的操作时，后端才调用 `SessionRevert.cleanup()`。`cleanup()` 会删除 revert 边界之后的 `message` / `part` rows，并清掉 `session.revert`，相当于 commit 这次 revert。

这个设计允许用户在 commit 前反复调整“回退到哪里”：文件状态会跟随当前 pending revert 实时变化，但会话消息历史先不立即破坏，直到用户真的从这个点继续。

## Trace

1. 前端进入 pending revert：TUI 的 message action 调用 `sdk.client.session.revert({ sessionID, messageID })`；TUI `/undo` 也会找上一个 user message 并调用同一个 API。App 侧也用 `revertMutation` 调用 `sdk.client.session.revert(input)`。
2. `SessionRevert.revert()` 读出 session 和所有 messages，找到目标 message/part 之后的 `patch` parts，构造 `rev` 边界。如果之前已经处在 pending revert，它会先 `snap.restore(session.revert.snapshot)` 回到最初点击 revert 前的工作区，然后再应用新的 revert 程度。
3. 文件 rollback 在 `SessionRevert.revert()` 内即时执行：`rev.snapshot = session.revert?.snapshot ?? (yield* snap.track())` 保存取消 revert 所需的当前 snapshot，随后 `yield* snap.revert(patches)` 恢复 patch 涉及的文件。
4. `Snapshot.revert()` 对每个 patch 文件执行 git checkout 到对应 `hash`；如果该文件在那个 snapshot 里不存在，就删除文件。因此文件层变化不是 UI 假象，也不是等 cleanup 才发生。
5. `SessionRevert.revert()` 最后调用 `sessions.setRevert(...)`，通过 `Session.Event.Updated` projector 把 pending state 写到 `SessionTable.revert` JSON 列。
6. UI 读取 `session.revert` 作为 pending state：TUI 隐藏 `message.id >= revert.messageID` 的消息并显示 reverted-message 提示；App 用 `revertMessageID` 过滤 visible user messages，并用 revert dock 提供 restore 操作。
7. 取消 pending revert 走 `SessionRevert.unrevert()`：它用 `session.revert.snapshot` 执行 `snap.restore(...)`，然后 `sessions.clearRevert(...)` 清掉 pending state。
8. 提交 pending revert 走 `SessionRevert.cleanup()`：它删除 revert 边界之后的 messages，或在 part-level revert 时删除目标 part 之后的 parts，最后 `sessions.clearRevert(...)`。删除通过 `MessageV2.Event.Removed` / `PartRemoved` projector 落到 DB。
9. `cleanup()` 不是前端直接调用的 API，而是在后端新动作入口前自动触发，例如发新 prompt、执行 shell、summarize。

## Evidence

- `packages/opencode/src/session/revert.ts:42-91`：`SessionRevert.revert()` 构造 `rev`，保存 `snapshot`，执行 `snap.restore(...)` / `snap.revert(patches)`，然后 `sessions.setRevert(...)`。
- `packages/opencode/src/snapshot/index.ts:377-490`：`Snapshot.revert()` 对 patch files 做 git checkout，checkout 失败且 snapshot 不含该路径时删除文件。
- `packages/opencode/src/session/session.ts:656-665`：`setRevert()` 把 `revert` 写入 session update，`clearRevert()` 把 `revert` 写成 `null`。
- `packages/opencode/src/session/projectors.ts:39-82`：`Session.Event.Updated` projector 把 partial session update 映射到 `SessionTable`，其中包含 `revert` 列。
- `packages/opencode/src/session/session.sql.ts:35`：`SessionTable.revert` 是 JSON text，包含 `messageID`、可选 `partID`、`snapshot`、`diff`。
- `packages/opencode/src/session/revert.ts:94-101`：`unrevert()` 用 `session.revert.snapshot` restore 文件状态，然后清掉 pending revert。
- `packages/opencode/src/session/revert.ts:104-144`：`cleanup()` 删除 messages/parts 并 `clearRevert()`，这才是 messages DB 层的提交。
- `packages/opencode/src/session/projectors.ts:108-118`：`MessageV2.Event.Removed` 删除 `MessageTable`，`PartRemoved` 删除 `PartTable`。
- `packages/opencode/src/session/processor.ts:108-119`、`357-389`、`463-477`：assistant run 前记录 snapshot，step finish 或 processor cleanup 时生成 `patch` part，供以后 revert 文件变化。
- `packages/opencode/src/cli/cmd/tui/routes/session/index.tsx:541-603`：TUI `/undo` 调 `session.revert`；`/redo` 要么把 revert 边界往后移，要么调用 `session.unrevert`。
- `packages/opencode/src/cli/cmd/tui/routes/session/index.tsx:1011-1143`：TUI 用 `session.revert` 隐藏 reverted messages，并显示 restore 提示和 diff 文件列表。
- `packages/app/src/pages/session.tsx:448-475`、`1623-1684`、`1701-1709`、`1923-1932`：App 侧用 `session.revert` 过滤消息，调用 revert/unrevert，并显示 revert dock。
- `packages/opencode/src/session/prompt.ts:730-731`、`1247-1249` 和 `packages/opencode/src/server/routes/instance/session.ts:589`：继续 shell、prompt、summarize 前自动 `revert.cleanup(session)`。

## Uncertainty

None noted for the inspected snapshot. Product terminology in UI uses “undo/redo/restore” somewhat differently from backend names: backend `unrevert` means cancel the whole pending revert and restore the pre-revert snapshot, while UI `redo` may either move the revert boundary forward or call backend `unrevert` when there is no next hidden user message.

## Related Pages

- [[wiki/index]]
