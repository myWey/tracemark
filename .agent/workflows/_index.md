---
id: workflows-index
status: active
---

# Workflows 索引

> 主 agent 可执行的可复用 prompt。触发任意 workflow 的方式：
> *「跑工作流 `.agent/workflows/{name}.md`」*。

| Workflow | 用途 | 典型触发 |
|---|---|---|
| [`wizard`](./wizard.md) | 自动引导落地范式（路径自动判定） | 首次接入 AgentOS |
| [`verify-loading`](./verify-loading.md) | 验证 IDE 真的加载了 `.agent/`（光面板显示不算数） | 切换 IDE / 怀疑没生效 |
| [`bootstrap-project`](./bootstrap-project.md) | 0→1 项目初始化 | 已知是空 repo |
| [`retrofit-project`](./retrofit-project.md) | 把 AgentOS 嵌入既有项目（散乱或无范式） | 既有项目首次接入 |
| [`retrofit-with-legacy`](./retrofit-with-legacy.md) | 嵌入**有旧范式 + 大量旧文档**的既有项目 | 旧 specs / RFCs / 旧 ADR 大量存在 |
| [`start-feature`](./start-feature.md) | 规划+落地一个 feature；UI 任务伴随 flow | "做个 X" |
| [`architecture-change`](./architecture-change.md) | 走 ADR + impact-analyzer + migration | "改 Y 的做法" |
| [`write-handoff`](./write-handoff.md) | 长任务接近 70% 上下文时存档 | 上下文将满 |
| [`resume-session`](./resume-session.md) | 新窗口冷启动接续 | 新窗口、未完任务 |
| [`regenerate-map`](./regenerate-map.md) | 刷新 `.agent/map/` 派生视图 | source-hash 失配 |
| [`drift-check`](./drift-check.md) | 验证哲学/ADR/flow 仍贴合现实 | epoch 末尾 |
| [`prune`](./prune.md) | 裁剪 `.agent/` 防止文档膨胀 | 触阈值 / epoch 末尾 |

## 自动触发对应表（IDE → workflow）

| IDE 事件 | Hook 文件 | 触发的 workflow |
|---|---|---|
| 任务开始前（Kiro spec task） | `.kiro/hooks/pre-task-context-check.kiro.hook` | 仅必读检查 + 必要时 `regenerate-map` |
| 任务完成后 | `.kiro/hooks/post-task-verify-and-sync.kiro.hook` | 调 `verifier` + `regenerate-map`，必要时 `write-handoff` |
| 代码/契约变更 | `.kiro/hooks/post-merge-sync-map.kiro.hook` | `regenerate-map` |
| 新建/编辑 ADR | `.kiro/hooks/post-adr-impact.kiro.hook` | 调 `impact-analyzer`，回填 ADR Impact 段 |
| Git commit-msg | `lefthook.yml` | 校验是否引用 ADR / flow / P{n} |
| Git pre-push | `lefthook.yml` | 跑 boundary lint + ID 唯一性 |

> **跨 IDE 提示**：Cursor / Trae / Antigravity 当前没有原生的 IDE-side hook。
> 这些环境下**git hook（`lefthook.yml`）是兜底**。详见 `.agent/_LIMITATIONS.md`
> 第 1 项。

## 触发关系图

```
首次接入 → wizard → bootstrap | retrofit
新功能 → start-feature → 调 explorer / verifier / visual-reviewer
架构变更 → architecture-change → 调 impact-analyzer
上下文将满 → write-handoff → 调 scribe
新窗口 → resume-session
源变更 → regenerate-map → 调 doc-syncer
epoch 末 → drift-check + prune
```

## 约定

- 每个 workflow 文件结构一致：Purpose / When / Inputs / Steps / Outputs /
  Done-when / Anti-patterns。
- Steps 是有编号、原子化的。主 agent 默认顺序执行。
- 一个 workflow 可以调用 sub-agent 与其它 workflow。
- workflow 文件**人机共读用中文**；其中 sub-agent 的 I/O schema 段落保留英文。
