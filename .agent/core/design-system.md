---
id: design-system
status: template
audience: agent + human
purpose: 项目级 UI 规范——不是通用模式（那在 skills/），而是"这个项目的视觉长什么样"
last-confirmed: null
---

# 设计系统规范（Design System）

> Bootstrap Stage 2.5（philosophy 之后、ADR-0001 之前）填写。
> 这份文件是 `shared/tokens/` 的"设计意图说明"——token 是值，这里是为什么。
>
> Sub-agent（visual-reviewer / fixer）通过主 agent 传入的 intent 引用本文件的
> 段落 ID（DS-1、DS-2…）。

## DS-1. 视觉基调

{一句话描述整体视觉感受。例如："克制、信息密度高、留白适度、无装饰性动效"}

参考产品 / 截图：{链接}

## DS-2. 色彩体系

- **品牌色**：{primary / secondary / accent}
- **语义色**：success / warning / error / info
- **中性色**：surface / text / border / disabled
- **暗色模式**：{是否支持 / 策略}

对应 token 文件：`shared/tokens/base/color.json` + `shared/tokens/semantic/color.json`

## DS-3. 间距体系

- **基础单位**：{4px / 8px}
- **Scale**：{列出 spacing-1 到 spacing-N 的值}
- **使用规则**：{组件内间距用 N，组件间用 M，section 间用 L}

对应 token 文件：`shared/tokens/base/spacing.json`

## DS-4. 字体体系

- **字体族**：{中文 / 英文 / 等宽}
- **字号 scale**：{xs / sm / base / lg / xl / 2xl / ...}
- **行高规则**：{紧凑 / 正常 / 宽松}
- **字重**：{regular / medium / semibold / bold}

对应 token 文件：`shared/tokens/base/typography.json`

## DS-5. 圆角 & 阴影

- **圆角 scale**：{none / sm / md / lg / full}
- **阴影层级**：{sm / md / lg / xl}——对应 elevation

## DS-6. 动效

- **策略**：{无动效 / 最小动效 / 丰富动效}
- **时长**：{fast: Nms / normal: Nms / slow: Nms}
- **缓动**：{ease-out 为主 / spring / ...}
- **原则**：{动效服务于信息层级，不服务于装饰}

## DS-7. 组件视觉约定

| 组件类型 | 视觉规则 |
|---|---|
| Button | {圆角 md、高度 40px、primary 用品牌色填充、secondary 用 outline} |
| Input | {圆角 sm、border 1px neutral-300、focus 时 ring 2px primary} |
| Card | {圆角 lg、shadow-sm、padding spacing-4} |
| Modal | {居中、overlay 50% black、圆角 lg} |
| Toast | {右上角、auto-dismiss 5s、圆角 md} |

> 这张表随组件增加而扩展。每加一个 Layer 1 primitive 时来这里补一行。

## DS-8. 响应式断点

| 名称 | 宽度 | 策略 |
|---|---|---|
| mobile | < 640px | {单列 / 隐藏侧栏 / ...} |
| tablet | 640–1024px | {双列 / ...} |
| desktop | > 1024px | {三列 / 侧栏展开 / ...} |

## Agent 怎么用这份文件

1. 写 UI 代码时**引用 token 名**（不是具体值）。token 名来自 `shared/tokens/`，
   设计意图来自本文件。
2. 新建组件时查 DS-7 表——如果该类型已有约定，遵循；没有则提议加一行。
3. 主 agent 调 `visual-reviewer` 时，在 input 的 `intent` 字段引用 DS-{N}。
4. 主 agent 调 `fixer` 做视觉批量修时，pattern 来自本文件的规则。
5. 如果用户说"感觉不对"但说不清哪里——对照本文件逐项检查。

## 何时更新

- Bootstrap Stage 2.5（首次填写）
- 新增 Layer 1 primitive 时（补 DS-7 表）
- 用户说"整体风格要调"时（改 DS-1 + 相关 token）
- 每个 epoch 的 drift-check 时验证是否还贴合现实
