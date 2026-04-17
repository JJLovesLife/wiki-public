# LLM Wiki Vault

This repository is an Obsidian-friendly personal knowledge base built around the LLM wiki pattern.

## Start Here

- Human browsing: `wiki/index.md`
- LLM workflow rules: `AGENTS.md`
- Ingested source notes: `wiki/sources/`
- Chronological history: `log.md`

## Layout

- `sources/files/` stores immutable raw source files.
- `wiki/` is the LLM-maintained knowledge layer.
- `wiki/sources/` holds source notes and per-source metadata for ingested sources.
- `wiki/concepts/` holds synthesized concept pages when topics grow beyond a single source note.
- `wiki/entities/` holds named-entity pages.
- `wiki/syntheses/` holds durable query outputs.

## Typical Workflow

1. Add a raw source file under `sources/files/` or give the LLM a URL to fetch.
2. Ask the LLM to ingest the source.
3. Review `wiki/index.md`, the source note, and any other updated wiki pages in Obsidian.
4. Ask questions against the wiki and keep useful answers by filing them into `wiki/syntheses/`.
5. Use Git for detailed history; keep `log.md` short.

## Notes

- Raw source files are immutable after creation.
- The wiki is expected to evolve continuously as more sources are added.
- The page shapes and maintenance workflow live in `AGENTS.md`; there is intentionally no separate `templates/` directory in this first version.
