---
type: source
title: LLM Wiki
author: Andrej Karpathy
ingested_on: 2026-04-17
source_slug: karpathy-llm-wiki
local_file: sources/files/karpathy-llm-wiki.md
original_url: https://gist.githubusercontent.com/karpathy/442a6bf555914893e9891c11519de94f/raw/ac46de1ad27f92b28ac95459c782c07f6b8c964a/llm-wiki.md
retrieved_on: 2026-04-17
---

# Karpathy LLM Wiki

## Summary

Karpathy proposes a pattern where an LLM incrementally builds and maintains a persistent markdown wiki on top of a curated set of immutable source documents. Instead of re-solving each question with retrieval over raw files, the LLM keeps a standing synthesis current through ingest, query, and lint workflows.

## Key Takeaways

- The main artifact is a maintained wiki, not just a retrieval layer over documents.
- The architecture has three parts: immutable raw sources, an LLM-owned wiki, and a schema document that defines maintenance behavior.
- The recurring workflows are ingest, query, and lint.
- `index.md` and `log.md` are special navigation files with different jobs: one content-oriented, one chronological.
- Obsidian and Git make the pattern practical without requiring heavy retrieval infrastructure at small to medium scale.

## Implications For This Wiki

- Keep exact local copies of source material under `sources/files/`.
- Treat `AGENTS.md` as the schema layer and evolve it deliberately.
- Update `wiki/index.md` and `log.md` whenever a durable change lands.
- Save reusable answers from future queries into `wiki/syntheses/` so knowledge compounds over time.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/obsidian-cli-help]]
- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]]
- [[AGENTS]]
- [[log]]
