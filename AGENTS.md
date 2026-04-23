# LLM Wiki Schema

This file is the operating schema for this repository's LLM-maintained wiki.

## Purpose

The goal is to maintain a persistent, interlinked markdown knowledge base in `wiki/` on top of immutable raw sources in `sources/files/` and code inspections anchored to specific repository snapshots. The wiki should accumulate summaries, cross-references, contradictions, and syntheses over time instead of re-deriving them from scratch for every query.

## Ownership Boundaries

- Immutable raw sources: `sources/files/`
  - Never edit a raw source after it has been added.
  - If a source needs correction, add a new source or capture the correction in a wiki page.
- LLM-owned knowledge layer: `wiki/`
  - The LLM may create and update these as part of normal ingest, query, and lint work.
- Shared operational docs and helpers: `AGENTS.md`, `README.md`, `scripts/obsidian-wiki-health.sh`
  - Update these only when the workflow or structure actually changes.
- Everything else is user-owned unless the user explicitly asks for changes.

## Directory Layout

- `sources/files/` holds immutable local copies of raw sources.
- `wiki/index.md` is the main navigation file for the knowledge layer.
- `wiki/sources/` holds source notes derived from individual raw sources and is the primary metadata layer for ingested sources.
- `wiki/inspections/` holds unified notes for code-derived investigations that span multiple files, call sites, tests, configs, or layers within a repository snapshot.
- `wiki/concepts/` holds synthesized concept pages when a topic earns its own durable page.
- `wiki/entities/` holds pages for people, organizations, tools, places, or other named entities.
- `wiki/syntheses/` holds durable answers that originated from queries.
- `scripts/obsidian-wiki-health.sh` is an Obsidian-aware lint helper for the maintained `wiki/` layer.

## Naming Conventions

- Raw source files: `sources/files/slug.ext`
- Source notes: `wiki/sources/slug.md`
- Inspection pages: `wiki/inspections/slug.md`
- Concept pages: `wiki/concepts/slug.md`
- Entity pages: `wiki/entities/slug.md`
- Synthesis pages: `wiki/syntheses/slug.md`
- Source slugs should be short, stable, and human-readable.
- Inspection slugs should usually include the repository and subject, for example `mesa-radv-graphics-queue-family-support`.
- If two sources would naturally share a slug, disambiguate with a clear qualifier such as a year, publisher, or format.
- Default to explicit path-qualified wikilinks such as `[[wiki/sources/karpathy-llm-wiki]]` to avoid ambiguity.

## Global Conventions

- Prefer updating an existing page over creating a near-duplicate.
- Keep internal links dense enough that related pages are easy to follow in Obsidian.
- Keep claims anchored to evidence pages. Concept and entity pages should include a `## Supporting Evidence` section. Synthesis pages should include `## Evidence` with citations back to relevant source notes, inspection notes, and, when useful, raw sources.
- For code-derived claims, prefer a single inspection page in `wiki/inspections/` over fake per-file source notes. Anchor file and line references to `repo_commit` and prefer commit-pinned URLs when available.
- Preserve uncertainty and disagreement. If newer sources conflict with older ones, note the conflict instead of silently overwriting it.
- Git commit history is the canonical operational history for this wiki.
- Prefer small, logically grouped commits so the vault's evolution stays easy to review.
- Do not create a separate `templates/` system unless the user asks for it. The required page shapes live in this file.
- Do not create concept pages that only restate a single source note unless the user asks for that extra structure or the page is clearly becoming a durable hub.

## Git Commit Message Schema

Git replaces `log.md` as the durable operational history for this vault. When creating commits, use a consistent message shape so history is readable inside Git itself.

- Prefer one durable wiki action per commit when practical. Split unrelated topics into separate commits.
- Use a subject line in the form `<kind>: <subject>`.
- Keep `<subject>` short, human-readable, and specific to the source slug, inspection slug, concept, entity, or schema change.
- Common `kind` values:
  - `ingest` for new raw sources and their source notes.
  - `inspect` for code investigation notes.
  - `synthesize` for durable query answers saved to the wiki.
  - `concept` for concept-page additions or major updates.
  - `entity` for entity-page additions or major updates.
  - `schema` for workflow, layout, naming, or page-shape changes.
  - `lint` for cross-link, metadata, wording, or structural maintenance.
  - `reorg` for renames, moves, and larger vault reshaping.
  - `docs` for README or helper-documentation updates that are not schema changes.
- Add a body when the reason is not obvious from the subject or when the commit spans multiple files.
- In the body, start with 1-2 sentences on why the change matters. Then optionally list the materially affected pages or inspected repository snapshot.
- For inspection commits, include the inspected repository and commit hash in the body when that provenance is important.

Examples:

- `ingest: obsidian cli help`
- `inspect: linux idr preload purpose`
- `synthesize: obsidian cli for wiki maintenance`
- `schema: replace log.md with git history`
- `lint: repair source-note cross-links`

## Required Page Shapes

### Source Pages

Every file in `wiki/sources/` should begin with YAML frontmatter for stable machine-readable metadata, followed by these sections:

1. `## Summary`
2. `## Key Takeaways`
3. `## Implications For This Wiki`
4. `## Related Pages`

Source-page frontmatter should normally include these flat fields when known:

- `type: source`
- `title`
- `author`
- `ingested_on`
- `source_slug`
- `local_file`
- `original_url` when the source came from a URL
- `retrieved_on` when the source came from a URL fetch

### Inspection Pages

Every file in `wiki/inspections/` should begin with YAML frontmatter for stable machine-readable metadata, followed by these sections:

1. `## Question`
2. `## Answer`
3. `## Trace`
4. `## Evidence`
5. `## Uncertainty`
6. `## Related Pages`

Inspection-page frontmatter should normally include these fields when known:

- `type: inspection`
- `title`
- `repo`
- `repo_commit`
- `inspected_on`
- `scope_paths`

If there are no uncertainties yet, say `None noted.`

### Concept And Entity Pages

Every file in `wiki/concepts/` and `wiki/entities/` should include these sections:

1. `## Definition`
2. `## Why It Matters`
3. `## Supporting Evidence`
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
2. If the user only provided a URL, fetch a stable local copy into `sources/files/slug.ext` using a direct download tool such as `curl` so the stored raw source is an exact local copy without editing, normalizing, or reformatting the contents.
3. Read `wiki/index.md`, the raw source, and any obviously related pages.
4. Create or update the corresponding source note in `wiki/sources/`, including YAML frontmatter metadata.
5. Update all materially affected concept, entity, or synthesis pages.
6. Update `wiki/index.md` so every new or materially changed page is represented by a one-line summary.
7. If the source is broad and the desired emphasis is unclear, ask the user a short targeted question. Otherwise make a reasonable first pass and let the user refine it.

### Inspect

Use this workflow when the user asks a question whose answer comes from source code, tests, configs, or multiple call sites rather than from a single document.

1. Confirm the repository and the revision or snapshot being inspected. When possible, record an exact commit hash.
2. Read `wiki/index.md` first, then any existing inspection, concept, entity, or synthesis pages that seem related.
3. Trace the answer across the relevant files, call sites, tests, configs, logs, or layers instead of treating a single file as the whole source.
4. Create or update a unified inspection note in `wiki/inspections/`, including YAML frontmatter metadata and exact evidence references.
5. Update all materially affected concept, entity, or synthesis pages.
6. Update `wiki/index.md` so every new or materially changed page is represented by a one-line summary.
7. If the question is too broad for one inspection page, ask a short targeted question or split it into clearly named inspection pages.

### Query

Use this workflow when answering questions against the wiki.

1. Read `wiki/index.md` first.
2. Read the most relevant pages from `wiki/`.
3. Read page frontmatter and recent Git history when recency matters.
4. Answer with citations to wiki pages and, when useful, raw source links.
5. If the answer is durable and broadly useful, save it as a new or updated page under `wiki/syntheses/`. If the answer is primarily a repo-specific code investigation, save or update a page under `wiki/inspections/` instead. Then update `wiki/index.md`.

### Lint

Use this workflow when checking the health of the wiki.

1. Look for contradictions, stale claims, orphan pages, missing cross-references, missing source or inspection pages, broken links, and concept gaps.
2. When using Obsidian-aware link checks, treat `wiki/` as the primary health surface. Raw source copies under `sources/files/` may contain upstream wikilinks and should not automatically be treated as wiki breakage.
3. Use `scripts/obsidian-wiki-health.sh` when it fits the task, or perform equivalent checks manually.
4. Make small maintenance fixes directly when the intent is clear.
5. If the lint pass reveals a larger structural issue, summarize it clearly for the user.
6. Update `wiki/index.md` whenever the lint pass produces durable changes.

## Operational Defaults

- Start navigation in `wiki/index.md`.
- Treat `wiki/sources/` as the canonical set of ingested document source notes.
- Treat `wiki/inspections/` as the canonical set of code-derived investigation notes.
- Treat Git history as the canonical operational history for the vault.
- Keep raw sources immutable and keep the wiki as the maintained interpretation layer.
- For Obsidian CLI linting, judge wiki health primarily on `wiki/`, not on upstream wikilinks embedded inside raw source copies.
