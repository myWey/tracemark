---
description: 
---

# 工作流：verify-loading（验证 IDE 是否真的加载了 .agent/）

## 目的

各 IDE 加载 `.agent/` 的机制不同，**面板显示不能保证内容真的进了 prompt**。
这个 workflow 让你用一次空对话就验证——agent 必须能**复述具体内容**才算通过。

## 何时跑

- 第一次在某个 IDE 打开项目
- 切换 IDE 后
- 改了 steering shim 后怀疑没生效
- 怀疑 agent 行为偏离范式时（"它好像没读到我的原则"）

## 步骤

1. 开一个**全新的对话窗口**（不要继承之前会话）
2. 把下面这段 prompt 整段粘给 agent
3. 对照"通过判据"逐项检查回复

## 验证 prompt

```
请只用你当前 system prompt 中已经加载的内容回答下列 6 题。
不要打开任何文件。不要 grep。如果你不知道，明确说"未加载"。

Q1. 本项目的语言约定（Language policy）规定了哪几类文件应该用中文，哪几类应该用英文？
Q2. 列出本项目的"会话开始时的必读清单"，按顺序。
Q3. agent-discipline 的 4 条核心规则的标题分别是什么？
Q4. 在前端任务里，FLOW 与 ADR 的边界是什么？给一句话区分。
Q5. 本项目允许使用什么"时间"做内部引用？什么时间只用于审计？
Q6. 如果发现自己同一个方法尝试两次都失败，你应该怎么做？

最后一行只输出："Loading: PASS" 或 "Loading: PARTIAL（缺 X）" 或 "Loading: FAIL"。
```

## 通过判据

每题应来自这些文件：

| 题号 | 应该来自 | 触发文件 |
|---|---|---|
| Q1 | 语言约定 | `AGENTS.md` 或 `core/conventions.md` |
| Q2 | 必读清单 | `AGENTS.md` |
| Q3 | Karpathy 4 条 | `skills/agent-discipline.md` |
| Q4 | flow vs ADR 边界 | `flows/_index.md` 或 `adr/_index.md` |
| Q5 | 逻辑时间 | `AGENTS.md` 硬性规则 / `_meta.md` |
| Q6 | "two failed attempts" | `skills/agent-discipline.md` 6.6 |

**Q1 + Q2 + Q5 全错** → AGENTS.md 没被加载，IDE 注册有问题。
**Q3 + Q6 错** → `skills/agent-discipline.md` 没被注入。这是最常见的失败——
重点检查 IDE shim 里对该文件的引用语法是否正确。
**Q4 错** → flows / adr 索引没被加载，工作时可能跑偏到全部塞 ADR。

## 失败时的修复路径

### Kiro

- 确认 `.kiro/steering/00-core.md` 在面板里且 inclusion = always
- 确认 `00-core.md` 内部用 `#[[file:../../.agent/skills/agent-discipline.md]]` 语法
- 重启 Kiro 让 steering 缓存失效
- 仍失败：可能是 Kiro 没递归解析嵌套引用——临时方案是把内容**直接复制**到 `00-core.md`（牺牲 SSOT 换可靠性）

### Cursor

- 确认 `.cursor/rules/00-core.mdc` 头部 `alwaysApply: true`
- Cursor 用 `@filename` 而不是 `#[[file:...]]`
- 在 chat 里打 `/rules` 查看 active rules

### Claude Code

- 确认 `.claude/CLAUDE.md` 用 `@../AGENTS.md` 这种相对路径
- 在 chat 里打 `/memory` 查看加载的 memory

### Antigravity

### Antigravity

- 确认根目录 `AGENTS.md` 存在——Antigravity 通过 `user_rules` 机制将其作为 `RULE[AGENTS.md]` 自动注入 system prompt
- 确认根目录 `AGENTS.md` 内部包含了 `<!-- AUTO-GENERATED SHIMS START` 标记及下方的核心规则
- 确认根目录 `AGENTS.md` 行数在 **600–800 行**区间（太短内容丢失，太长注意力衰减）
- Q1–Q6 部分失败：说明根目录 `AGENTS.md` 未注入最新编译产物。运行 `python scripts/sync-shims.py` 即可自动向 `AGENTS.md` 末尾安全注入合并规则（注意：终端沙箱限制 `.` 开头目录的 shell 命令，该 Python 脚本利用原生文件 IO 规避）。
- **不要**手动将 `.antigravity/AGENTS.md` 覆盖到根目录，这会导致下一次运行 `sync-shims.py` 时文件无限膨胀。

### 其它 IDE

- 看该 IDE 文档对引用语法的说明
- 兜底方案：把 `agent-discipline.md` 内容**直接复制**到该 IDE 的 always-on 配置文件

## 通过后

- 把验证结果记到 `.agent/sessions/{ulid}/verify-report.md`
- 在该 IDE 上工作可放心
- 切 IDE 时再跑一次

## 反模式

- 跳过这个验证，假设"加载了就生效"——是范式无声失败的最大单点
- 用打开过 `.agent/` 文件的窗口验证（agent 已读到了，结果不算数）
- 让 agent 读完再问——这是测它读的能力，不是测加载机制