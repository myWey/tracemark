---
id: workflow-regenerate-map
status: active
---

# 工作流：regenerate-map

## 目的

刷新 `.agent/map/` 下的派生文件，使它们反映当前代码、契约与 ADR。**Map 是
派生物**，不要手编辑。

## 何时跑

- PR merge 后（post-merge IDE hook）
- `shared/` 契约或 ADR 变更后
- 会话开始时若任一 map 的 `Source-hash` 失配
- 用户主动请求

## 步骤

### 1. 检测失配

对 `.agent/map/` 下每个带头部的文件：

- 读其 `Sources` 与记录的 `Source-hash`
- 在 `HEAD` 上对那些 source 路径计算当前 hash
- 不匹配则标记需要重生成

如果用户指定了具体文件，无视 hash 也重生成。

### 2. 委托给 doc-syncer

调 `doc-syncer`：

```yaml
trigger: startup-staleness | post-merge | new-adr | schema-change
changed_paths: <自上次提交起的 git diff 路径列表，如有>
target_files: <失配文件列表；空 = 全部>
budget:
  max_runtime_seconds: 120
```

### 3. 各文件生成器（举例，按项目栈适配）

- **architecture.md / .svg**：从包清单 + 源码 import 生成依赖图
  （madge / dependency-cruiser → mermaid → svg）
- **api-surface.md**：扫 `shared/api-contracts/` 与 `shared/schemas/`
  → 表格：endpoint × input × output × 所属 feature
- **component-tree.md**：扫 `packages/ui-*` 与 `apps/*` 中组件
  → 按层分组、含 props 签名与已声明的交互态
- **route-map.md**：扫框架路由配置 / route 文件
- **data-flow.svg**：合并 `shared/events/` 与 `packages/features-*/state/`
  下的状态机
- **adr-timeline.md**：扫 `.agent/adr/*`，按 ID 排序、按 epoch 分组、
  画 supersedes 关系
- **flow-coverage.md**（建议）：交叉对照 `.agent/flows/*` 与既有组件、
  Storybook story、e2e 测试，列出每条 flow 中**未被 story / 测试覆盖的
  交互态**

### 4. 刷新头部

每个重新生成的文件，更新：

```
At: <ISO 时间戳，仅供参考>
Source-hash: sha256:<新 hex>
Sources: [<paths>] at commit <git sha>
```

### 5. spot-check

每个更新文件粗看一眼 diff。生成器输出可疑（空、乱码、暴增）→ 弃此次更新，
报告在 `notes`。

### 6. 汇报

告知用户（或调用方）：

- 已更新的文件
- 不变（已新鲜）的文件
- 生成失败的文件及原因

## 输出

- 头部一致刷新过的 map 文件
- 一行总结：`Map: 更新 N，未变 M，失败 K。`

## 完成判定

每个 map 文件要么有当前 `Source-hash`，要么列在失败清单并说明原因。

## 反模式

- 因为生成器输出"看着不对"就手编辑 map 文件——应该改生成器
- 在 `start-feature` 实施循环里跑——应该在阶段间跑，保持循环紧凑
