> Status: Template — not initialized. This directory documents behavior-level smoke tests for agentOS. Run them manually or script them after embedding a concrete project.

# agentOS Evaluations

本目录记录 agentOS 工作环境自身的行为级验证（behavior-level evals），用于确认优化未引入退化。

## 运行方式

当前为文档化 smoke test，手动执行即可。未来可脚本化：`bash eval/run-smoke.sh`。

## Smoke Tests

见 [agentOS-smoke-eval.md](./agentOS-smoke-eval.md)。

## 新增 Eval 规范

- 描述用户请求或系统状态。
- 说明预期行为。
- 给出可执行的验证命令或检查项。
- 不依赖具体项目业务逻辑。
