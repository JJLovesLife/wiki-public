# Managed Agents Harness Sandbox Separation

## Question

如何理解 Managed Agents 架构里 `harness leaves sandbox`、`many brains, many hands`、tool-call 粒度控制和恢复语义？如果一个团队直接托管 Claude Code 或类似 CLI agent，而不是拥有 Anthropic 那样成熟的 agent framework，这种 harness/sandbox 分离是否值得？

## Answer

最有用的理解不是“harness/sandbox 分离让架构更干净”，而是：平台的最小可控单元从 `session/container` 下沉到 `tool call/effect`。

```text
supervisor + session log: 恢复一个黑盒 agent
harness/sandbox 分离: 管理 agent 发出的每个 effect
```

在只做外部 supervisor 的模式下，控制层通常负责 session log 持久化、容器启停、健康检查和崩溃后重启。Claude Code 或其它 harness 仍在 sandbox/container 里，LLM loop、tool dispatch、shell、repo 和一部分凭证机制仍然处在同一个黑盒内。这个模式实现成本低，适合快速托管现有 CLI agent，也能覆盖基本 session 恢复需求。

在 harness/sandbox 分离的模式下，harness 不再住在执行环境里。它通过 `execute(name, input) -> string` 调用 sandbox 或其它 tool，sandbox/container 只是一个可替换的 hand。session log 外置使 harness 自己可恢复，而 harness 离开 sandbox 使 sandbox failure 不再等同于 agent runtime failure。

这两步解决的问题不同：

| Move | 解决的问题 | 让谁变成 cattle |
|---|---|---|
| Harness leaves sandbox | 控制逻辑不和执行环境同生共死 | Sandbox |
| Session log leaves harness | 会话状态不和控制进程同生共死 | Harness |

即使 session log 已经外置，harness 离开 sandbox 仍然有意义。外置 session log 只能说明 harness 挂了可以 `wake(sessionId)` 恢复；它不能说明 sandbox 挂了时，平台仍然有一个活着的控制面可以记录、解释、重试、降级或路由这次 tool failure。

关键收益来自 tool-call boundary。平台可以在副作用发生前后拥有一个不可绕过的 chokepoint：

```text
LLM/harness wants to act
-> platform policy/audit/scheduler sees the action
-> platform allows/denies/routes/records it
-> side effect happens
```

这会打开一组更具体的能力：

1. Step-level resume/retry：把 `ToolRequested`、`ToolStarted`、`ToolCompleted`、`ToolInterrupted` 记录成结构化事件，而不是只知道 container died。
2. Human approval gates：在 `git push`、deploy、生产 VPC 访问、破坏性 shell command 或昂贵 API call 发生前拦截。
3. Live control：取消当前 shell command、延长 timeout、重跑最后失败的 tool、跳过某一步，而不是杀掉整个 session。
4. Better progress UI：把用户看到的状态从 `agent is working` 改成 `running tests`、`waiting on MCP`、`git push blocked by approval` 这样的 timeline。
5. Policy and governance：不同 workspace、用户、agent role、tool、repo、环境使用不同权限、配额、审批和网络策略。
6. Resource scheduling：按 effect 调度资源，例如测试走 high-CPU sandbox，browser 走 browser pool，MCP 走 proxy，Git push 走 credential broker。
7. Cost controls：按 shell runtime、browser runtime、MCP call、high-CPU job 计费、限流、预算和排队。
8. Audit trail：回答“agent 到底对外部世界做了什么”，而不是只保存自然语言 transcript。
9. Multi-agent handoff：planner、coder、reviewer、security checker 或 human 可以围绕同一个 hand/sandbox 交接。
10. Replay/fork/compare：从某个 tool call 前 fork，对比不同 agent run，或者把失败 run 变成 eval case。

如果一个团队直接使用 Claude Code，完整自研 harness/sandbox 分离的代价通常很高。更现实的路线是分阶段拿回 tool execution boundary：

| 模式 | 控制力 | 成本 |
|---|---:|---:|
| 黑盒 Claude Code + supervisor | 低 | 低 |
| Claude Code hooks + 平台策略 | 中 | 中 |
| Claude Code 作为 harness，但高风险工具走平台代理 | 高 | 中高 |
| 自研 harness/sandbox 分离 | 最高 | 高 |

Claude Code 的 tool-call hooks 或类似机制可能实现一部分同样收益，但前提是 hook 是所有副作用的必经路径。如果 agent 仍然能在 sandbox 里读 token、改 git config、直接访问网络或调用未受控二进制，那么 hook 更像协作式观测和审批，不是安全边界。要让 hook-based 方案接近平台级权限控制，需要配合 sandbox 内不放长期 token、Git/MCP/VPC 通过平台代理、网络 egress 受控、settings 由平台注入且不能被 agent 修改。

恢复方面要保持克制。Anthropic 文章没有声称 sandbox/harness 分离能完美恢复 bash 进程或文件系统状态。原文描述的是：container died 后，harness 把它当作 tool-call error 传回 Claude；如果 Claude 决定 retry，平台用 `provision({resources})` 重新初始化一个 container。它更像：

```text
sandbox died
-> harness catches tool-call error
-> error passed back to Claude
-> Claude decides whether to retry
-> platform provisions a new sandbox from a standard recipe
```

这不是进程 checkpoint，也不是透明恢复到崩溃前一毫秒。它不能天然恢复正在执行的一半 bash 命令、未 flush 的 stdout/stderr、临时文件、未持久化 working tree、后台进程或已经发生但没有记录的外部副作用。如果目标是最大程度恢复真实执行状态，需要额外机制，例如 persistent volume、filesystem snapshot、git auto-commit/checkpoint、VM/container checkpoint 或 CRIU/Firecracker snapshot 一类技术。即使如此，外部副作用仍然难以精确回滚。

因此，这篇文章中的恢复价值更准确地说是 failure containment 和 recovery control point，而不是 exact execution recovery。

`many brains, many hands` 也要按 tool 类型理解。`many brains` 指 stateless harness/Claude loop 可以独立扩缩容，不必每个 session 都先 provision 一个完整 container，所以可以降低 TTFT。`many hands` 指一个 brain 可以通过统一接口连接多个 execution environment 或 tool，hand 也可以被不同 brain 接手。

对 bash 这种 hand，many-hands 并不天然舒服。bash 是一个 stateful world，不只是 `input -> output` 的普通 tool；它有当前目录、文件系统状态、依赖缓存、后台进程、临时文件和隐式 mutation。让一个 brain 同时操作多个 bash sandbox 容易造成上下文混乱。更合理的模式是一个 task 有一个 primary bash sandbox，再加上命名清楚的辅助 hands，例如 browser、phone、MCP、Git、VPC command runner。对 bash 来说，更有价值的是同一个 sandbox 可以被 planner、coder、reviewer 或新 brain 接手，而不是一个 brain 同时操控很多 shell。

物理部署方面，文章没有规定 harness 和 sandbox 必须在不同机器。它承诺的是接口级、故障域级和信任边界级分离。最小实现可以是同一台机器上 host harness 进程调用本机 container；更平台化的实现可能是 control-plane fleet 上运行 orchestration/harness/session log，worker fleet 上按需 provision sandbox/container/VM/device，credential vault 和 MCP proxy 作为平台服务存在。判断标准不是“是否跨机器”，而是 sandbox failure 是否会杀死 harness、tool effect 是否经过平台控制点、credential 是否仍然可被 sandbox 读到。

最终判断：如果目标只是托管 Claude Code、备份 session、容器挂了能重启，supervisor + session log 已经很实用，完整 harness/sandbox 分离未必值得。如果目标是 managed agents platform，特别是要提供平台自己的权限控制、审计、审批、成本控制、资源调度、multi-agent handoff 和 effect-level 恢复语义，那么 tool-call boundary 迟早要由平台拥有。此时 harness/sandbox 分离不再只是架构审美，而是让平台掌握 agent 副作用控制权的自然结果。

## Evidence

- [[wiki/sources/herohua-managed-agents-architecture]] 将 Anthropic 的 redesign 概括为三次 state externalization：harness leaves sandbox、session log leaves harness、credentials leave sandbox，并用 microkernel 和 capability-based OS lens 解释这些接口。
- [[wiki/sources/anthropic-scaling-managed-agents]] 明确说 harness 不再住在 container 里，而是像调用其它 tool 一样调用 container：`execute(name, input) -> string`。container died 时，harness catches the failure as a tool-call error 并传回 Claude；如果 Claude decides to retry，新 container 可以通过 `provision({resources})` reinitialized。
- [[wiki/sources/anthropic-scaling-managed-agents]] 还区分 harness failure recovery：session log 在 harness 外部，所以新 harness 可以 `wake(sessionId)`、`getSession(id)`、读取 event log 并 resume from the last event；运行过程中通过 `emitEvent(id, event)` 保持 durable record。
- [[wiki/sources/anthropic-scaling-managed-agents]] 的 `many brains` 部分把 TTFT 改善归因于 lazy sandbox provisioning：inference 可以在 orchestration 读取 session log 后开始，container 只在需要时由 brain 通过 tool call provision。它报告 p50 TTFT 下降约 60%，p95 下降超过 90%。
- [[wiki/sources/anthropic-scaling-managed-agents]] 的 `many hands` 部分说明 hand 可以是 container、phone、Pokémon emulator、custom tool 或 MCP server，并且 because no hand is coupled to any brain, brains can pass hands to one another。
- 本页还综合了 2026-05-25 对 Herohua 文章的讨论：session-level supervisor 与 effect-level platform 的差异、Claude Code hooks 的中间路线、bash 作为 stateful hand 的局限、以及 sandbox recovery 并不等同于 process/filesystem checkpoint。

## Follow-Ups

1. 补一页 concept note 区分 `session log`、`effect log`、`tool-call boundary`、`checkpoint/snapshot` 四种恢复和审计机制。
2. 进一步比较 Claude Code hooks、OpenCode permission rules、sidecar proxy、network egress policy 和 full harness/sandbox separation 的安全边界强度。
3. 如果要落地类似平台，优先设计不可绕过的 tool execution chokepoint，再决定是否必须自研完整 harness。
4. 如需更强档案完整性，下载 Anthropic 文中的图片资源到本地 source assets，并在 source note 中记录映射。

## Related Pages

- [[wiki/index]]
- [[wiki/sources/herohua-managed-agents-architecture]]
- [[wiki/sources/anthropic-scaling-managed-agents]]
- [Herohua: Managed Agents architecture](https://herohua.github.io/managed-agents-architecture)
- [Anthropic: Scaling Managed Agents](https://www.anthropic.com/engineering/managed-agents)
