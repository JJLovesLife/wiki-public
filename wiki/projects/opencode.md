# OpenCode

## Overview

This project hub groups durable notes about OpenCode as a whole: its product behavior, local and remote execution model, session/event architecture, console and UI-facing semantics, configuration, and practical usage patterns.

The current evidence base is still uneven. Most inspected code so far is concentrated around sessions, workspace synchronization, revert behavior, and local concurrency boundaries. That cluster should be treated as the first mapped region of the OpenCode project, not as the boundary of the project itself.

## Repositories And Scope

- `opencode` inspections are drawn from multiple commits on the `dev` branch.

Current covered areas:

- Session message, part, revert, and prompt-run behavior.
- Local multi-process concurrency boundaries around shared sessions and shared SQLite state.
- Workspace targets, remote synchronization, event replay, and projected session state.
- Practical usage observations such as active-file context injection.
- Console benchmark/evaluation result storage 和 UI-consumed data model。

Expected future scope:

- CLI and TUI behavior.
- Server/API boundaries and client SDK behavior.
- Agent, tool, permission, config, and plugin surfaces.
- Storage layout, event model, migrations, and sync reliability.
- Editor integration and day-to-day workflow ergonomics.

## Reading Map

Start with user-visible behavior and local workflow notes:

- [[wiki/concepts/opencode-usage-tips]] records practical OpenCode usage observations, including active-file context behavior and the command that toggles file context injection.

Then read session state semantics:

- [[wiki/inspections/opencode-session-revert-two-layer-semantics]] explains why OpenCode revert is two-layered: file changes are rolled back immediately, while message DB cleanup is delayed until a later action commits the pending revert.
- [[wiki/inspections/opencode-session-concurrent-prompt-instances]] explains that prompt serialization is process-local. One instance serializes or reuses a per-session runner, but separate processes sharing the same DB can concurrently advance the same session.

Then read workspace and sync behavior:

- [[wiki/syntheses/opencode-workspace-syncevent-sync]] explains local versus remote workspace semantics, `SyncEvent` replay, event logs, projector-updated DB tables, and why local shared-DB workspaces do not need remote sync.

Then read console benchmark/evaluation semantics:

- [[wiki/inspections/opencode-console-benchmark-evaluation-data-model]] 解释 console benchmark model：database row 存 loose JSON result data；tasks 是 benchmark cases；runs 最可能是 repeated attempts/sessions；judges 是 per scoring criterion 的 grader results。

Use this hub as the starting point for later OpenCode inspections even when the topic is not session-centric. New pages about CLI, tools, config, permissions, editor integration, or server APIs should attach here if they describe OpenCode behavior rather than a one-off usage note.

## Evidence Base

- The inspection pages are code-derived and anchored to specific `opencode` commits with exact file/function evidence.
- The workspace sync synthesis is inspection-backed from `opencode` snapshot `1afa9e32c9ebde43fc94782c883b422a3628daff`, but it is not yet split into its own dedicated inspection page.
- Console benchmark inspection 是来自 console routes 和 schema 的 consumer-side evidence；对 result producer 和 exact grading formula 的 interpretation 仍然是 provisional。
- The usage-tips concept page is conversation-derived from observed OpenCode behavior and should be upgraded with source or code evidence if it becomes operationally important.

## Open Questions

- What are the main OpenCode architectural seams across CLI/TUI, server routes, SDK clients, core storage, and app UI?
- How do agent, tool, permission, and config systems compose with session execution?
- Which editor integrations provide active-file context, and what is the authoritative code path for that injection?
- How reliable is the remote workspace sync path under reconnects, partial replay, stolen sessions, and multiple writers?
- Which OpenCode behaviors are stable product contracts versus incidental implementation details of the inspected snapshots?
- Benchmark `result` JSON 在哪里 produced？producer 是否 enforce console UI assumed 的同一套 semantics？

## Related Pages

- [[wiki/index]]
- [[wiki/concepts/opencode-usage-tips]]
- [[wiki/inspections/opencode-session-revert-two-layer-semantics]]
- [[wiki/inspections/opencode-session-concurrent-prompt-instances]]
- [[wiki/inspections/opencode-console-benchmark-evaluation-data-model]]
- [[wiki/syntheses/opencode-workspace-syncevent-sync]]
