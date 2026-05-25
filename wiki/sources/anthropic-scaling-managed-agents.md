---
type: source
title: "Scaling Managed Agents: Decoupling the brain from the hands"
author: Lance Martin, Gabe Cemaj, Michael Cohen
ingested_on: 2026-05-25
source_slug: anthropic-scaling-managed-agents
local_file: sources/files/anthropic-scaling-managed-agents.md
original_url: https://www.anthropic.com/engineering/managed-agents
retrieved_on: 2026-05-25
archived_html_file: sources/files/anthropic-scaling-managed-agents.html
conversion: readable markdown conversion from retrieved page body
---

# Anthropic Scaling Managed Agents

## Summary

Anthropic describes Managed Agents as a hosted service for long-horizon agent work built around stable interfaces for sessions, harnesses, and sandboxes. The article says the original implementation placed all agent components in one container, making that container a pet: if it failed, the session was lost, and debugging required entering an environment that often held user data.

The redesigned system decouples the brain, hands, and session. The brain is Claude plus its harness; hands are sandboxes and tools that perform actions; the session is the durable append-only event log. The harness calls hands through `execute(name, input) -> string`, wakes sessions through `wake(sessionId)`, and records durable events through `emitEvent(id, event)`.

## Key Takeaways

- Anthropic's initial coupled design put session, harness, and sandbox in one container; this made container failure a session failure and made stuck-session debugging difficult.
- Decoupling the brain from the hands means the harness no longer lives inside the container. The container is called like any other tool through `execute(name, input) -> string`.
- If a container dies, the harness catches the failure as a tool-call error and passes it back to Claude. If Claude decides to retry, a new container can be initialized with `provision({resources})`.
- Harness failure recovery depends on the session log living outside the harness. A new harness can `wake(sessionId)`, call `getSession(id)`, read the event log, and resume from the last event.
- Credentials are kept outside the sandbox. Git access is wired into the local remote during sandbox initialization, and MCP OAuth tokens live in a secure vault accessed by a dedicated proxy.
- The session is not just Claude's context window. It is a durable context object that can be interrogated with `getEvents()` and transformed by the harness before being passed into Claude's context.
- `Many brains` means stateless harnesses can start inference before a sandbox is provisioned. Anthropic reports about 60% lower p50 TTFT and over 90% lower p95 TTFT from this lazy provisioning shape.
- `Many hands` means a brain can address multiple execution environments or tools through the same interface, and hands are not coupled to a single brain.

## Implications For This Wiki

- This source anchors the factual claims behind [[wiki/syntheses/managed-agents-harness-sandbox-separation]], especially the exact limits of sandbox failure recovery.
- The article supports the distinction between session-level recovery and tool/effect-level control, but it does not claim exact restoration of bash process state or filesystem deltas after sandbox failure.
- The article is useful for future concept pages about `session log`, `harness`, `sandbox`, `tool-call boundary`, `effect log`, `credential vault`, and `many brains/many hands` patterns.
- The strongest practical takeaway is that a managed-agent platform should be opinionated about interfaces around Claude while allowing harnesses, sandboxes, and tools to change underneath.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/herohua-managed-agents-architecture]]
- [[wiki/syntheses/managed-agents-harness-sandbox-separation]]
