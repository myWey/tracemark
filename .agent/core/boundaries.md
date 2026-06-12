---
id: boundaries
status: template
last-confirmed: null
---

# 模块边界（Boundaries）

> 什么能 import 什么。**用 lint 强制**，不是写在文档里求自觉。Agent 不得绕过
> 边界，哪怕只是"临时"。

## 分层 import 图（前端默认套）

```
Layer 4: apps/*                     ← 页面、路由、应用外壳
   ↑
Layer 3: packages/features-*        ← 业务 feature、hooks、状态机
   ↑
Layer 2: packages/ui-composites     ← form-field、data-table 等
   ↑
Layer 1: packages/ui-primitives     ← Button、Input、Card（headless + tokens）
   ↑
Layer 0: shared/{tokens,schemas,events,api-contracts}
```

**规则**：import 只能**向上**。不允许平级或向下。

> 项目实际目录可能不一样（特别是 retrofit 进既有项目时）。这里的层级是**意图**；
> 实际目录名由 ADR-0001 / ADR-0002 锁定。lint 配置必须对齐到实际目录。

## 跨层均可使用的"中性物"

- `shared/tokens/`
- `shared/schemas/`
- `shared/events/`
- `shared/api-contracts/`
- 标准库 + 经 ADR 批准的外部依赖

## 禁止模式

- primitive 引用 feature（`ui-primitives → features-*`）
- 一个 page 直接引用兄弟 page（应通过 shared 模块或路由）
- 两个 feature 互引（共享逻辑应抽到上层或 `shared/`）
- schema 引用 feature（schema 必须是纯数据定义）
- 内联 magic number / 颜色 / 字符串而不是引用 token / schema

## 强制方式

- **TypeScript path alias** 按层限制
- **dependency-cruiser** 或 **Steiger** 在 CI 里强制
- 每个 package 的 ESLint `no-restricted-imports`
- 边界违反**直接 fail build**，不是 warn（既有项目接入时，初期可设 warn——见
  `retrofit-project.md` 第 1.5 步）

## 例外

- 测试文件可以从任意层引测试工具
- Storybook story 可以引用目标组件 + mock
- 其它例外**必须**有 ADR 记录

## 何时引入新一层

只在"同一逻辑在 3+ 既有层都需要"且"不能作为某层的兄弟存在"时。否则在既有层
内抽兄弟。

## 与 flow 的关系

flow 文件用**用户视角**描述路径，但其引用的组件、hooks、状态机必须遵守这里的
边界。一个 flow 引用了越层的组合 → flow 没错，错的是组件该被分解。
