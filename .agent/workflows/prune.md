---
id: workflow-prune
status: active
---

# 工作流：prune（防止文档膨胀）

## 目的

定期裁剪 `.agent/` 下的内容，避免**维护成本超过收益**——这是范式最容易自我
破坏的失败模式。

## 触发条件（任一）

- `.agent/` 总行数 > 5000（agent 加载变慢）
- 单个文件 > 300 行（人类不读、agent 抓重点低）
- ADR 总数 > 50 且超过半数 status=`active`（说明从没收编过）
- flow 总数 > 30（前端流程膨胀）
- session handoff 未归档数 > 10（任务断点堆积）
- skill 总数 > 8（按需加载策略形同虚设）
- map 失败 > 1 周（生成器坏了没人修）
- epoch 切换时（每个 epoch 末尾跑一次）

## 步骤

### 1. 测量

跑下面的盘点（agent 自动）：

```yaml
totals:
  agent_dir_lines: <N>
  files_over_300_lines: [path, ...]
  adr_count_active: <N>
  adr_count_superseded: <N>
  flow_count_active: <N>
  flow_count_deprecated: <N>
  session_open_count: <N>
  skill_count: <N>
  map_files_stale: [path, ...]
```

### 2. 候选清单（auto）

agent 列出**可以裁剪**的候选：

- ADR 状态为 `active` 但其决策已不在代码中体现 → 标 `superseded` 或拆并
- flow `deprecated` 超过两个 epoch → 移出主索引，归档到 `flows/_archive/`
- session handoff 状态 `done` → 归档到 `sessions/_archive/`
- skill 几乎从未被加载（看 commit / chat 记录引用频次）→ 候选删除或合并
- 单个文件 > 300 行 → 候选拆分（把次级章节抽成兄弟文件）
- map 文件失败 > 1 周 → 修生成器或弃用

### 3. 用户审

把候选清单给用户，标记四种动作之一：

- ✂️ **prune**：裁掉 / 归档
- 🔀 **merge**：合并到另一份
- 🛠️ **fix**：保留但需要修复（多见于 map 失败）
- 🟢 **keep**：保留不动

不让 agent 自动 prune——这是用户判断。

### 4. 执行

- prune：移到 `_archive/` 子目录（**不删**，留 git 历史 + 物理回收点）
- merge：写新文件，把旧的标 `superseded-by`，移到 `_archive/`
- fix：跑相关 workflow（如生成器修复就跑 `regenerate-map`）
- keep：什么也不做

### 5. 更新索引

跑 `regenerate-map` 刷新 ADR / flow / skill 的索引文件。

### 6. 复盘

把这次 prune 的统计写到一份简短报告 `.agent/sessions/{ulid}/prune-report.md`：

- 删了什么、合了什么、新总数
- 觉得哪类内容增长太快（信号：可能是 ADR 颗粒太细，或者 flow 重复）
- 建议下次 prune 的触发条件调整

## 归档目录约定

```
.agent/
├── adr/
│   └── _archive/           ← superseded 后被归档的 ADR
├── flows/
│   └── _archive/           ← deprecated 后被归档的 flow
├── sessions/
│   └── _archive/           ← done 状态的 handoff
└── skills/
    └── _archive/           ← 退役的 skill
```

归档目录的内容：

- **不在主索引里**（防止误用）
- **不进 cache / 不被 always-on 加载**
- **保留**，便于追溯
- 真要删，需要单独的 `git rm` PR + ADR 说明

## 维护成本控制总原则

1. **新增有摩擦**：写新 ADR / flow 必须用模板 + 索引登记。提高新增门槛。
2. **裁剪是常态**：每个 epoch 末尾跑一次 `prune` + `drift-check`。
3. **生成物不维护**：map 是派生的，坏了修生成器，不要手编辑。
4. **handoff 即焚**：完成的 handoff 一律归档；常驻只看 in-progress 的。
5. **上限即报警**：5000 行 / 300 行 / 50 ADR 是经验阈值，到了主动 prune。

## 反模式

- 把 prune 当成"清洁工任务"扔给 agent 自动跑——这是用户判断
- 物理删除而不归档——丢历史
- 把所有 ADR 都标 active 因为"难判断"——`superseded` 是常态，不是失败
- 不裁 skill——长尾 skill 比单纯多一份文档更糟，因为它在抢加载预算
