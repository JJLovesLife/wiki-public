# Obsidian CLI For Wiki Maintenance

## Question

How can Obsidian CLI help maintain and improve this wiki?

## Answer

Obsidian CLI is useful here because it operates on the vault the same way Obsidian does, not just as a folder of markdown files. For this repository, its biggest value is vault-aware maintenance: checking unresolved links, spotting orphan and dead-end notes, inspecting backlinks, searching for required section headings, and using Obsidian-managed rename or move operations when reorganizing notes.

One caveat matters in this repo: files under `sources/files/` are immutable raw copies, and some upstream markdown files contain their own Obsidian wikilinks. That means `obsidian unresolved` can report noise from raw sources that should not automatically be treated as damage in the maintained `wiki/` layer.

The most useful command set for this wiki is:

```bash
obsidian unresolved counts verbose format=json
obsidian orphans
obsidian deadends
obsidian backlinks path="wiki/sources/karpathy-llm-wiki.md" counts format=json
obsidian links path="wiki/index.md"
obsidian search:context query="## Related Pages" path="wiki" format=json
obsidian outline path="wiki/sources/obsidian-cli-help.md" format=json
obsidian diff path="wiki/index.md"
obsidian history path="wiki/index.md"
```

For routine maintenance, the most practical pattern is:

1. Run link-health commands (`unresolved`, `orphans`, `deadends`) to catch structural problems.
2. Use `search:context` or `outline` to audit note shape against the schema in [[AGENTS]].
3. Use `backlinks` and `links` when strengthening navigation around source notes and synthesis pages.
4. Use `rename` or `move` through Obsidian when reorganizing notes, so internal links can be updated by the app.
5. If desired, append a recurring task to the daily note with `obsidian daily:append content="- [ ] lint wiki links"`.
6. Run `scripts/obsidian-wiki-health.sh` to check wiki-only unresolved links, wiki orphans, wiki dead ends, and required section headings.

## Evidence

- The CLI help explicitly positions the tool as a way to do from the terminal what Obsidian can do in the app, including links, search, history, tasks, properties, and developer commands. [[wiki/sources/obsidian-cli-help]]
- Running the CLI against this vault on 2026-04-17 confirmed that it can surface real maintenance data immediately, but it also exposed a repo-specific nuance: unresolved links from raw source copies need to be filtered out when evaluating wiki health. [[wiki/sources/obsidian-cli-help]]
- The current wiki schema relies heavily on stable internal links, related-page sections, and consistent note shapes; those are all areas where Obsidian-aware commands are more informative than plain filesystem inspection. [[wiki/sources/karpathy-llm-wiki]]

## Follow-Ups

1. Extend `scripts/obsidian-wiki-health.sh` if we want stricter checks such as minimum backlink counts for source notes or index coverage for new durable pages.
2. Decide whether to adopt Obsidian properties for source metadata so the CLI `properties` command becomes more informative.
3. Use `search:context` and `backlinks` together to identify thin notes that need more related-page links.

## Related Pages

- [[wiki/index]]
- [[wiki/sources/obsidian-cli-help]]
- [[wiki/sources/karpathy-llm-wiki]]
- [[AGENTS]]
