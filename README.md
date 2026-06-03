# LLM Wiki

This is a public, Quartz-rendered version of a personal LLM-maintained wiki.

The wiki collects source notes, code-reading inspections, concept pages, project reading maps, and durable syntheses from useful discussions. It is meant to preserve evidence and reasoning over time instead of re-deriving the same answers from scratch.

## Start Here

- [[wiki/index]] - Main wiki navigation.
- [[wiki/sources/karpathy-llm-wiki]] - Source note for the LLM wiki pattern that inspired this vault.
- [[AGENTS]] - Public note on how this site is maintained and what has been redacted.

## How To Read It

- `wiki/sources/` contains notes derived from individual document sources.
- `wiki/inspections/` contains code-reading investigations anchored to repository snapshots, files, functions, commits, or observed call paths.
- `wiki/concepts/` contains reusable concept pages that synthesize multiple notes.
- `wiki/projects/` contains reading maps for repository or subsystem clusters.
- `wiki/syntheses/` contains durable answers that came from questions or discussions.

## Evidence Maturity

Pages may have different levels of support:

- `source-backed`: grounded in a saved source note or public source URL.
- `inspection-backed`: grounded in a code-reading note for a specific repository snapshot.
- `conversation-derived`: useful synthesis from discussion, but not yet fully sourced.
- `needs-source`: worth keeping, but still needs stronger evidence.

Treat this site as a working knowledge base, not as final documentation. Code inspections can go stale when upstream repositories change, and synthesis pages may preserve uncertainty or open questions intentionally.

## Public Scope

This public branch publishes the interpreted wiki layer and public-facing method notes. Raw local source archives and private operational details are not part of the public site.
