---
id: workflow-retrofit-with-legacy
status: active
---

# 工作流：retrofit-with-legacy（嵌入有旧范式的既有项目）

> **核心原则**：不 mv 文件、不删旧文档、不破坏 git blame、不打断当前开发节奏。
> AgentOS 是"加层"而非"换"。

## 何时触发

- 项目已有 specs / RFCs / design docs / 旧 steering / 旧 AGENTS.md
- 项目已用某种结构化 spec 流程（旧版 Kiro / Spec-Kit / BMAD / 自创）
- wizard Round 0 选了 [C]

## 6 阶段流程

| 阶段 | 名称 | 核心动作 | 必停 |
|---|---|---|---|
| 0 | Discovery | 盘点旧文档 + 摸清现状 | ✅ |
| 1 | Classify | 跟用户决策每份旧文档的处置 | ✅ |
| 2 | Bridge + 理解产品 | 建 bridge + 填 philosophy + design-system | ✅ |
| 3 | Harden | 编译 shim + 注册 hooks + 安装 lefthook + verify-loading | ✅ |
| 4 | Project-customize | 裁剪 skills + conventions + boundaries | ✅ |
| 5 | First feature | 用新范式走一个完整 feature 验证 | — |

---

## 阶段 0: Discovery（只读，不动一行业务代码）

### 0.1 备份旧范式文件（保护稳定结构）

**在做任何事之前**：

```bash
# 如果旧项目已有这些，先备份
mkdir -p .agent/_backup
[ -f AGENTS.md ] && cp AGENTS.md .agent/_backup/AGENTS.md.bak
[ -d .kiro/steering ] && cp -r .kiro/steering .agent/_backup/kiro-steering-bak/
[ -d .kiro/specs ] && cp -r .kiro/specs .agent/_backup/kiro-specs-bak/
```

**绝不覆盖**——后续是 merge，不是 replace。

### 0.2 注入骨架

复制 AgentOS 模板的以下到 repo 根（**不覆盖已有文件**）：

- `.agent/` 全部（如果不存在）
- `scripts/sync-shims.sh`（如果不存在）
- `lefthook.yml`（如果不存在）

**已有的 `AGENTS.md`**：不覆盖，后续 merge。
**已有的 `.kiro/steering/`**：不覆盖，后续在阶段 3 处理。
**已有的 `.kiro/specs/`**：完全保留，不动。

### 0.3 摸清现状

调 `explorer` sub-agent：

```
🔧 Calling sub-agent: explorer
📥 Input:
    question: |
      盘点这个项目的文档资产和技术现状：
      1. 旧范式文档（specs / RFCs / design docs / ADR / wiki）
      2. 现有 .kiro/ 配置（steering / hooks / specs）
      3. 技术栈（框架 / 语言 / 状态管理 / 测试工具）
      4. 目录结构（apps / packages / shared / lib / src）
      5. 现有 AGENTS.md 内容（如有）
    scope:
      paths: ["docs/", ".kiro/", ".specs/", "AGENTS.md", "package.json", "tsconfig.json", "src/", "apps/", "packages/"]
    budget:
      max_files_read: 50
📤 Output: {结构化清单}
```

### 0.4 产出 retrofit 报告

写 `.agent/sessions/{ulid}/retrofit-report.md`：

- 旧文档清单（路径 + 类型 + 状态猜测）
- 技术栈摘要
- 现有 `.kiro/` 配置摘要
- 现有 `AGENTS.md` 内容摘要
- 目录结构 vs AgentOS 默认 boundaries 的差异
- 建议的 bridge 清单

✅ 输出报告 → 等用户确认 → 停。

---

## 阶段 1: Classify（跟用户决策）

对每份旧文档（或同类批量）确认状态：

| 状态 | 含义 |
|---|---|
| `archived` | 纯历史，不再指导代码 |
| `active-bridged` | 仍在用，但会在 ADR/FLOW 里建 canonical 版本 |
| `active-orphan` | 仍在用，尚未迁出（临时权威，下个相关 PR 必须迁） |

**批量决策允许**（如"docs/rfcs/2022-* 全部 archived"），但 active 的必须逐个确认。

产出：
- `.agent/legacy/_index.md`（填表）
- `.agent/sessions/{ulid}/legacy-policy.md`（决策依据）

✅ 输出分类结果 → 等用户确认 → 停。

---

## 阶段 2: Bridge + 理解产品

### 2.1 建 bridge 文档

对 `active-bridged` 的每份旧文档：

- 用 `.agent/legacy/_template.md` 创建 bridge
- bridge 内容由 agent 起草、用户审
- 在原文档**末尾** append 注释（不改正文）：
  ```html
  <!-- AgentOS legacy: bridged-to .agent/legacy/{slug}.md -->
  ```

### 2.2 填 philosophy（不能跳过）

**从用户对话中**（不是从代码中）提取产品哲学：

- 定位一句话
- 3–5 个用户痛点
- 5–7 条判断式原则（P1…Pn）
- 3–5 个反模式

写入 `.agent/core/philosophy.md`。

### 2.3 填 design-system（从旧项目逆向）

调 `explorer` 扫描旧项目的 UI 现状：

```
🔧 Calling sub-agent: explorer
📥 Input:
    question: |
      这个项目的 UI 规范现状：
      1. 用了什么 UI 框架 / 组件库？
      2. 有没有 design token / CSS 变量 / theme 文件？
      3. 间距、颜色、字体的模式是什么？
      4. 有没有 Storybook？
      5. 响应式断点是什么？
    scope:
      paths: ["src/", "apps/", "packages/", "styles/", "theme/", "tailwind.config.*"]
    budget:
      max_files_read: 30
📤 Output: {UI 现状摘要}
```

基于发现 + 用户确认，填 `.agent/core/design-system.md`（DS-1 到 DS-8）。

### 2.4 填 glossary 初版

从代码命名 + 旧文档 + 用户对话提取 ≥ 3 个领域术语。

### 2.5 追认 ADR

按阶段 1 的分类，为关键决策写追认 ADR：

- `ratified-retroactively: true`
- Decision 段写"当前如何做"
- Consequences 段写"已观察到的正负后果"

### 2.6 填 entities + concept-map（可选）

如果项目有明显的领域实体 → 填 `domain/entities.md`。
纯工具类项目可以 deferred。

如果 entities 已写：
- 基于 `domain/entities.md` 生成 `domain/concept-map.mmd`（Mermaid erDiagram）
- 只画实体 + 关系 + 基数，保持 < 20 节点
- entities 被 deferred → concept-map 一并 defer

✅ 输出所有产物 → 等用户确认 → 停。

---

## 阶段 3: Harden（让范式真正生效）

> **这是最关键的阶段**——前面都是"写文档"，这里是"让 agent 真的读到"。

### 3.1 Merge AGENTS.md

如果旧项目已有 `AGENTS.md`：

- 读旧版内容
- 把旧版中**项目特有的规则**（不在 AgentOS 模板里的）提取出来
- 写入新 `AGENTS.md`（AgentOS 模板 + 旧版特有规则合并）
- 旧版移到 `.agent/_backup/AGENTS.md.bak`

如果没有旧 `AGENTS.md`：直接用 AgentOS 模板。

### 3.2 处理旧 .kiro/steering/

如果旧项目已有 `.kiro/steering/*.md`：

- 读每个旧 steering 文件
- 判断：是否跟 AgentOS 的 steering 冲突？
  - 不冲突（项目特有规则）→ **保留**，重命名为 `90-legacy-{name}.md`（排序在 AgentOS 之后）
  - 冲突（旧版的 philosophy / conventions）→ 移到 `.agent/_backup/`，用 AgentOS 版替代

### 3.3 编译 shim

```bash
chmod +x scripts/sync-shims.sh
bash scripts/sync-shims.sh
```

确认输出 `wrote .kiro/steering/00-discipline.md` 等。

### 3.4 注册 Kiro hooks

确认 `.kiro/hooks/` 下有这 5 个 hook：

- `auto-sync-shims.kiro.hook`
- `pre-task-context-check.kiro.hook`
- `post-task-verify-and-sync.kiro.hook`
- `post-merge-sync-map.kiro.hook`
- `post-adr-impact.kiro.hook`

如果旧项目已有 hooks → 保留，AgentOS hooks 追加（不覆盖）。

### 3.5 安装 lefthook

```bash
# 如果项目用 npm
npx lefthook install

# 如果项目用 brew
lefthook install
```

确认 `.git/hooks/` 下有 lefthook 生成的文件。

### 3.6 注册 Kiro skills

确认 `.kiro/skills/` 下有 4 个子目录（sync-shims 应该已生成）：

- `pbt-cookbook/SKILL.md`
- `frontend-patterns/SKILL.md`
- `state-machines/SKILL.md`
- `design-tokens/SKILL.md`

### 3.7 验证加载（Gate）

**这是阶段 3 的 gate——不通过不能进阶段 4。**

跑 `.agent/workflows/verify-loading.md`：

- 开新对话窗口
- 粘 6 道题
- 必须 `Loading: PASS`

如果 PARTIAL 或 FAIL → 排查 shim 编译问题，修复后重新验证。

✅ verify-loading PASS → 停。

---

## 阶段 4: Project-customize（裁剪到实际栈）

### 4.1 裁剪 conventions.md

- 分层表用**旧项目的真实目录名**（不是模板默认的 `packages/ui-primitives`）
- 测试约定用**旧项目实际的测试框架**
- commit 约定：如果旧项目已有 conventional commits → 保留；没有 → 引入

### 4.2 裁剪 boundaries.md

- import 图用**旧项目的真实目录名**
- 如果旧项目没有分层 → 先不强制，boundaries 写"当前无分层，新代码按 X 规则"
- lint 规则设 `warn`（既有违规不阻断，新代码 error）

### 4.3 裁剪 skills

- `frontend-patterns.md`：Layer 表 → 真实目录；状态库 → 实际用的
- `design-tokens.md`：token 结构 → 对齐实际（可能旧项目用 CSS 变量不用 DTCG）
- `state-machines.md`：库名 → 实际用的
- `pbt-cookbook.md`：框架名 → 实际用的（如果旧项目没有 PBT → 标"待引入"）

### 4.4 重新编译

```bash
bash scripts/sync-shims.sh
```

✅ 输出裁剪结果 → 停。

---

## 阶段 5: First feature（验证范式工作）

用新范式走一个完整 feature（`start-feature` workflow）：

- Pre-spec：triage + 反向确认 + explorer
- Kiro spec：Requirements → Design → Tasks → 执行
- Post-spec：executor verify + visual-reviewer + flow 更新

**这一步的目的不是交付 feature，是验证范式在旧项目上能跑通。**

验证点：
- [ ] agent 读到了 philosophy（引用了 P{n}）
- [ ] agent 遵守了 boundaries（没有跨层 import）
- [ ] agent 调了 sub-agent（可见 🔧 标记）
- [ ] agent 引用了 design-system（DS-{N}）
- [ ] flow 被创建/更新
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
- 旧文档原位不动（只有末尾注释）
- git blame 未被破坏
- 旧 `.kiro/specs/` 完整保留
- 新 `.kiro/steering/` 含 AgentOS 编译产物 + 旧项目特有规则（90-legacy-*）

## 反模式

- **覆盖旧 AGENTS.md**——必须 merge
- **删除旧 .kiro/steering/**——必须备份 + 保留不冲突的
- **跳过 verify-loading**——嵌入完成但 agent 可能什么都没读到
- **跳过 design-system 填写**——前端任务没有视觉约束
- **跳过 skills 裁剪**——agent 引用不存在的目录
- **一次性把所有旧文档标 archived**——会丢失 active-orphan
- **在阶段 5 之前就开始正式开发**——范式没验证就用，出问题回滚成本高
