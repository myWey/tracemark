# Goal Description

根据审计和评估结论，对 Antigravity 环境下的 AgentOS 工作范式进行深度适配与精细化优化：
1. **同步脚本（antigravity-sync.sh）自适应升级**：支持完全缺省参数运行，通过自动嗅探最新修改的 IDE 局部会话目录及最新的仓库 Session 目录，免除手动传参的复杂度。
2. **Git Commit 联动静默备份**：在 [lefthook.yml](file:///Users/zerohsueh/Gemini/workflow-antigravity/lefthook.yml) 的 `pre-commit` 阶段，注入一个针对 Antigravity 的自动静默备份 Hook，确保每一次代码提交前自动备份规划文件，实现防丢保护与流程闭环。

## User Review Required

> [!IMPORTANT]
> 1. 本次升级完全向下兼容。当用户或 Agent 手动传入参数时，继续使用传入参数；缺省时自动激活自适应嗅探机制。
> 2. `lefthook` 中的自动备份将在 `.gemini/` 目录存在时执行，在纯粹的其它 IDE 环境中（无 Antigravity brain）会自动跳过，保证非 Antigravity 环境下的无干扰协同。

## Open Questions

无。

## Proposed Changes

### 1. Synchronization Optimization

#### [MODIFY] [antigravity-sync.sh](file:///Users/zerohsueh/Gemini/workflow-antigravity/scripts/antigravity-sync.sh)
- 允许参数缺省，加入自适应嗅探逻辑：
  - **`session_ulid` 缺省**：自动在仓库 `.agent/sessions/` 下定位最近更新（Latest Modified）的目录（排除 `_archive`）。
  - **`app_data_dir` 缺省**：自动探测 Mac 默认路径 `${HOME}/.gemini/antigravity-ide`。
  - **`conversation_id` 缺省**：在 brain 目录下自动定位最近被创建和修改（Latest Modified）的会话目录。

### 2. Git Hook Automation

#### [MODIFY] [lefthook.yml](file:///Users/zerohsueh/Gemini/workflow-antigravity/lefthook.yml)
- 在 `pre-commit` 部分新增 `antigravity-auto-backup` 任务：
  - 触发条件：本地存在默认的 `${HOME}/.gemini/` 且项目级 `antigravity-sync.sh` 脚本可执行。
  - 执行指令：`bash scripts/antigravity-sync.sh backup` （不带任何参数，全自动静默嗅探并备份）。

### 3. Workflow Prompts Streamlining

#### [MODIFY] [write-handoff.md](file:///Users/zerohsueh/Gemini/workflow-antigravity/.agent/workflows/write-handoff.md) & [resume-session.md](file:///Users/zerohsueh/Gemini/workflow-antigravity/.agent/workflows/resume-session.md)
- 更新其中的命令提示，将复杂的带参数脚本调用简化为一键式指令：
  - Handoff 备份简化为：`bash scripts/antigravity-sync.sh backup`
  - Resume 恢复简化为：`bash scripts/antigravity-sync.sh restore`

---

## Verification Plan

### Automated Tests
- 执行 `bash scripts/sync-shims.sh` 重新编译更新后的 rules，确保 `--check` 通过。
- 本地模拟不带参数运行自适应嗅探备份与恢复：
  - 建立模拟仓库 sessions 目录，写入 mock-ulid。
  - 建立本地 mock-gemini 临时 brain 目录，写入 mock 规划文件。
  - 执行不带参数的 `backup`，验证是否正确自适应定位 to mock-ulid 并完成备份。
  - 验证 `restore` 是否能自适应找到会话并进行还原。

### Manual Verification
- 检查 `lefthook` 的语法和 `pre-commit` 结构校验。
