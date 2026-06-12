---
id: triggers
status: active
audience: human (maintainers); 资深 agent 在 prune/audit 时
purpose: 列清楚 .agent/ 下每份文档何时被读 / 何时被写 / 由谁触发，避免文档"漂着无人问津"
last-confirmed: null
---

# 文档触发机制总览（哪个文档何时被读 / 写）

> 这份是给**人**看的——回答"这些文档是真的会被 agent 用到，还是漂在那里没人看？"
>
> 三个加载层级：
> - **always-on**：每次会话开始就被注入到主 agent 上下文，常驻
> - **on-demand**：触某个事件 / 用户某句话才被读 / 写
> - **passive-archive**：仅在 audit / drift-check / 历史追溯时被访问
>
> 每个文件都明确归到一类，否则文档堆积就是范式失败的开始。

## 加载机制（重要：实测情况）

**Kiro（已验证 2026.5）**：

- IDE 自动加载 `AGENTS.md`（完整内容）
- IDE 加载 `.kiro/steering/*.md`（front matter 标 `inclusion: always` 的文件）
- **steering 文件内的 `#[[file:...]]` 引用不会被递归解析**——只是纯文本
- 因此 `.agent/core/*` 这些必须通过 `scripts/sync-shims.sh` **内联编译**到
  `.kiro/steering/0X-*.md` 才进 prompt

**Cursor**：

- IDE 加载 `.cursor/rules/*.mdc` 中标 `alwaysApply: true` 的文件
- `.mdc` 内的 `@filename` 引用语法行为不稳定——同样用编译路径

**Claude Code**：

- IDE 加载 `CLAUDE.md`（项目根或 `.claude/CLAUDE.md`）
- `@` 引用支持但跨目录行为不一致——稳妥的做法是单文件全内联

**Antigravity**：

- IDE 通过 `user_rules` 机制注入根目录 `AGENTS.md` 的完整内容
- `.antigravity/AGENTS.md` 是完整编译产物（同 `.kiro/steering/` 的节点角色）
- 根目录 `AGENTS.md` 必须与 `.antigravity/AGENTS.md` 保持一致
- **行数甘点区**：600–800 行。超过 800 行可能被 IDE 截断，低于 600 行说明内容不足
- 无原生 Hook 系统，用「Antigravity 软 Hook 协议」替代（见 AGENTS.md 硬性规则段）

**结论：所有 IDE 上 SSOT 都通过编译时展开（`scripts/sync-shims.sh`）保证**，
不依赖 IDE 的引用机制。

## 文件级清单

### Core 层（always-on，常驻）

| 真理源（编辑这个） | 编译产物（agent 实际读到） | 触发者 |
|---|---|---|
| `AGENTS.md` | 自身 | IDE 直读 |
| `.agent/skills/agent-discipline.md` | `.kiro/steering/00-discipline.md`（编译） | sync-shims.sh |
| `.agent/core/philosophy.md` | `.kiro/steering/01-philosophy.md`（编译） | sync-shims.sh |
| `.agent/core/conventions.md` | `.kiro/steering/02-conventions.md`（编译） | sync-shims.sh |
| `.agent/core/boundaries.md` | `.kiro/steering/03-boundaries.md`（编译） | sync-shims.sh |
| `.agent/core/glossary.md` | `.kiro/steering/04-glossary.md`（编译） | sync-shims.sh |
| 各 `_index.md`（adr/flows/sub-agents/workflows/skills） | `.kiro/steering/05-indexes.md`（编译合并） | sync-shims.sh |
| `.agent/core/dialog-rules.md` | **不进 agent**——给人看 | 人手动读 |

> Cursor 路径：同样 `.cursor/rules/00-discipline.mdc` ... `05-indexes.mdc`
> Claude Code 路径：所有内容编译进单一 `.claude/CLAUDE.md`

### Domain 层（按需）

| 文件 | 何时读 | 何时写 |
|---|---|---|
| `.agent/domain/entities.md` | 数据 / API 设计时 | 新实体、生命周期变化 |
| `.agent/domain/concept-map.mmd` | 同上 | 同上 |

### Decision 层（事件触发）

| 文件 | 何时读 | 何时写 | 触发 |
|---|---|---|---|
| `.agent/adr/_index.md` | 每次会话（编译进 05-indexes） | 新 ADR、状态变更 | sync-shims.sh + post-adr hook |
| `.agent/adr/{NNNN}-*.md` | 涉及该决策时 | architecture-change、retrofit 追认 | impact-analyzer 自动回填 Impact 段 |
| `.agent/flows/_index.md` | 每次会话（编译进 05-indexes） | 新 flow、状态变更 | sync-shims.sh |
| `.agent/flows/{NNN}-*.md` | 实施该 flow 时 | 流程改动时 | start-feature step 4 |

### Map 层（auto-generated，被动）

| 文件 | 何时读 | 何时写 | 触发 |
|---|---|---|---|
| `.agent/map/architecture.md` | 会话启动 + 接到陌生模块时 | source-hash 失配后 | regenerate-map workflow / hook |
| `.agent/map/api-surface.md` | API 设计时 | 同上 | 同上 |
| `.agent/map/component-tree.md` | UI 任务时 | 同上 | 同上 |
| `.agent/map/route-map.md` | 路由变更时 | 同上 | 同上 |
| `.agent/map/data-flow.svg` | event / state 设计时 | 同上 | 同上 |
| `.agent/map/adr-timeline.md` | retrofit / drift-check 时 | ADR 增删改后 | post-adr hook |

### Session 层（短期）

| 文件 | 何时读 | 何时写 | 触发 |
|---|---|---|---|
| `.agent/sessions/{ulid}/handoff.md` | resume-session 时 | 上下文 70% / 用户暂停 / 阶段结束 | write-handoff workflow |
| `.agent/sessions/_archive/*` | 极少（追溯） | prune 完成后归档 | prune workflow |

### Skills 层（按需 + 一个 always-on）

| 文件 | 何时读 | 何时写 |
|---|---|---|
| `.agent/skills/agent-discipline.md` | **编译进 always-on shim** | 行为护栏更新时 |
| `.agent/skills/pbt-cookbook.md` | 写 PBT 时 | 经验沉淀 |
| `.agent/skills/frontend-patterns.md` | UI 任务时 | 经验沉淀 |
| `.agent/skills/state-machines.md` | 复杂交互时 | 经验沉淀 |
| `.agent/skills/design-tokens.md` | token 改动时 | token 体系演进 |

### Workflows 层（被调用时）

| 文件 | 何时读 | 触发 |
|---|---|---|
| `.agent/workflows/wizard.md` | 首次接入 | 用户/agent 主动调 |
| `.agent/workflows/verify-loading.md` | 切 IDE / 怀疑没生效 | 用户主动 |
| `.agent/workflows/start-feature.md` | 用户提"做 X"时 | 用户/agent |
| `.agent/workflows/architecture-change.md` | 用户提"改 Y 做法" | 用户/agent |
| `.agent/workflows/write-handoff.md` | 上下文将满 / 用户暂停 | 70% 触发 / 用户 / 阶段末 |
| `.agent/workflows/resume-session.md` | 新窗口 + 未完任务 | 用户主动 |
| `.agent/workflows/regenerate-map.md` | source 变更后 | post-merge hook / 用户 |
| `.agent/workflows/drift-check.md` | epoch 末尾 | 人主动 |
| `.agent/workflows/prune.md` | 触阈值 | 阈值 / epoch 末 |
| `.agent/workflows/bootstrap-project.md` | 0→1 启动 | wizard or 用户 |
| `.agent/workflows/retrofit-project.md` | 既有项目嵌入 | wizard or 用户 |

### Sub-agents 层（被主 agent 调用时）

| 文件 | 何时读 | 触发 |
|---|---|---|
| `.agent/sub-agents/explorer.md` | 调 explorer 前 | start-feature step 3 / retrofit |
| `.agent/sub-agents/verifier.md` | 调 verifier 前 | start-feature step 8 / hook |
| `.agent/sub-agents/visual-reviewer.md` | 调 visual-reviewer 前 | UI 任务 step 8 |
| `.agent/sub-agents/impact-analyzer.md` | 调 impact-analyzer 前 | architecture-change / post-adr hook |
| `.agent/sub-agents/doc-syncer.md` | 调 doc-syncer 前 | regenerate-map / hooks |
| `.agent/sub-agents/scribe.md` | 调 scribe 前 | write-handoff |

### Meta 层（基本不进 agent 上下文）

| 文件 | 何时读 |
|---|---|
| `.agent/_README.md` | 第一次接触范式时（人） |
| `.agent/_INDEX.md` | 找文档时（人 + agent） |
| `.agent/_meta.md` | 想理解结构时（人 + 资深 agent） |
| `.agent/_LIMITATIONS.md` | 决定要不要用范式时（人） |
| `.agent/_HARNESS.md` | 想了解范式跟前沿对齐情况时（人 + 资深 agent） |
| `.agent/_TRIGGERS.md`（本文件） | 想知道哪个文件何时触发时（人） |
| `.agent/_AUDIT.md` | epoch 末尾 audit 时（维护者） |

---

## 编译流程图

```
人编辑（真理源）              编译（脚本）                 IDE 加载（Agent prompt）
─────────────────             ─────────────                ────────────────────────
.agent/core/philosophy.md  ──┐
.agent/core/conventions.md ──┤
.agent/core/boundaries.md  ──┤
.agent/core/glossary.md    ──┼──> sync-shims.sh ──>  .kiro/steering/0X-*.md
.agent/skills/agent-       ──┤                       .cursor/rules/0X-*.mdc       ──> Agent
  discipline.md                                      .claude/CLAUDE.md
各 _index.md               ──┘                       .antigravity/AGENTS.md

AGENTS.md                  ───────（直接）─────>  Agent

lefthook (pre-commit) ─> sync-shims.sh --check ─> 漂移则阻止 commit
```

## 触发关系图

```
                    会话启动
                       ↓
     [IDE 加载 always-on 编译 shim]
     AGENTS + 0X-discipline + 0X-philosophy + 0X-conventions + 0X-boundaries + 0X-glossary + 0X-indexes
                       ↓
                 用户提需求
                       ↓
        ┌──────────────┼──────────────┬─────────────┐
        ↓              ↓              ↓             ↓
   首次接入        新功能           架构改动     续接旧任务
   wizard      start-feature     architecture   resume-session
        ↓              ↓              ↓             ↓
   bootstrap/    explorer/      impact-analyzer  读 handoff
   retrofit      verifier/      → ADR 起草 →
                visual-reviewer  migration
                       ↓
                 中途任意时刻：上下文 70% 触发 write-handoff
                       ↓
                 完成时刻：post-task hook → verifier + regenerate-map
                       ↓
              事件后台：post-merge hook → regenerate-map
                       ↓
                 epoch 末：drift-check + prune（人主动）
                       ↓
              .agent/ 改动：lefthook → sync-shims.sh → shim 重编译
```

## 哪些文件"会被忽略"的风险（实测后更新）

| 文件 | 风险 | 原因 | 减害 |
|---|---|---|---|
| `core/dialog-rules.md` | **极高** | 给人看的，不进 agent | wizard 末尾强制看一次 |
| `_LIMITATIONS.md` / `_HARNESS.md` / `_TRIGGERS.md` | 高 | meta 文档，agent 不主动读 | onboarding 时给链接 |
| 编译产物未刷新 | **中**（已通过 lefthook 治理） | `.agent/` 改了但忘了跑 sync-shims.sh | lefthook `shim-in-sync` 阻止 commit |
| 直接编辑 `.kiro/steering/0X-*.md` | **中**（已通过 lefthook 治理） | 人误以为 shim 是编辑入口 | lefthook `no-edit-generated-shims` 拦截；文件头 `AUTO-GENERATED` 标记 |
| `domain/entities.md` | 中 | 不在 always-on，按需 | workflow step 内强制提示读 |
| `flows/{NNN}-*.md` | 中 | 涉及才读 | 通过 `_index.md` always-on，让 agent 知道存在 |
| `adr/{NNNN}-*.md` | 中 | 涉及才读 | 同上，代码注释引用注释自然带回 |
| `map/*` | 低（hook 工作时） | hook 不工作时变陈旧 | source-hash 自动检测 |
| 任意 skill | 低 | relevance 触发 | `_index.md` always-on，agent 按任务自决加载 |

## 维护成本预估（单人项目）

| 文档类型 | 写一次 | 维护频次 | 谁写 |
|---|---|---|---|
| AGENTS.md / 各 IDE shim | 编译产生 | 改 `.agent/` 时自动 | sync-shims.sh |
| core/* | bootstrap + drift-check | 季度级 | 人 + agent |
| domain/* | bootstrap + 实体演进 | 月度级 | agent 起草人审 |
| adr/* | 每次重要决策 | 看决策频次 | agent 起草人审 |
| flow/* | 每次前端流程改动 | 看产品迭代 | agent 起草人审 |
| map/* | 完全自动 | source 变更后 | agent 自动 |
| sessions/* | 每次会话 | 每天 | agent 自动 |
| skills/* | 经验沉淀 | 不定 | 人 / 资深用户 |
| workflows/* / sub-agents/* | 模板自带 | 范式升级 | 模板维护者 |

**单人项目典型分布**：60% 时间 agent 自动写（map / sessions），30% agent 起草
人确认（ADR / flow），10% 人主笔（philosophy / glossary 关键术语）。
