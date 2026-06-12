# AgentOS Template

一份**跨 IDE 通用**的 agentic coding 项目骨架。同一份骨架在 Kiro、Cursor、
Claude Code、Windsurf、Antigravity、Trae，以及任何读 `AGENTS.md` 的工具下
都工作。

> 真理只放在 `.agent/`。各 IDE 的目录（`.kiro/`、`.cursor/` …）只是薄壳，
> 通过引用拉同一份内容。**换 IDE 不丢知识**。

## 这套骨架给你什么

- **五层洋葱**：philosophy → domain → architecture → contracts → impl，
  每层各有家。
- **前端"决策有家"**：在 ADR 之外引入 `flows/`，承载页面 / 组件 / 交互 /
  跳转的流程级决策——人类讨论前端的自然介质。
- **单主 agent + 6 个 sub-agent**（explorer、verifier、visual-reviewer、
  impact-analyzer、doc-syncer、scribe）按动作类型，不按角色。
- **Workflows**：bootstrap、retrofit、start-feature、architecture-change、
  write-handoff、resume-session、regenerate-map、drift-check。
- **逻辑时间优先**的项目记忆：ADR 编号、ULID session、epoch tag、commit hash。
  wall-clock 仅供审计与漂移检测。
- **自动生成的项目地图**在 `.agent/map/`，从代码 + 契约派生，不手编辑。
- **跨 IDE shim** 现成：Kiro steering+hooks、Cursor rules、Claude Code、
  Windsurf、Trae。
- **Git hook 兜底**（`lefthook.yml`）：在没有 IDE-side hook 的环境下保证
  确定性校验（边界、ID 唯一性、commit 格式）。

## 开始用

### 0→1 新项目

1. 复制本目录作为新项目根
2. 在你的 IDE 里打开
3. 在 agent chat 里粘：

   ```
   跑 .agent/workflows/bootstrap-project.md。
   接下来我会提供产品上下文。
   ```

4. 跟着 agent 完成 philosophy / 初始 ADR / 首份 spec
5. 启动首个 vertical-slice

### 嵌入既有项目

复制 `AGENTS.md` + `.agent/` + 你用的 IDE shim 目录到既有 repo，再粘：

```
跑 .agent/workflows/retrofit-project.md。
```

retrofit 走"先观察、再追认、再改造"三阶段，不打断当前节奏。详见
`.agent/workflows/retrofit-project.md`。

## 目录速览

```
AGENTS.md                        通用 agent 入口（每个 IDE 都读）
.agent/                          ◆ 真理源（IDE 无关）
  core/                          稳定层：philosophy / glossary / conventions / boundaries
  domain/                        实体、概念图
  adr/                           架构决策（append-only）
  flows/                         前端流程（页面 / 组件 / 交互 / 跳转）
  map/                           自动生成的项目视图
  sessions/                      跨窗口续接 handoff
  skills/                        按需加载的知识包
  workflows/                     可复用的 agent prompt
  sub-agents/                    Sub-agent 定义
  _meta.md                       本结构的 meta 说明
  _LIMITATIONS.md                诚实的局限清单
shared/                          跨域契约（tokens、schemas、events、api-contracts）
.kiro/ .cursor/ .claude/ ...     各 IDE 薄壳
lefthook.yml                     Git hook 兜底（跨 IDE）
```

## 接着读

- [`AGENTS.md`](./AGENTS.md)——agent 入口
- [`.agent/_meta.md`](./.agent/_meta.md)——这套结构是怎么工作的
- [`.agent/_LIMITATIONS.md`](./.agent/_LIMITATIONS.md)——它做不到什么（先读这个）
- [`.agent/workflows/bootstrap-project.md`](./.agent/workflows/bootstrap-project.md)——0→1 第一次跑
- [`.agent/workflows/retrofit-project.md`](./.agent/workflows/retrofit-project.md)——既有项目嵌入
