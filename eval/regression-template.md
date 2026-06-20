> Template for converting a repeated mistake or lesson into an automated regression check.

# Regression Eval Template

每在 `.trae/memory/project_memory.md` 的 `## Lessons` 中新增一条教训，就按本模板在 `eval/` 下新增一条可执行检查，防止同一错误重复发生。

## 元数据

```yaml
lesson_id: [short-id]
discovered: [YYYY-MM-DD]
related_files: [paths]
memory_entry: ".trae/memory/project_memory.md ## Lessons"
```

## 场景

[描述当初导致错误的具体场景]

## 错误表现

[描述错误症状，越具体越好]

## 根本原因

[一句话总结根本原因]

## 自动化检查

### 检查项 1

**目的**：[防止什么]

**命令**：
```bash
[可执行的 bash 命令]
```

**通过标准**：[明确的输出或退出码]

### 检查项 2（可选）

...

## 修复方案参考

[当时是如何修复的，方便未来复用]

## 示例

```yaml
lesson_id: hook-bash-variable
discovered: 2026-06-17
related_files:
  - .trae/hooks/protect-files.sh
  - .trae/hooks/post-edit-lint.sh
memory_entry: ".trae/memory/project_memory.md ## Lessons"
```

**场景**：在 bilingual hook 脚本中，全角中文标点紧邻 `$variable`，在 macOS bash 3.2 下触发 `set -u` 错误。

**错误表现**：`$variable` 被解析失败，hook 非正常输出 JSON 决策。

**根本原因**：未使用 `${variable}` 形式引用变量。

**自动化检查**：

```bash
# 检查所有 hook 脚本中是否对变量使用 ${} 形式（至少没有紧邻中文标点的 $var）
grep -nE '\$[a-zA-Z_][a-zA-Z0-9_]*[，。！？；：]' .trae/hooks/*.sh && echo "FAIL" || echo "PASS"
```

**通过标准**：输出 `PASS`。
