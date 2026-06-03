# Public Maintenance Note

This page is a redacted public version of the internal maintenance schema for this LLM wiki.

The private branch contains operational instructions used while writing, ingesting sources, inspecting code, and linting the vault. This public page exists so links to `[[AGENTS]]` remain meaningful without publishing private workflow details or local-only source archives.

## What This Wiki Is

This wiki is an LLM-maintained Markdown knowledge base. It keeps an interpreted layer under `wiki/` and organizes durable knowledge into source notes, code inspections, concept pages, project hubs, and synthesis pages.

The goal is accumulation: each useful source read, code trace, or discussion can become a page that future work can cite instead of re-deriving the same context.

## Public And Private Boundary

- The public site publishes the maintained `wiki/` layer.
- Raw local archives under `sources/files/` are not published by default.
- Some wiki pages may mention a `local_file` path for provenance; those paths refer to private archival copies, not public downloads.
- Internal automation, local lint helpers, and editing instructions may be omitted or summarized here.

## Page Families

- `wiki/sources/` records notes derived from individual document sources.
- `wiki/inspections/` records code-reading investigations and should cite repository snapshots, commits, files, functions, or call paths when available.
- `wiki/concepts/` records reusable concepts that have grown beyond a single source note.
- `wiki/projects/` records reading maps for repository, subsystem, or related-project clusters.
- `wiki/syntheses/` records durable answers and discussion outcomes.

## Evidence Labels

The wiki may preserve evidence maturity in page prose:

- `source-backed` means a claim is grounded in a source note or public source URL.
- `inspection-backed` means a claim is grounded in a code investigation.
- `conversation-derived` means a claim came from discussion and may need stronger source backing.
- `needs-source` marks useful but under-supported knowledge.

## Reliability

This is a working knowledge base. It is useful because it preserves context, uncertainty, links, and evidence, but it should not be read as final authority.

When sources conflict, the preferred behavior is to record the conflict rather than erase it. When code-derived notes age, the relevant repository commit or snapshot should be checked before relying on the conclusion.
