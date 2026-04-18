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

## [2026-04-18] schema | add code inspection notes
- Added `wiki/inspections/` as the home for code-derived, multi-file investigation notes anchored to repository snapshots.
- Updated [[AGENTS]] and [[README]] to distinguish document source notes from code inspections and to use `## Supporting Evidence` for concept and entity pages.
- Updated [[wiki/index]] to list inspection pages as a first-class section.
- Updated `scripts/obsidian-wiki-health.sh` to lint inspection notes without requiring `repo_commit` when a stable commit is not available.

## [2026-04-18] inspect | mesa radv graphics queue family detection
- Added [[wiki/inspections/mesa-radv-graphics-queue-family-detection]] to trace how RADV decides whether to expose the graphics queue family in `vkGetPhysicalDeviceQueueFamilyProperties2`.
- Anchored the answer to Mesa commit `e9d00909f5082218159541d647182176ed237e60`, following the path from `radv_graphics_queue_enabled()` through winsys `query_info` to `DRM_AMDGPU_INFO` / `AMDGPU_INFO_HW_IP_INFO` and `available_rings`.
- Captured the `AMD_USERQ` exception where `num_queues` may be forced to `1` without counting `available_rings`, and updated [[wiki/index]].
- Rewrote [[wiki/inspections/mesa-radv-graphics-queue-family-detection]] into a mixed Chinese/English style so the prose is faster to scan while code terms, symbols, and paths stay in English.
- Updated [[wiki/index]] to match the same mixed style.
