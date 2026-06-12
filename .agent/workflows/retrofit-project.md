---
id: workflow-retrofit-project
status: active
---

# 工作流：retrofit-project（嵌入散乱/无范式的既有项目）

> 适用于：项目有代码但**没有结构化文档范式**（或文档散乱、无 ADR、无 spec 流程）。
> 如果项目**有旧范式 + 大量旧文档**，用 `retrofit-with-legacy.md`。
>
> **核心原则**：不破坏现有代码结构、不打断当前开发节奏。

## 何时触发

- 项目有代码但没有 `.agent/` / 没有结构化 spec 流程
- wizard Round 0 选了 [B]

## 5 阶段流程

| 阶段 | 名称 | 核心动作 | 必停 |
|---|---|---|---|
| 0 | Discovery | 摸清现状 | ✅ |
| 1 | 理解产品 | 填 philosophy + design-system + glossary + 追认 ADR | ✅ |
| 2 | Harden | 编译 shim + hooks + lefthook + verify-loading | ✅ |
| 3 | Project-customize | 裁剪 conventions + boundaries + skills | ✅ |
| 4 | First feature | 用新范式走一个完整 feature 验证 | — |

---

## 阶段 0: Discovery

### 0.1 确认骨架已就位

两种入口：

**A) 你已经手动把 AgentOS 模板复制进了旧项目**（最常见）：
- 确认 `.agent/` 目录存在
- 确认 `scripts/sync-shims.sh` 存在
- 确认 `AGENTS.md` 存在
- → 直接跳到 0.2

**B) 还没复制**：
- 复制 AgentOS 模板的 `.agent/`、`scripts/sync-shims.sh`、`lefthook.yml`、`AGENTS.md` 到 repo 根
- **不覆盖已有文件**（如果旧项目碰巧有同名文件）

> 备份逻辑：只在旧项目**已有** `AGENTS.md` 或 `.kiro/steering/` 时才备份。
> 如果旧项目是散乱 md 文档、没有这些文件，备份步骤自动跳过。

### 0.2 摸清现状

```
🔧 Calling sub-agent: explorer
📥 Input:
    question: |
      盘点项目现状：
      1. 技术栈（框架 / 语言 / 状态管理 / 测试工具 / 构建工具）
      2. 目录结构（有哪些顶层目录、组件在哪、API 在哪）
      3. 有没有散落的文档（README / docs/ / wiki 链接）
      4. 有没有现有的 .kiro/ 配置
      5. 测试基础设施（有没有 test runner / CI）
      6. UI 现状（用什么组件库 / 有没有 design token / Storybook）
    scope:
      paths: [".", "src/", "apps/", "packages/", "docs/", ".kiro/", "package.json", "tsconfig.json"]
    budget:
      max_files_read: 50
📤 Output: {结构化清单}
```

### 0.3 产出报告

写 `.agent/sessions/{ulid}/retrofit-report.md`：

- 技术栈摘要
- 目录结构 vs AgentOS 默认 boundaries 的差异
- 散落文档清单
- 隐含决策（从代码推断的选型）
- 建议追认的 ADR 清单

✅ 输出报告 → 等用户确认 → 停。

---

## 阶段 1: 理解产品

### 1.1 填 philosophy（跟用户对话，不从代码推）

- 定位一句话
- 3–5 个用户痛点
- 5–7 条判断式原则
- 3–5 个反模式

写入 `.agent/core/philosophy.md`。

### 1.2 填 design-system（从现状逆向 + 用户确认）

```
🔧 Calling sub-agent: explorer
📥 Input:
    question: "UI 规范现状：组件库 / token / 颜色 / 间距 / 字体 / 断点"
    scope: { paths: ["src/", "styles/", "theme/", "tailwind.config.*"] }
📤 Output: {UI 现状}
```

基于发现填 `.agent/core/design-system.md`（DS-1 到 DS-8）。

### 1.3 填 glossary

从代码命名 + 用户对话提取 ≥ 3 个领域术语。

### 1.4 追认 ADR

把"已经发生的"决策写成 ADR：

- `ratified-retroactively: true`
- 至少 ADR-0001（Foundation：栈 + 分层）
- 可选：ADR-0002（前端 stack）、ADR-0003（测试策略）

### 1.5 填 entities + concept-map（可选）

如果项目有明显的领域实体 → 填 `domain/entities.md`。
纯工具类项目可以 deferred。

如果 entities 已写：
- 基于 `domain/entities.md` 生成 `domain/concept-map.mmd`（Mermaid erDiagram）
- 只画实体 + 关系 + 基数，保持 < 20 节点
- entities 被 deferred → concept-map 一并 defer

✅ 输出所有产物 → 等用户确认 → 停。

---

## 阶段 2: Harden（让范式真正生效）

### 2.1 编译 shim

```bash
chmod +x scripts/sync-shims.sh
bash scripts/sync-shims.sh
```

### 2.2 注册 hooks

确认 `.kiro/hooks/` 下有 5 个 hook：

- `auto-sync-shims.kiro.hook`
- `pre-task-context-check.kiro.hook`
- `post-task-verify-and-sync.kiro.hook`
- `post-merge-sync-map.kiro.hook`
- `post-adr-impact.kiro.hook`

> [!NOTE]
> **Antigravity 替代**：Antigravity 没有原生 Hook 系统。以上 5 个 hook 由「Antigravity 软 Hook 协议」
> 替代（见 `AGENTS.md` 硬性规则段）：agent 在相应时机主动执行检查，`lefthook` 在 commit 时兜底。
> Stage 2.1 的 `sync-shims.sh` 应改用 `python scripts/sync-shims.py`（沙箱规避）。

### 2.3 安装 lefthook

```bash
npx lefthook install  # 或 brew install lefthook && lefthook install
```

### 2.4 注册 skills

确认 `.kiro/skills/` 下有 4 个子目录（sync-shims 应该已生成）。

### 2.5 验证加载（Gate）

跑 `.agent/workflows/verify-loading.md`——必须 `Loading: PASS`。

不通过 → 排查 → 修复 → 重新验证。

✅ verify-loading PASS → 停。

---

## 阶段 3: Project-customize

### 3.1 裁剪 conventions.md

- 分层表用真实目录名
- 测试约定用实际框架
- commit 约定：引入 conventional commits（如果没有）

### 3.2 裁剪 boundaries.md

- import 图用真实目录名
- 如果项目没有分层 → boundaries 写"当前无分层，新代码按 X 规则"
- lint 设 `warn`（既有违规不阻断）

### 3.3 裁剪 skills

- `frontend-patterns.md`：真实目录 + 真实状态库
- `design-tokens.md`：对齐实际 token 结构
- `state-machines.md`：实际库名
- `pbt-cookbook.md`：实际框架（如果没有 PBT → 标"待引入"）

### 3.4 重新编译

```bash
bash scripts/sync-shims.sh
```

✅ 输出裁剪结果 → 停。

---

## 阶段 4: First feature

用新范式走一个完整 feature（`start-feature` workflow）：

- Pre-spec → Kiro spec → Post-spec

验证点：
- [ ] agent 引用了 P{n}
- [ ] agent 遵守了 boundaries
- [ ] agent 调了 sub-agent（可见 🔧）
- [ ] agent 引用了 DS-{N}
- [ ] executor 跑测试成功
- [ ] verify-loading 仍然 PASS

全部通过 → tag `epoch-retrofit-1`。

收尾步骤：
- 调 `regenerate-map.md` 做**首次 map 生成**（至少生成 `architecture.md` + `adr-timeline.md`）
- 提示用户：**「请阅读 `.agent/core/dialog-rules.md`——它教你如何与 agent 高效对话，是发挥范式效力的关键」**

---

## 完成判定

- verify-loading PASS
- 至少一个 feature 端到端跑通
- git blame 未被破坏
- 新 `.kiro/steering/` 含 AgentOS 编译产物（Kiro），或 `.antigravity/AGENTS.md` 含编译产物（Antigravity）

## 与 retrofit-with-legacy 的边界

| 情况 | 用哪个 |
|---|---|
| 没文档 / 文档散乱 / 无结构化范式 | **本 workflow** |
| 有旧范式 + 大量旧文档（specs / RFCs / 旧 ADR） | `retrofit-with-legacy.md` |

## 反模式

- 跳过 philosophy 直接干——没有判断器，ADR 和 flow 都失去意义
- 跳过 verify-loading——嵌入完成但 agent 可能什么都没读到
- 跳过 design-system——前端任务没有视觉约束
- 跳过 skills 裁剪——agent 引用不存在的目录
- boundaries 直接 error——既有代码全红，团队拒绝接入

## Antigravity 适配说明

- **Stage 2.1**：用 `python scripts/sync-shims.py` 替代 `bash scripts/sync-shims.sh`。
- **Stage 2.2**：Kiro hook 文件不适用，由 `AGENTS.md` 中的「Antigravity 软 Hook 协议」替代。
- **Stage 2.4**：确认 `.antigravity/AGENTS.md` 存在且行数在 600–800 区间。
- **Stage 4.1**：`start-feature` 将走 4B 路径（Antigravity Planning Mode）。
- **收尾**：handoff 后执行 `bash scripts/antigravity-sync.sh backup`。
