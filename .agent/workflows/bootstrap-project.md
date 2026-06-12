---
id: workflow-bootstrap-project
status: active
---

# 工作流：bootstrap-project

> ⚠️ **严格遵循 `agent-discipline.md` 6.9 工作流纪律**：每个 stage 结束必须
> ✅ 输出 + 等用户 `y` 才能进下一个 stage。**不要把多 stage 压到一次输出**。

## 目的

把空（或几乎空）的 repo + AgentOS 骨架，变成有"已确认的哲学、已落地的
分层、首份实体、首个 ADR、首个 vertical-slice spec"的项目。

## 何时跑

- 新 repo 第一次会话
- retrofit 不适用：retrofit 用 `retrofit-project.md` 或 `retrofit-with-legacy.md`

## Stage 列表（**严格按顺序**）

| #   | Stage　　　　　　　　　　　　　　　　　　　| 必做 | 产物　　　　　　　　　　　　　　　　　　　　　　　　　　| 必停　　　　　　　　　|
| -----| --------------------------------------------| ------| ---------------------------------------------------------| -----------------------|
| 0   | 初始化 workflow-state　　　　　　　　　　　| ✅　　| `.agent/sessions/{ulid}/workflow-state.md`　　　　　　　| 然后写完输出 → 等用户 |
| 1   | 收集素材 + 反向确认　　　　　　　　　　　　| ✅　　| `.agent/sessions/{ulid}/inputs/`　　　　　　　　　　　　| ✅　　　　　　　　　　 |
| 2   | 起草 philosophy　　　　　　　　　　　　　　| ✅　　| `.agent/core/philosophy.md`（≥ 5 P + 3 A）　　　　　　　| ✅　　　　　　　　　　 |
| 2.5 | 起草 design-system　　　　　　　　　　　　 | ✅　　| `.agent/core/design-system.md`（视觉基调 + token 意图） | ✅　　　　　　　　　　 |
| 3   | 调整 conventions　　　　　　　　　　　　　 | ✅　　| `.agent/core/conventions.md` 按栈裁剪　　　　　　　　　 | ✅　　　　　　　　　　 |
| 4   | 调整 boundaries　　　　　　　　　　　　　　| ✅　　| `.agent/core/boundaries.md` 指向真实目录　　　　　　　　| ✅　　　　　　　　　　 |
| 5   | 起草 ADR-0001 Foundation　　　　　　　　　 | ✅　　| `.agent/adr/0001-foundation.md` 填实内容　　　　　　　　| ✅　　　　　　　　　　 |
| 6   | 起草 glossary 初版　　　　　　　　　　　　 | 可选 | `.agent/core/glossary.md`（≥ 3 术语 active）　　　　　　| ✅　　　　　　　　　　 |
| 7   | 起草 entities 初版　　　　　　　　　　　　 | 可选 | `.agent/domain/entities.md`（≥ 3 实体）　　　　　　　　 | ✅　　　　　　　　　　 |
| 8   | 选首个 vertical slice + 启动 start-feature | ✅　　| `.kiro/specs/{slug}/`（移交 start-feature workflow）　　| —　　　　　　　　　　 |
| 9   | 收尾 + epoch-0 tag + handoff　　　　　　　 | ✅　　| git tag + `.agent/sessions/{ulid}/handoff.md`　　　　　 | —　　　　　　　　　　 |

> "可选"是指：bootstrap 时如果信息不足，**可以**延后。但必须在 workflow-state
> 里标 `deferred`，并在第一个相关 feature 触及时补。

## 每个 stage 结束的强制输出格式

```
✅ Stage {N}/9 done: {一句话总结}
📂 Files written:
  - {path}
🧠 Decisions captured (if any):
  - D{N}: ...
🔜 Next stage {N+1}/9: {一句话描述}

Continue? (回复 y / 调整 / 跳过)
```

**输出后立即停止。不要在同一回复里开始下一 stage。**

## 各 Stage 详细步骤

### Stage 0: 初始化

- 生成 ULID（如果环境无生成器，用时间戳 + 随机后缀）
- 用 `_workflow-state-template.md` 创建 `.agent/sessions/{ulid}/workflow-state.md`
- 锁定 step list（拷贝本文件的 stage 表）
- 输出 ✅ 然后停。

### Stage 1: 收集 + 反向确认

主动问用户（一次问完）：
- 定位一句话
- 用户痛点（2–5 个具体场景）
- 受众（主 / 次 / 不服务的）
- 审美参考（链接、截图、产品名）
- 栈偏好（如有）
- 硬约束（合规、性能等）
- 非目标

收到后**用 5–8 个 bullet 复述**，等用户确认"形状对吗"。

把原始素材落到 `.agent/sessions/{ulid}/inputs/`（每条一个 .md）。

输出 ✅ 然后停。

### Stage 2: 起草 philosophy

- 把模糊语句转成**判断式原则**（P1…Pn），格式：
  *"当 X 与 Y 冲突时，倾向 X。"*
- 5–7 条原则、按优先级
- 3–5 个反模式（A1…An）
- `last-confirmed` 设为今天

写完 → ✅ 输出 → 停。允许用户最多 3 轮调整。每轮调整也要 ✅ 输出 → 停。

### Stage 3: 调整 conventions

- 读模板 `.agent/core/conventions.md`
- 根据 Stage 1 的栈偏好**实际改动**：
  - "Layered front-end" 表：用真实目录名替换 `packages/ui-primitives` 等
  - 测试约定：用真实测试框架（vitest / pytest / etc.）
  - Conventional Commits：保留
- 不要保留 `{TBD}` 占位

写完 → ✅ → 停。

### Stage 4: 调整 boundaries

- 读模板 `.agent/core/boundaries.md`
- 用真实目录名替换分层 import 图
- 决定 lint 工具（dependency-cruiser / Steiger / eslint-plugin-boundaries）
- 在 ADR-0001 Decision 段记一句"边界由 {tool} 强制"

写完 → ✅ → 停。

### Stage 5: 起草 ADR-0001

- **不复制空模板**。基于 Stage 1 的栈偏好填实：
  - Decision 段写明：语言、框架、状态管理路线、API 风格、DB、部署、分层工具
  - Alternatives：列至少 2 个真实备选，写明拒绝理由
  - Consequences：正/负/中性各一段
- status 直接 `active`
- 调 `impact-analyzer` sub-agent（**按 6.10 规则可见地 role-play**）
  → 因为这是首个 ADR，影响是 scaffold，输出会很简短，但**必须可见地走过程**

写完 → ✅ → 停。

### Stage 5.5: 项目化 skills（基于 ADR-0001 的栈选型）

ADR-0001 确定了栈，现在把 skills 里的占位换成真实值：

- `.agent/skills/frontend-patterns.md`：
  - Layer 表里的目录名 → 换成 ADR-0001 决定的真实目录
  - 状态源段落 → 换成实际用的库名（如 TanStack Query / Zustand）
- `.agent/skills/design-tokens.md`：
  - token 分类 → 对齐 `shared/tokens/` 的实际子目录
  - 构建步骤 → 写明用什么工具转换（如 style-dictionary / token-transformer）
- `.agent/skills/state-machines.md`：
  - 库名 → 换成实际用的（XState / zustand / 自写 reducer）
  - 文件路径约定 → 对齐 boundaries 的真实目录
- `.agent/skills/pbt-cookbook.md`：
  - 框架名 → 换成实际用的（fast-check / Hypothesis / proptest）
  - 文件命名 → 确认 `*.pbt.ts` 还是其它后缀

每个 skill 改完后跑 `sync-shims.sh`（auto-sync hook 会自动触发）。

写完 → ✅ → 停。

### Stage 6: 起草 glossary（可选但推荐）

- 从 Stage 1 素材 + philosophy 提取 ≥ 3 个领域术语
- 每个：中文规范名 + 英文规范名 + 定义（一句话）
- 状态全部 `proposed`，等首个 feature 在代码中确认后转 `active`

如果 Stage 1 素材里术语很少（< 3 个值得记）：
- 标 deferred 在 workflow-state 里
- 输出 ⚠️ 而非 ✅，说明"延后到首个 feature 阶段"

→ 停。

### Stage 7: 起草 entities + concept-map（可选但推荐）

同上。如果用户素材偏纯前端 / 工具类项目，没有明显领域实体：
- 标 deferred
- 输出 ⚠️ → 停

如果 entities 已写：
- 基于 `domain/entities.md` 生成 `domain/concept-map.mmd`（Mermaid erDiagram）
- 只画实体 + 关系 + 基数，不画属性细节（保持 < 20 节点）
- entities 被 deferred → concept-map 一并 defer

### Stage 8: 选首个 vertical slice

- 提 2–3 个候选 feature，**重点选最能压力测试假设的**（不是最简的）
- 用户确认后→**移交给 `start-feature.md` workflow**
- 此时 bootstrap 不再驱动；start-feature 接管
- workflow-state 里把当前 stage 标 done，把 status 改为 `handed-off-to-start-feature`

### Stage 9: 收尾

- 调 `regenerate-map.md` 做**首次 map 生成**（至少生成 `architecture.md` + `adr-timeline.md`）
- `git tag epoch-0`
- 调 `scribe` sub-agent 写一份 handoff（首个 handoff = 项目"出生证"）
- workflow-state status → `done`
- 提示用户：**「请阅读 `.agent/core/dialog-rules.md`——它教你如何与 agent 高效对话，是发挥范式效力的关键」**

## 完成判定

- 所有 ✅ 的 stage 都完成（不是 ⚠️ deferred）
- 一个新成员（人或 agent）能从 AGENTS.md → philosophy → conventions → ADR-0001
  解释这个项目"做什么 / 为谁 / 怎么搭"
- 首个 slice 实施时不需要发明 glossary 之外的术语

## 反模式（**这些是 bootstrap 最常见失败**）

- **跳过 conventions/boundaries 调整直接写 ADR**——ADR 引用了占位边界，
  后续代码不知道按什么约束写
- **glossary / entities 完全跳过**——后续命名飘忽，第一个 feature 就开始
  造词
- **用户没确认就直冲 vertical slice**——slice 假设的 philosophy 可能不成立
- **不调 impact-analyzer 写 ADR**——ADR 没有 Impact 段，后续超 supersede
  时没基线
- **多 stage 压到一次输出**——表面快、实际跳过用户审核点；这是 6.9 红线

## Antigravity 适配说明

在 Antigravity IDE 中执行本 workflow 时的特殊注意事项：

- **沙箱限制**：Antigravity 终端沙箱限制对 `.` 开头目录的 shell 命令。Stage 5
  的 `sync-shims.sh` 应改用 `python scripts/sync-shims.py` 执行。
- **Stage 8 移交**：`start-feature.md` 将走 **4B（Antigravity Planning Mode）**
  分支——创建 `implementation_plan.md` 而非 Kiro Spec。
- **Stage 9 handoff**：写完 handoff 后执行 `bash scripts/antigravity-sync.sh backup`
  将规划文件备份到仓库。
- **Soft Hook**：由于 Antigravity 没有原生 Hook，Stage 4（ADR-0001）后需主动
  调 `impact-analyzer`，不要等 hook 自动触发。

