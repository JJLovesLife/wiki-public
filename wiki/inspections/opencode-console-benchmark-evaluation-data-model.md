---
type: inspection
title: OpenCode Console Benchmark Evaluation Data Model
repo: opencode
repo_commit: f9ba23ab62eabea5031495247e5eb5e2d823fea3
inspected_on: 2026-06-02
scope_paths:
  - packages/console/app/src/routes/bench/
  - packages/console/core/src/schema/benchmark.sql.ts
---

# OpenCode Console Benchmark Evaluation Data Model

## Question

OpenCode console 的 benchmark/evaluation page 隐含了什么 data model？特别是 `Benchmark`、`Task`、`Run`、`model`、`agent`、source commits 和 judge results 之间是什么关系？

## Answer

Console benchmark model 目前是 loose JSON-backed model，不是 normalized relational evaluation schema。Database 里每个 benchmark submission 对应 `benchmark` table 的一行，top-level 存 `model`、`agent` 和一个 `result` mediumtext JSON string。UI 再把 `result` parse 成 route file 里局部声明的 TypeScript interfaces。

最清晰的 mental model 是：

```text
Benchmark submission
  = 一次 submitted evaluation result，通常对应一个 model + agent pair

Task
  = 一个 benchmark case
  = repo + base commit + expected/reference commit + prompts
  = 对 repeated runs 的 aggregate

Run
  = evaluated agent 在同一个 task 上的一次 attempt/session
  = 有 score、usage、duration 和 grading details

ScoreDetail
  = run 内的一个 grading criterion

Judge
  = 某个 grader 对一个 criterion 的 judgement，包含 score 和 rationale
```

UI consume 的 `result` JSON shape 大致是：

```ts
interface BenchmarkResult {
  averageScore: number
  tasks: Task[]
}

interface Task {
  averageScore: number
  averageDuration?: number
  averageUsage?: {
    input: number
    output: number
    cost: number
  }
  model?: string
  agent?: string
  summary?: string
  runs?: Run[]
  task: {
    id: string
    source: {
      repo: string
      from: string
      to: string
    }
    prompts?: {
      commit: string
      prompt: string
    }[]
  }
}

interface Run {
  task: string
  model: string
  agent: string
  score: {
    final: number
    base: number
    penalty: number
  }
  scoreDetails: ScoreDetail[]
  usage?: {
    input: number
    output: number
    cost: number
  }
  duration?: number
}

interface ScoreDetail {
  criterion: string
  weight: number
  average: number
  variance?: number
  judges?: Judge[]
}

interface Judge {
  score: number
  rationale: string
  judge: string
}
```

`Task.task.source.from` 最好理解成 agent 开始工作的 starting/base commit。`Task.task.source.to` 最好理解成 expected/reference final commit，而不是 agent actual output。UI 只是把二者都 link 到 GitHub commit，没有展示任何独立的 agent-produced commit artifact。

`Task.runs[]` 最一致的解释是 same task 的 repeated attempts，而不是一个 commit range 下的 multiple sub-tasks。证据是 detail route 用 `benchmarkId:taskId` 定位；`Task.averageScore` 和相关 averages 都是 task-level summary；runs 只显示成 `Run 1`、`Run 2`；而 `Run` 没有 `promptId`、`subtaskId` 或 per-run source commits 这类可以区分 independent child tasks 的字段。

`model` 和 `agent` 在三层重复出现：database row、task result、run。当前 code 不检查它们是否一致。如果 diverge，list page 和 detail page 可能展示 conflicting values。从 UI design 看，intended shape 更接近 single model/agent benchmark submission，所以 lower-level copies 更像 denormalized snapshots，而不是 independent routing keys。

## Trace

Storage table 定义为一行 `benchmark`，包含 IDs、timestamps、`model`、`agent` 和 `result`：

```ts
export const BenchmarkTable = mysqlTable(
  "benchmark",
  {
    id: id(),
    ...timestamps,
    model: varchar("model", { length: 64 }).notNull(),
    agent: varchar("agent", { length: 64 }).notNull(),
    result: mediumtext("result").notNull(),
  },
  (table) => [primaryKey({ columns: [table.id] }), index("time_created").on(table.timeCreated)],
)
```

Submission endpoint 接受 `{ model, agent, result }`，只 validate 三个 field 存在，然后把 JSON result string 原样 insert。Nested evaluation data 没有 runtime schema validation。

Benchmark list page parse `row.result`，读取 `averageScore`，并按 `parsed.tasks[].task.id` 把 `parsed.tasks[].averageScore` flatten 成 table columns。这让 `Task.task.id` 成为 visible benchmark case identifier。

Task detail page parse 同一个 `result` JSON，并用 `parsed.tasks.find((t) => t.task.id === taskId)` 选择单个 task。然后 render：

- Detail header 里的 `task.agent` 和 `task.model`。
- 作为 GitHub links 的 `task.task.source.repo`、`from` 和 `to`。
- Score summary 之前合并展示的全部 `task.task.prompts[]`。
- Task-level duration、score 和 cost averages。
- 编号展示的 `task.runs[]`，包含 score、usage、duration、score details、judges 和 judge rationale。

UI 把 run score 显示成 `final (base - penalty)`，暗示 `base` 是 criterion-derived score，`penalty` 是 additional deduction。这里 inspected code 不包含 scoring producer 或 formula。

## Evidence

- `opencode` snapshot: `f9ba23ab62eabea5031495247e5eb5e2d823fea3`.
- `packages/console/core/src/schema/benchmark.sql.ts` 定义 `benchmark` table，包含 `model`、`agent` 和 `result` mediumtext。
- `packages/console/app/src/routes/bench/submission.ts` 接受 `model`、`agent` 和 `result`，然后在没有 nested result validation 的情况下 insert row。
- `packages/console/app/src/routes/bench/index.tsx` 定义 minimal `BenchmarkResult`，parse `row.result`，并用 `tasks[].task.id` 加 `tasks[].averageScore` 生成 list table。
- `packages/console/app/src/routes/bench/[id].tsx` 定义更完整的 task/run/judge interfaces，并 render source commits、prompts、averages、runs、criteria、judges 和 raw JSON。
- Evidence maturity: console consumer data shape 是 inspection-backed；`from`、`to` 和 repeated runs 的 semantic interpretation 部分是 conversation-derived，因为 inspected scope 里没有找到 result producer。

## Uncertainty

- Inspected code 里没有 identify `result` JSON producer。所以 exact scoring formula，以及 lower-level `model`/`agent` fields 是 intentional snapshots 还是 accidental duplication，都还不确定。
- `Task.task.source.to` 被 infer 为 reference/expected final commit，但 inspected UI code 只能证明它被 display 成 commit link。
- `Task.runs[]` 被 infer 为 same task 的 repeated attempts。当前 shape 强烈支持这个解释，但没有 explicit `runKind`、`attemptNumber` 或 `sessionId` field 来把 semantics 固化。
- `Task.task.prompts[]` 可能表示一个 task 的 multi-commit 或 multi-part instructions。UI 不把 prompts link 到 individual runs 或 child cases。

## Related Pages

- [[wiki/index]]
- [[wiki/projects/opencode]]
