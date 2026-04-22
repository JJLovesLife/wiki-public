# LLM Wiki Vault

This repository is an Obsidian-friendly personal knowledge base built around the LLM wiki pattern.

## Start Here

- Human browsing: `wiki/index.md`
- LLM workflow rules: `AGENTS.md`
- Ingested source notes: `wiki/sources/`
- Code inspection notes: `wiki/inspections/`
- Change history: Git commit log

## Layout

- `sources/files/` stores immutable raw source files.
- `wiki/` is the LLM-maintained knowledge layer.
- `wiki/sources/` holds source notes with YAML frontmatter metadata for ingested sources.
- `wiki/inspections/` holds unified code-investigation notes backed by multiple files or call sites.
- `wiki/concepts/` holds synthesized concept pages when topics grow beyond a single source note.
- `wiki/entities/` holds named-entity pages.
- `wiki/syntheses/` holds durable query outputs.

## Typical Workflow

1. Add a raw source file under `sources/files/`, give the LLM a URL to fetch, or point the LLM at a code question for a local repository snapshot.
2. Ask the LLM to ingest the source or inspect the code.
3. Review `wiki/index.md`, the updated source note or inspection note, and any other updated wiki pages in Obsidian.
4. Ask questions against the wiki and keep useful answers by filing them into `wiki/syntheses/` or `wiki/inspections/` as appropriate.
5. Use Git as the canonical history. Keep commits small and follow the commit message schema in `AGENTS.md`.

## Git Commit Messages

- Git replaces `log.md` as the operational history for this vault.
- Prefer one durable wiki task per commit.
- Use the subject format `<kind>: <subject>`.
- Common kinds: `ingest`, `inspect`, `synthesize`, `concept`, `entity`, `schema`, `lint`, `reorg`, `docs`.
- Add a short body when the reason or scope is not obvious.
- Full commit-message rules live in `AGENTS.md`.

## Notes

- Raw source files are immutable after creation.
- Code investigations should live in `wiki/inspections/` and cite repository paths plus a commit or snapshot when possible.
- The wiki is expected to evolve continuously as more sources are added.
- The page shapes and maintenance workflow live in `AGENTS.md`; source notes use YAML frontmatter for stable machine-readable metadata.
- There is intentionally no separate `templates/` directory in this first version.
