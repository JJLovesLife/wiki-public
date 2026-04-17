# Log

Append-only operational history for this wiki.

## [2026-04-17] scaffold | initialize source-first llm wiki vault
- Added the initial directory layout, `AGENTS.md`, `README.md`, `log.md`, and `wiki/index.md`.
- Established `sources/files/` as immutable storage and `wiki/` as the LLM-owned knowledge layer.

## [2026-04-17] ingest | karpathy llm wiki
- Added the canonical local copy of Andrej Karpathy's `LLM Wiki` gist at `sources/files/karpathy-llm-wiki.md`.
- Created the initial source note for the seed source.

## [2026-04-17] ingest | obsidian cli help
- Added a local copy of [[sources/files/obsidian-cli-help]] and the corresponding source note [[wiki/sources/obsidian-cli-help]].
- Added [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]] to capture the most useful CLI workflows for this vault.
- Added `scripts/obsidian-wiki-health.sh` for Obsidian-aware wiki health checks.
- Updated [[wiki/index]] and [[AGENTS]] to document the new source, synthesis, exact-copy URL ingest rule, and wiki-only Obsidian lint guidance.

## [2026-04-17] schema | yaml frontmatter for source notes
- Updated [[AGENTS]] so `wiki/sources/` uses YAML frontmatter as the canonical metadata layer for source notes.
- Converted [[wiki/sources/karpathy-llm-wiki]] and [[wiki/sources/obsidian-cli-help]] from Markdown metadata blocks to frontmatter.
- Updated [[README]] to reflect the frontmatter-based source-note shape.
