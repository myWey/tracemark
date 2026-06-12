---
id: flow-002
slug: annotation-canvas
status: active
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
related-adrs: [ADR-0001, ADR-0002]
related-specs: [Spec-2]
---

# FLOW-002: 矢量标注层与画布编辑流程

> 一句话：用户从右下角缩略图进入标注画布，进行箭头、方框、打码等精致标注后输出最终图片的完整闭环。

## 入口

- **悬浮卡片单击**：在 `FLOW-001` 成功生成右下角悬浮缩略图卡片（ThumbnailWindow）后，用户**单击缩略图主体区域**，或者点击卡片 Hover 态的“编辑”按钮。

## 路径（步骤）

1. **画布唤起 (Wake up Canvas)**
   - 点击缩略图后，ThumbnailWindow 瞬间淡出销毁。
   - 屏幕中央平滑弹出一个无边框的现代悬浮卡片窗口 (`AnnotationWindow` / `OverlayWindow` 中间编辑态)。
   - 窗口内等比缩放展示原始截图底图。

2. **双层悬浮工具栏 (Two-Tier Toolbar)**
   - 窗口底部或侧边悬浮一个高度固定、宽度固定的双层工具栏。
   - **上层（工具栏选择）**：将工具分组排列，并用 `|`（Divider）进行物理分区。当鼠标悬停在工具图标上时，显示工具的中文名称提示（Tooltip）。
     - 分组一 (Shapes)：矩形 (rectangle)、实心矩形 (filledRectangle)、圆形/椭圆 (ellipse)、直线 (line)、箭头 (arrow)。
     - 分组二 (Text)：文字 (text)、序号文字 (numberedText)、计数器 (counter)。
     - 分组三 (Effects)：画笔 (pencil)、荧光笔/高亮 (highlighter)、模糊 (blur)、马赛克 (mosaic)、聚焦/聚光灯 (spotlight)。
     - 操作区：撤销/重做、取消、完成。
   - **下层（样式与属性配置）**：
     - 调色板：预设多色圆形色块。
     - 统一尺寸滑块 (Size Slider)：无缝合并了之前的“字号”与“笔触粗细”概念。滑动可无级调节编辑工具的大小 (2...64)。当使用文本时，作为字号（最小 12pt）；当使用画笔/线条/打码时，作为线条粗细。
     - 文本样式 (Style Menu)：当选中“文字”或“序号文字”工具时，该层额外展现 TextStyle 下拉菜单（如 Standard, Boxed, Outlined 等）。

3. **属性的“粘性与实时生效”机制 (Sticky & Live Styles)**
   - **选中更新**：当画布上有某一个标注处于选中状态时，改变下层工具栏的颜色、尺寸、文本样式，会**实时作用**于当前选中的标注。
   - **后续生效**：该配置更新会记录到全局默认属性（Sticky Options），后续用户绘制的任何标注均自动应用最新的属性配置，无需反复重复设置。

4. **矢量数据绘制 (Vector Drawing)**
   - 用户在底图上拖动，绘制所选工具的图形。
   - 鼠标松开，将新建的 `AnnotationItem` 添加到画布，并且**默认保持选中该新标注**（便于立即对其进行微调，如移动或更改颜色）。

5. **文字自适应输入与再编辑 (Text Box Interactions)**
   - **初始输入**：点击文字工具并在选区内点击时，立即生成文字标注并进入高亮激活输入态，输入光标聚焦（无输入卡顿或延迟）。
   - **自适应与折行**：文本输入框宽度根据内容自适应。当输入宽度到达截图选区的右侧边界时，**自动换行**，防止文字渗透或溢出截图边界。
   - **位置移动与再编辑**：点击已创建的文本框可将其选中，选中状态下按住即可整体移动位置；双击已创建的文本则重新激活输入光标，允许修改此前的文字。

6. **输出与销毁 (Render & Export)**
   - 点击“完成”，系统在离屏渲染层将原图与所有矢量标注进行合并压制，存入剪贴板和历史记录，并关闭编辑窗口。

## 交互态矩阵

| 页面/组件 | 交互态 | 视觉参考 | 状态机 |
|---|---|---|---|
| AnnotationWindow | 初始挂载态 | 屏幕中央，大尺寸悬浮圆角卡片带重度阴影 | SwiftUI `AnnotationRootView` |
| UnifiedToolbarView | 常驻显示 (双层) | 上层图标组 + 下层属性调节面板，宽度固定不跳动 | SwiftUI `UnifiedToolbarView` |
| TextAnnotationView | 正在输入 (Editing) | 外框带虚线边框，输入焦点聚焦，字符宽度自适应 | SwiftUI `AnnotationShapeView` |
| ShapeAnnotationView | 选中激活态 (Selected) | 图形外围包裹蓝色虚线边框，并浮现 8 个白色拖动控制点 | SwiftUI `AnnotationCanvasLayer` |

## 边界条件 / 失败模式

- **工具栏防溢出 (Screen Bounds Guard)**：动态测量工具栏位置。当选区靠近屏幕最左、最右或底部时，工具栏位置自动平移/避让，确保其**任何部分都不会被裁剪在屏幕可视区域之外**。
- **宽度越界换行**：文本宽度限制为 `min(选区宽, 屏幕宽 - startPoint.x - padding)`。

## 引用

- **组件**：
  - `Sources/Screenshot/UI/AnnotationRootView.swift`
  - `Sources/Screenshot/UI/OverlayWindow.swift` (UnifiedToolbarView, 边缘避让算法)
- **ADR**：[ADR-0002](file:///Users/zerohsueh/Gemini/screenshot/.agent/adr/0002-annotations-serialization.md)
- **原则**：P3, P4
