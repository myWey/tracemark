---
id: flow-003
slug: pin-and-history-edit
status: active
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
related-adrs: [ADR-0001, ADR-0002]
related-specs: []
---

# FLOW-003: 贴图Pin与历史截图再编辑流程

> 一句话：支持将截图或历史快照以悬浮窗（Pin）形式钉在桌面上参考，并支持从历史面板重新唤起画布对标注内容进行无损修改。

## 入口

1. **贴图 Pin 入口**：
   - 截图完成后在右下角悬浮窗上，或者在标注编辑界面底部工具栏中，点击“钉住 (Pin)”按钮。
   - 历史记录界面中，每个历史卡片浮现的悬浮操作区点击“钉住 (Pin)”图标。
2. **再编辑入口**：
   - 历史记录界面中，每个历史卡片悬停时，点击“再编辑 (Edit)”按钮。

## 路径（步骤）

### 第一部分：贴图 Pin 流程

1. **生成贴图窗口 (Pin Window)**
   - 在入口触发 Pin 后，屏幕上原地淡入一个无边框、无标题栏、四角圆角带软阴影的精致贴图悬浮卡片 (`PinWindow`)。
   - 贴图内容展示选中的图片，并置顶于所有系统窗口层级最上方（level = .floating 或更高）。

2. **贴图互动操作**
   - **移动位置**：用户在贴图窗口主体区域内按下左键拖拽，即可任意平滑拖动贴图。
   - **调节透明度**：在贴图窗口上方滚动鼠标滚轮（Scroll Wheel），透明度随之无级调整（透明度下限为 0.15，上限为 1.0），便于遮挡对比。
   - **快速关闭**：双击贴图卡片，播放淡出动效，卡片关闭销毁。

---

### 第二部分：历史再编辑流程

1. **历史卡片时间线浏览**
   - 用户点击顶部状态栏的“历史记录”，唤起历史窗口。
   - **时间线布局**：左侧为带有实心圆点、虚实连接线的垂直时间轴；右侧按时间由新到旧分成“今天”、“昨天”、“更早”等分组展示截图列表。
   - **固定尺寸**：列表内每一个历史卡片的缩略图容器规格完全固定（例如：宽高比例固定为 16:9，缩略图在容器内 Fit/Fill 显示），避免因为截图本身大小不一导致布局凌乱错落。

2. **触发再编辑**
   - 用户鼠标悬停在某个历史卡片上，卡片浮现“再编辑”图标，用户点击。
   - 历史窗口失去核心焦点（或暂时隐藏），系统根据该记录对应的 UUID 读取其无损原图 `_original.png` 以及存放在 `metadata.json` 里的 `annotations` 矢量数组。
   - 弹出 `AnnotationRootView`，画布上完美还原该历史记录此前绘制的所有箭头、矩形、文本。

3. **修改并更新**
   - 用户在画布上自由删除已有的形状、移动文本框、更改颜色、或者新画标注。
   - 点击“完成并复制”：
     - 系统在后台用新的矢量数据重新渲染覆盖 `_original.png` 并生成新的已标注图 `Screenshot_yyyyMMdd_HHmmss.png`。
     - 将修改后的标注数组回写至 `metadata.json`。
     - 触发全局 `HistoryDidUpdate` 通知，历史记录界面自动刷新预览图。

## 交互态矩阵

| 页面/组件 | 交互态 | 视觉参考 | 状态机 |
|---|---|---|---|
| PinWindow | 浮动挂载态 | 屏幕上任意位置的无边框圆角图片，带阴影且常驻最前 | `PinWindow` |
| HistoryRootView | 时间线空状态 | Timeline 轴线淡化，中间显示“暂无截图历史” | SwiftUI `HistoryRootView` |
| HistoryRootView | 时间线填充态 | 左侧圆点，右侧固定卡片，鼠标 Hover 卡片露出“Pin/编辑/Finder/删除”按钮 | SwiftUI `HistoryRootView` |

## 边界条件 / 失败模式

- **老数据兼容**：如果编辑一个旧版本创建的历史记录（即其 `annotations` 字段不存在），我们优雅地将其反序列化为 `[]`（空数组），底图使用原历史图进行一次性背景载入（作为一次性的底层新编辑起步）。
- **多贴图同屏**：用户可以同时 Pin 任意多个贴图。每一个 `PinWindow` 有自己独立的 UUID 和透明度状态。
- **贴图退出清理**：退出 App 时，所有常驻置顶的 `PinWindow` 会一并销毁退出，绝不留存后台。

## 引用

- **组件**：
  - `Sources/Screenshot/UI/PinWindow.swift` (New file)
  - `Sources/Screenshot/History/HistoryRootView.swift`
  - `Sources/Screenshot/History/HistoryManager.swift`
- **ADR**：[ADR-0002](file:///Users/zerohsueh/Gemini/screenshot/.agent/adr/0002-annotations-serialization.md)
- **原则**：P3 (零摩擦), P4 (精致视觉)
