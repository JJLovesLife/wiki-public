# LLM Wiki Vault

This repository is an Obsidian-friendly personal knowledge base built around the LLM wiki pattern.

## Start Here

- Human browsing: `wiki/index.md`
- LLM workflow rules: `AGENTS.md`
- Ingested source notes: `wiki/sources/`
- Code inspection notes: `wiki/inspections/`
- Repo/project reading maps: `wiki/projects/`
- Change history: Git commit log

## Layout

- `sources/files/` stores immutable raw source files.
- `wiki/` is the LLM-maintained knowledge layer.
- `wiki/sources/` holds source notes with YAML frontmatter metadata for ingested sources.
- `wiki/inspections/` holds unified code-investigation notes backed by multiple files or call sites.
- `wiki/concepts/` holds synthesized concept pages when topics grow beyond a single source note.
- `wiki/entities/` holds named-entity pages.
- `wiki/projects/` holds repo, subsystem, or related-repository hub pages for code-reading clusters.
- `wiki/syntheses/` holds durable query outputs.

## Typical Workflow

1. Add a document source under `sources/files/`, give the LLM a URL to fetch, or point the LLM at a code question for a repository snapshot.
2. Ask the LLM to ingest the document source or inspect the code source.
3. Review `wiki/index.md`, the updated source note or inspection note, and any other updated wiki pages in Obsidian.
4. Ask questions against the wiki and keep useful answers by filing them into `wiki/syntheses/` or `wiki/inspections/` as appropriate. Useful multi-turn discussions may become synthesis pages even when they are not a strict Q&A.
5. Use Git as the canonical history. Keep commits small and follow the commit message schema in `AGENTS.md`.

## Git Commit Messages

- Git replaces `log.md` as the operational history for this vault.
- Prefer one durable wiki task per commit.
- Use the subject format `<kind>: <subject>`.
- Common kinds: `ingest`, `inspect`, `synthesize`, `concept`, `entity`, `project`, `schema`, `lint`, `reorg`, `docs`.
- Add a short body when the reason or scope is not obvious.
- Full commit-message rules live in `AGENTS.md`.

## Notes

- Raw source files are immutable after creation.
- Code investigations should live in `wiki/inspections/` and cite repository paths plus a commit or snapshot when possible.
- Repo/project hubs should live in `wiki/projects/` once a code-reading cluster becomes too large for a flat index entry.
- Synthesis pages may be source-backed, inspection-backed, conversation-derived, or in need of stronger sources; preserve that evidence maturity when it matters.
- The wiki is expected to evolve continuously as more sources are added.
- The page shapes and maintenance workflow live in `AGENTS.md`; source notes use YAML frontmatter for stable machine-readable metadata.
- There is intentionally no separate `templates/` directory in this first version.
