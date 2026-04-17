# LLM Wiki Schema

This file is the operating schema for this repository's LLM-maintained wiki.

## Purpose

The goal is to maintain a persistent, interlinked markdown knowledge base in `wiki/` on top of immutable raw sources in `sources/files/`. The wiki should accumulate summaries, cross-references, contradictions, and syntheses over time instead of re-deriving them from scratch for every query.

## Ownership Boundaries

- Immutable raw sources: `sources/files/`
  - Never edit a raw source after it has been added.
  - If a source needs correction, add a new source or capture the correction in a wiki page.
- LLM-owned knowledge layer: `wiki/`, `log.md`
  - The LLM may create and update these as part of normal ingest, query, and lint work.
- Shared operational docs: `AGENTS.md`, `README.md`
  - Update these only when the workflow or structure actually changes.
- Everything else is user-owned unless the user explicitly asks for changes.

## Directory Layout

- `sources/files/` holds immutable local copies of raw sources.
- `wiki/index.md` is the main navigation file for the knowledge layer.
- `wiki/sources/` holds source notes derived from individual raw sources and is the primary metadata layer for ingested sources.
- `wiki/concepts/` holds synthesized concept pages when a topic earns its own durable page.
- `wiki/entities/` holds pages for people, organizations, tools, places, or other named entities.
- `wiki/syntheses/` holds durable answers that originated from queries.
- `log.md` is a brief chronological history of ingests, queries, lint passes, and major maintenance.

## Naming Conventions

- Raw source files: `sources/files/slug.ext`
- Source notes: `wiki/sources/slug.md`
- Concept pages: `wiki/concepts/slug.md`
- Entity pages: `wiki/entities/slug.md`
- Synthesis pages: `wiki/syntheses/slug.md`
- Source slugs should be short, stable, and human-readable.
- If two sources would naturally share a slug, disambiguate with a clear qualifier such as a year, publisher, or format.
- Default to explicit path-qualified wikilinks such as `[[wiki/sources/karpathy-llm-wiki]]` to avoid ambiguity.

## Global Conventions

- Prefer updating an existing page over creating a near-duplicate.
- Keep internal links dense enough that related pages are easy to follow in Obsidian.
- Keep claims anchored to source pages. Concept, entity, and synthesis pages should include a `Supporting sources` section.
- Preserve uncertainty and disagreement. If newer sources conflict with older ones, note the conflict instead of silently overwriting it.
- Keep `log.md` brief. Detailed history belongs in Git.
- Do not create a separate `templates/` system unless the user asks for it. The required page shapes live in this file.
- Do not create concept pages that only restate a single source note unless the user asks for that extra structure or the page is clearly becoming a durable hub.

## Required Page Shapes

### Source Pages

Every file in `wiki/sources/` should include these sections:

1. `## Source Metadata`
2. `## Summary`
3. `## Key Takeaways`
4. `## Implications For This Wiki`
5. `## Related Pages`

`## Source Metadata` should normally include title, author if known, added date, URL if applicable, source slug, and a link to the local raw file.

### Concept And Entity Pages

Every file in `wiki/concepts/` and `wiki/entities/` should include these sections:

1. `## Definition`
2. `## Why It Matters`
3. `## Supporting Sources`
4. `## Related Pages`
5. `## Open Questions`

If there are no open questions yet, say `None yet.`

### Synthesis Pages

Every file in `wiki/syntheses/` should include these sections:

1. `## Question`
2. `## Answer`
3. `## Evidence`
4. `## Follow-Ups`
5. `## Related Pages`

## Core Workflows

### Ingest

Use this workflow when the user asks to process a new source.

1. Confirm the raw source exists in `sources/files/`.
2. If the user only provided a URL, fetch a stable local copy into `sources/files/slug.ext` without editing the contents.
3. Read `wiki/index.md`, the raw source, and any obviously related pages.
4. Create or update the corresponding source note in `wiki/sources/`, including its source metadata.
5. Update all materially affected concept, entity, or synthesis pages.
6. Update `wiki/index.md` so every new or materially changed page is represented by a one-line summary.
7. Append a brief entry to `log.md` using the format `## [YYYY-MM-DD] action | subject`.
8. If the source is broad and the desired emphasis is unclear, ask the user a short targeted question. Otherwise make a reasonable first pass and let the user refine it.

### Query

Use this workflow when answering questions against the wiki.

1. Read `wiki/index.md` first.
2. Read the most relevant pages from `wiki/`.
3. Read recent `log.md` entries when recency matters.
4. Answer with citations to wiki pages and, when useful, raw source links.
5. If the answer is durable and broadly useful, save it as a new or updated page under `wiki/syntheses/`, then update `wiki/index.md` and `log.md`.

### Lint

Use this workflow when checking the health of the wiki.

1. Look for contradictions, stale claims, orphan pages, missing cross-references, missing source pages, broken links, and concept gaps.
2. Make small maintenance fixes directly when the intent is clear.
3. If the lint pass reveals a larger structural issue, summarize it clearly for the user.
4. Update `wiki/index.md` and `log.md` whenever the lint pass produces durable changes.

## Operational Defaults

- Start navigation in `wiki/index.md`.
- Treat `wiki/sources/` as the canonical set of ingested source notes.
- Treat `log.md` as append-only operational history.
- Keep raw sources immutable and keep the wiki as the maintained interpretation layer.
