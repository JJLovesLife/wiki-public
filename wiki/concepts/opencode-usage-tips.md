## Definition

OpenCode usage tips 是这个 wiki 里用来记录 OpenCode 实际使用经验的页面，尤其是那些没有被官方文档明确覆盖、但会影响日常协作和 context 管理的行为。

## Why It Matters

这些提示可以减少重复摸索。OpenCode 的有些行为来自编辑器集成、后台监听或本地配置路径；如果不知道这些机制，LLM 看到的 context 可能会显得“凭空出现”或“不知道为什么缺失”。

## Tips

### Active File Context

OpenCode 会扫描 `~/.claude/ide/`，监听 IDE 发来的 active file 消息，并据此插入一个 `system-reminder`，提示 LLM 当前相关的文件 context。

这个行为可以通过 OpenCode 里的 `Enable/Disable file context` 命令切换。关闭后，IDE 当前 active file 不会再自动作为额外 context 注入给 LLM；打开后，OpenCode 会重新使用来自 IDE 的 active file 信息。

如果 VS Code 安装了 Claude Code extension，它也会暴露相同类型的 active file 集成功能，让 OpenCode 可以监听 VS Code 当前打开或激活的文件。

当存在多个可能的 IDE folder / active-file 候选时，OpenCode 会按 folder 匹配长度选择最相关的候选；如果匹配长度相同，则选择最新的记录。目前这个机制只支持一个 active file，也就是最终只会注入一个文件相关的 context。

## Supporting Evidence

- User-provided OpenCode usage observation, 2026-04-30: OpenCode scans `~/.claude/ide/`, listens for IDE active-file messages, inserts a `system-reminder`, exposes `Enable/Disable file context` to toggle that behavior, selects candidates by folder match length and recency, and currently supports one active file.

## Related Pages

- [[AGENTS]]
- [[README]]
- [[wiki/index]]

## Open Questions

None yet.
