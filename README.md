# LLM Wiki Vault

This repository is an Obsidian-friendly personal knowledge base built around the LLM wiki pattern.

## Start Here

- Human browsing: `wiki/index.md`
- LLM workflow rules: `AGENTS.md`
- Ingested source notes: `wiki/sources/`
- Code inspection notes: `wiki/inspections/`
- Chronological history: `log.md`

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
5. Use Git for detailed history; keep `log.md` short.

## Notes

- Raw source files are immutable after creation.
- Code investigations should live in `wiki/inspections/` and cite repository paths plus a commit or snapshot when possible.
- The wiki is expected to evolve continuously as more sources are added.
- The page shapes and maintenance workflow live in `AGENTS.md`; source notes use YAML frontmatter for stable machine-readable metadata.
- There is intentionally no separate `templates/` directory in this first version.
