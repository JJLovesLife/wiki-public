---
type: source
title: "Managed Agents, unpacked: from tightly-coupled containers to a microkernel for agents"
author: Ying Hua
ingested_on: 2026-05-25
source_slug: herohua-managed-agents-architecture
local_file: sources/files/herohua-managed-agents-architecture.md
original_url: https://raw.githubusercontent.com/herohua/tech-notes/c2cbde05d4d93905471b787c46b3bab947516541/notes/managed-agents-architecture.md
published_url: https://herohua.github.io/managed-agents-architecture
source_commit: c2cbde05d4d93905471b787c46b3bab947516541
archived_html_file: sources/files/herohua-managed-agents-architecture.html
retrieved_on: 2026-05-25
---

# Herohua Managed Agents Architecture

## Summary

Ying Hua's article interprets Anthropic's Managed Agents design through an operating-system lens. It argues that the architecture is less like ordinary microservices and more like a capability-oriented microkernel for agents: a small trusted core mediates durable sessions, disposable harness workers, disposable sandboxes, credential resources, and the remote Claude model service.

The article's central decomposition is a recursive pets-to-cattle move: externalize the load-bearing state, and the thing that formerly held it becomes disposable. Applied to Managed Agents, this yields three moves: the harness leaves the sandbox, the session log leaves the harness, and credentials leave the sandbox.

## Key Takeaways

- The old design coupled harness loop, conversation state, working filesystem, shell, repo, and credentials inside one container; losing the container meant losing the agent.
- `Harness leaves sandbox` means the control loop and tool routing move outside the execution container, so sandbox failure can surface as tool failure rather than session death.
- `Session log leaves harness` makes harness instances disposable because a new harness can wake a session from the durable event log.
- `Credentials leave sandbox` reframes token handling as capability passing: the agent can act through approved resources without reading raw secrets.
- The article separates the word `harness` into at least two layers: a per-step reducer and a session-level driver/orchestrator.
- The OS analogy maps session to process identity, event log to write-ahead log, harness step to syscall handler, sandbox to address space/container, tool execution to syscall, and credential vault to keyring/capability broker.
- The biggest architectural implication is not only crash recovery, but that sandboxes or hands become transferable resources that can be passed between brains.

## Implications For This Wiki

- This page is the source note behind the discussion in [[wiki/syntheses/managed-agents-harness-sandbox-separation]].
- When using this article, distinguish Hua's interpretive OS lens from Anthropic's narrower implementation claims in [[wiki/sources/anthropic-scaling-managed-agents]].
- The `harness leaves sandbox` move should not be overread as exact process or filesystem recovery; it primarily changes ownership of the tool execution boundary.
- The article is useful as a conceptual bridge for future notes on agent operating systems, capability-based permissioning, effect logs, tool-call audit trails, and multi-agent handoff.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/anthropic-scaling-managed-agents]]
- [[wiki/syntheses/managed-agents-harness-sandbox-separation]]
