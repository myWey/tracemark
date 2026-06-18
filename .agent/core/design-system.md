---
id: design-system
status: active
audience: agent + human
purpose: 项目级 UI 规范——规定 TraceMark 的视觉语言、品牌色彩与交互质感
last-confirmed: Phase 6
---

# TraceMark UI 设计系统规范 (Design System)

## DS-1. 视觉基调

**“极简、通透、专业”**
TraceMark 致力于成为 macOS 平台上最高效且最具原素质感的标注工具。整体 UI 语言严格遵循 Apple Human Interface Guidelines (HIG)。
- 界面避免繁杂的修饰，大量运用**毛玻璃 (Glassmorphism / Thin Material)**，确保与 macOS 沉浸式环境融为一体。
- 拒绝生硬纯色，所有色彩和线条都要给人以专业设计软件的克制感。
- 动效极简但自然，悬浮、选中、切换工具时应有平滑反馈。

## DS-2. 色彩体系 (Premium Color Palette)

本期彻底摒弃过往高饱和度、高刺眼度的基础色（`#FF0000`, `#00FF00` 等），全面引入 macOS 系统级自适应高级色 (System Colors) 以及经典的莫兰迪/低饱和高级色：
- **品牌高亮 (Accent)**：`Color.accentColor` (随系统偏好适配，默认蓝色)。
- **标注用色盘 (Annotation Colors)**：
  - 红色 (Red)：使用 `Color.red` / `NSColor.systemRed`。
  - 黄色 (Yellow)：使用 `Color.yellow` / `NSColor.systemYellow`。
  - 蓝色 (Blue)：使用 `Color.blue` / `NSColor.systemBlue`。
  - 绿色 (Green)：使用 `Color.green` / `NSColor.systemGreen`。
  - 橙色 (Orange)：使用 `Color.orange` / `NSColor.systemOrange`。
  - 黑色 (Black)/白色 (White)：使用动态深色模式的对比色 (如 `primary` / `Color.primary`)。
- **背景与表面 (Surface)**：
  - 主工具栏、侧边栏：使用 `.thinMaterial` 材质，不设纯色背景。

## DS-3. 间距体系与圆角

- **工具栏 (Toolbar)**：图标间隔统一，padding 为 `8px` 到 `12px`，保证合理的 Hitbox 而不显拥挤。
- **圆角 (Corner Radius)**：
  - 浮动工具栏：较大圆角 (`16px` - `24px`，通常为胶囊状 Capsule 或是高度一半的圆角)。
  - 贴图 (Pin)：保留原生图片的直角或极小圆角 (`4px`) 辅以阴影。
  - 选区框/文本框：微圆角 (`4px`)，消除锋利感。

## DS-4. 字体与排版 (Typography)

- **字体族**：全量使用苹果系统默认字体（`San Francisco` / `.systemFont`）。
- **标注文本**：
  - 告别单薄的 Regular 字重，默认中等或加粗 (`Medium` 或 `Semibold`)，增加阅读性。
  - 文字默认带有极细微的背景投影 (`Shadow`) 或半透明背景，以保证在复杂底图上的可读性。
- **引线与徽章**：序号框内的数字必须完美居中对齐，使用 `Monospaced Digit` 确保数字宽度一致。引线（Connector）需要平滑抗锯齿。

## DS-5. 阴影体系 (Elevation)

- **悬浮层 (Overlay/Toolbars)**：使用柔和的宽阴影，例如 `radius: 10, y: 5, color: .black.opacity(0.15)`。
- **放大镜 (Magnifier)**：
  - 采用**大圆角矩形或纯圆形**，必须带有明显的物理高光/内阴影和清晰的边框线 (`0.5px` gray)。
- **文本框/几何框**：绘制的 Annotation 可附带极弱阴影（视复杂程度定），提升视觉层次感。

## DS-6. 图标与动效 (Icons & Motion)

- **图标库**：**全局必须使用 SF Symbols**。
  - 禁止混用粗细不一的素材。
  - 图标字重统一设定为 `.font(.system(size: 16, weight: .medium))` 或相似配置。
- **动效时长**：所有悬浮高亮、尺寸过渡控制在 `150ms` - `200ms`，缓动方式使用 `.easeInOut` 或 `spring()`。

## DS-7. 特定功能组件视觉约定

| 组件类型 | 视觉规则 |
|---|---|
| 主工具栏 (Toolbar) | 胶囊状 (`Capsule`) / 圆角矩阵，`.thinMaterial` 毛玻璃背景，带轻微外发光阴影。图标在悬浮时变亮或变灰底。 |
| 放大镜 (Magnifier) | 圆形或大圆角矩形，自带十字准星（红色/灰色极细线）和像素棋盘格，边缘有高亮 Stroke 和阴影。 |
| 贴图 (Pin Window) | 无边框（或 `0.5px` 毛玻璃边），带标准窗口阴影，位于层级顶层，支持多窗口错开叠加。 |
| 翻译/OCR面板 | 轻量级 Sidebar，右侧滑出，支持宽容度高的自适应宽度，内容卡片化。 |

## Agent 怎么用这份文件

1. **写 UI 代码时**：抛弃 Hardcode 的杂色代码（如 `Color(red: 1, green: 0, blue: 0)`），直接使用系统提供的 `.systemRed` 或 `Color.red`。
2. **构建按钮时**：永远优先查找适合的 `Image(systemName: "...")`。
3. **视觉走查**：对照这 7 条规则，检查是否存在不和谐的尖角、无阴影的漂浮物或过时的颜色配置。
