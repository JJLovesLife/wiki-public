---
type: source
title: Obsidian CLI
author: Obsidian Help
ingested_on: 2026-04-17
source_slug: obsidian-cli-help
local_file: sources/files/obsidian-cli-help.md
original_url: https://obsidian.md/help/cli
retrieved_on: 2026-04-17
---

# Obsidian CLI Help

## Summary

The Obsidian CLI exposes the running Obsidian app and the active vault to terminal commands. It covers note creation and editing, search, link graph inspection, file history, tasks, properties, plugin management, and some developer tooling.

## Key Takeaways

- If the current working directory is a vault, the CLI targets that vault automatically.
- `file=<name>` uses Obsidian's normal note resolution, while `path=<path>` targets an exact vault-relative file path.
- The highest-value maintenance commands for this wiki are `unresolved`, `orphans`, `deadends`, `backlinks`, `links`, `search`, `search:context`, `outline`, `diff`, `history`, and `move`/`rename`.
- The CLI can drive daily-note tasks and lightweight operational routines without leaving the vault.
- The app must be running, so the CLI complements filesystem and Git tooling rather than replacing them.

## Implications For This Wiki

- We can lint the vault's link graph directly from Obsidian instead of inferring it only from raw markdown files.
- We can use Obsidian-aware rename and move operations when reorganizing notes so links stay consistent.
- We can query headings and maintenance phrases inside `wiki/` to spot missing sections and weak cross-linking.
- We can keep recurring wiki maintenance visible by adding tasks to Obsidian daily notes.

## Related Pages

- [[wiki/index]]
- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]]
- [[wiki/sources/karpathy-llm-wiki]]
- [[log]]
