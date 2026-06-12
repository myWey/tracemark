---
id: audit
status: active
audience: human (maintainers, reviewers)
purpose: 文档体系自身的健康度审计——按公认文档原则定期检查
last-confirmed: null
---

# 范式文档审计（Documentation Audit）

> 文档体系跟代码一样会熵增。这份是**审计基线**：每个 epoch 末尾或随
> `drift-check` 一起跑，检查文档体系自身是否还健康。

## 公认文档原则（业界共识）

| # | 原则 | 含义 |
|---|---|---|
| 1 | **Single Source of Truth** | 每个事实在一个地方 authoritative，其它地方引用 |
| 2 | **Diataxis 分离** | tutorial / how-to / reference / explanation 不混 |
| 3 | **可被发现** | 每文档至少两条进入路径（索引 + 上下文链接） |
| 4 | **可被定位** | 稳定 ID / anchor / 永久 link |
| 5 | **写者意图明确** | 标 audience（谁读）+ purpose（为什么） |
| 6 | **结构稳定 / 内容易变** | 头部 schema 固定，正文可演进 |
| 7 | **机器与人共读** | front-matter（机器）+ 正文（人） |
| 8 | **触发明确** | 文档何时被读 / 写在哪里写明 |
| 9 | **代谢机制** | 状态枚举 / 归档目录 / 阈值 prune |
| 10 | **审计可追** | last-confirmed / supersedes / git history |
| 11 | **进入门槛分层** | 5 分钟版 / 1 小时版 / 资深版 |
| 12 | **杀死孤儿** | 没有索引可达的文档不存在 |

## 当前合规状态

| # | 原则 | 状态 | 证据 / 缺口 |
|---|---|---|---|
| 1 | SSOT | ✅ | `.agent/` 是真理，IDE 配置是 shim |
| 2 | Diataxis | ⚠️ | how-to (workflows) ✓ / reference (skills, sub-agents) ✓ / explanation (_meta, _HARNESS) ✓ / **tutorial 缺**（`_README.md` 部分填补） |
| 3 | 可被发现 | ✅ | `_INDEX.md` 是总索引；每子目录 `_index.md` 全 |
| 4 | 可被定位 | ✅ | front-matter `id` 全部有 |
| 5 | audience + purpose | ✅ | 已为 meta 文档全部加 audience + purpose；其它文件正文清晰 |
| 6 | 结构稳定 | ✅ | front-matter schema 一致 |
| 7 | 机器+人共读 | ✅ | 双语策略明确（中文叙事 / 英文结构字段） |
| 8 | 触发明确 | ✅ | `_TRIGGERS.md` 全表 |
| 9 | 代谢机制 | ✅ | `prune.md` + 状态枚举 + `_archive/` |
| 10 | 审计可追 | ✅ | last-confirmed / supersedes / ratified-retroactively |
| 11 | 进入门槛分层 | ✅ | `_README.md` (5 分钟) / `_meta.md` (1 小时) / `_HARNESS.md`（资深） |
| 12 | 杀孤儿 | ✅ | `_INDEX.md` 链全；prune workflow 检测 |

## 审计 checklist（每 epoch 末跑）

跑 `drift-check.md` 时一并检查：

### 结构层

- [ ] `_INDEX.md` 列出的每份文档都还存在
- [ ] `.agent/` 下每份文档都被 `_INDEX.md` 或某个 `_index.md` 列出（无孤儿）
- [ ] 每份文档头部有 `id`、`status`、`audience`（如适用）、`purpose`（如适用）
- [ ] 单文件 < 300 行；超过的标 prune 候选

### 触发层

- [ ] always-on 文件确实进了所有 IDE shim
- [ ] on-demand 文件被对应 workflow 引用
- [ ] passive-archive 文件**不**进 agent 上下文（避免 cache 污染）
- [ ] 跑一次 `verify-loading.md` 确认实际加载

### 内容层

- [ ] always-on 文件的 `last-confirmed` 不超过 6 个月
- [ ] 状态为 `active` 的 ADR / flow 都还反映现实
- [ ] glossary 里的 `proposed` 词龄 > 1 epoch 必须升 `active` 或 `retired`
- [ ] 所有 sub-agent 的 I/O contract 与实际调用方一致

### 代谢层

- [ ] `_archive/` 总大小没超过 active 区
- [ ] 长尾 skill（一个 epoch 没被加载过）→ 候选归档
- [ ] handoff `done` 状态 > 30 天 → 归档

## 失败处理

任何 ❌ → 在 `.agent/sessions/{ulid}/audit-report.md` 记录 + 提议修复 PR。

任何 ⚠️ → 列入下一个 epoch 修复目标。

## 与 drift-check 的关系

- `drift-check` 检查"文档 vs 现实代码"是否一致（哲学 / ADR / glossary 还成立吗）
- 本 audit 检查"文档体系自身是否健康"（结构 / 触发 / 代谢）

两个是配套的，跑 `drift-check` 时一并跑本 audit。
