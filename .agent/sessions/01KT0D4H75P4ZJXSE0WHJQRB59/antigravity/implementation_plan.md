# 标注功能与贴图历史交互体验深度优化方案 (V4)

本方案针对用户反馈的 5 个深层交互问题与 Bug（贴图无法置顶/居中不合理、隐藏撤销按钮拦截关闭、序号无法选中删除、文字工具首次聚焦失败、光标样式异常且出界不恢复）进行体系化修复。

## 1. 目标描述与背景

1. **贴图右上角停驻与强制置顶 (PinWindow)**：
   - 在未传入 `rect`（例如从历史记录或重新编辑画布中 Pin 贴图）时，默认计算屏幕右上角的坐标，并留出适当边距（如顶和右各 40pt），使用 count-based offset 避免完全重合。
   - 在 `PinManager` 的 `pin` 流程中，除了 `makeKeyAndOrderFront` 外，强力加入 `panel.orderFrontRegardless()`，确保贴图无条件漂浮在最前面，不被前台活跃应用遮挡。
2. **阻断隐藏快捷键 Button 拦截鼠标点击 (Close Button Bug)**：
   - 目前在 `AnnotationRootView.swift` 和 `OverlayWindow.swift` 中，为了注册键盘快捷键（Cmd+Z / Cmd+Shift+Z）定义了隐藏按钮 `Button("") { undo() }` 和 `Button("") { redo() }`。由于只设置了 `.opacity(0)`，它们仍参与布局并拦截鼠标事件，恰好挡住了顶部的关闭按钮，导致关闭无响应且闪烁撤销 icon。
   - 修复：对这些隐藏 Button 补充 `.allowsHitTesting(false)` 并限制 `.frame(width: 0, height: 0)`。
3. **支持序号选中与删除 (Counter Selection)**：
   - 在 `AnnotationModels.swift` 中，当 `type == .counter` 时，其 `startPoint` 和 `endPoint` 重合，计算出的 `rect` 宽高为 0，导致点击碰撞检测 `rect.contains(point)` 永远为 false。
   - 修复：在 `AnnotationItem.rect` 的 getter 中，针对 `.counter` 特殊处理，返回一个以 `endPoint` 为中心、边长为 `fontSize * 1.5`（即其圆圈直径）的正方形。
4. **文字/带序号文字首次聚焦失败 (Text Tool Focus Deadlock)**：
   - 当点击文字工具首次创建文字时，如果当前窗口并非系统 Key Window（在刚打开或后台常驻激活时经常发生），TextField 将无法获取第一响应者焦点。而通过其他画笔工具拖动时，鼠标拖拽会激活窗口，因此后续点击才正常。
   - 修复：在 `AnnotationRootView.swift` 中的 `handleDragStart` 点击文本工具创建 `textItem` 前，通过 `NSApp.windows` 找到当前的 `AnnotationWindow` 并调用 `makeKey()` 强行将其设定为系统的键盘输入窗口。
5. **Photoshop 级别画笔光标与出界恢复 (Cursor Tracking & Clear)**：
   - 原生十字「+」光标与自定义圆圈同时出现：是因为在鼠标移动时 `handleHover` 中误用了 `NSCursor.crosshair.push()`，它会覆盖 `TrackingNSView` 设置的透明光标。
   - 移出窗口或在工具栏上时十字光标不恢复：是因为频繁使用 `.push()` 且未配对 `.pop()` 导致光标栈溢出。
   - 修复：
     - 将 `handleHover` 中的所有 `.push()` 统一替换为 `.set()`，移出时依靠 `mouseExited` 中的 `NSCursor.arrow.set()` 完美重置为箭头。
     - 如果当前是画笔/涂抹工具（pencil / highlighter / blur / mosaic），在没有命中已有标注时，将光标设为 `NSCursor.transparent.set()`，从而隐藏十字「+」。
     - 优化圆形光标样式：采用 ZStack 叠合 1.5pt 宽的黑色环和 0.8pt 宽的白色环，实现黑白高对比度圆环。
     - 画笔光标大小映射：pencil 映射为 `selectedSize / 4.0`；highlighter/blur/mosaic 映射为 `max(20.0, lw * 2.0)`，并乘以画布当前的 `scale` 缩放率。

---

## 2. Proposed Changes

### [Annotation & Core Layer]

#### [MODIFY] [AnnotationModels.swift](file:///Users/zerohsueh/Gemini/screenshot/Sources/Screenshot/Annotation/AnnotationModels.swift)
- 优化 `AnnotationItem.rect` 的 getter 方法，为 `.counter` 计算出对应的正方形 Bounding Box。

### [UI Layer - Rendering & Interactions]

#### [MODIFY] [AnnotationRootView.swift](file:///Users/zerohsueh/Gemini/screenshot/Sources/Screenshot/UI/AnnotationRootView.swift)
- 更新 `handleDragStart`：新建文本前，强行将所在 `AnnotationWindow` 设置为 Key 窗口。
- 修复隐藏按钮：在快捷键按钮上添加 `.allowsHitTesting(false)` 和 `.frame(width: 0, height: 0)`。
- 优化 `handleHover`：将所有的 `.push()` 替换为 `.set()`。如果是涂抹工具，设置透明光标 `NSCursor.transparent.set()`。
- 优化 PSD 画笔圆形光标：改用黑白双色环，修正圆圈大小使其与实际渲染笔触完美对应。

#### [MODIFY] [OverlayWindow.swift](file:///Users/zerohsueh/Gemini/screenshot/Sources/Screenshot/UI/OverlayWindow.swift)
- 修复隐藏按钮：添加 `.allowsHitTesting(false)` 和 `.frame(width: 0, height: 0)`。
- 优化 `handleHover` ：将所有的 `.push()` 替换为 `.set()`。如果是涂抹工具，设置透明光标 `NSCursor.transparent.set()`。
- 优化 PSD 画笔圆形光标：采用黑白双色环，修正圆圈大小使其与实际渲染笔触完美对应。

#### [MODIFY] [PinWindow.swift](file:///Users/zerohsueh/Gemini/screenshot/Sources/Screenshot/UI/PinWindow.swift)
- 修改 `PinManager.pin` 默认坐标计算逻辑：如果没有传入 `rect`，默认停靠在主屏幕的右上角（右边距 40pt，顶边距 40pt），使用 count-based 动态偏移防重叠。
- 强制最前：添加 `panel.orderFrontRegardless()` 保证贴图无论在何时何地都能强制最前置顶。

---

## 3. Verification Plan

### Manual Verification
1. **验证贴图位置与置顶**：
   - 在重新编辑画布里点击“Pin”，验证生成的贴图是否默认贴在屏幕 of 右上角。
   - 切换到其他应用（如 Safari 或 IDE），点击其他位置，验证贴图窗口是否仍然维持在所有窗口的上方，没有沉底。
2. **验证重新编辑窗口关闭**：
   - 打开重新编辑窗口，直接多次点击顶部的“关闭”按钮（或右上角的关闭按钮），验证窗口是否能够瞬间关闭，没有任何延迟，且不再闪烁撤销 icon。
3. **验证序号选中与删除**：
   - 在画布上点击贴上一个或多个序号（1、2、3），点击切换到“选择”工具（箭头或默认手势），验证是否可以通过鼠标点击这些序号选中它们（选中时应该出现编辑框），并且按下 Delete 键（Backspace）能够将它们成功删除。
4. **验证文本聚焦**：
   - 刚刚打开重新编辑窗口后，第一步操作直接点击“文本”或“待序号文本”工具，在画布空白处点击，验证是否能够秒聚焦并弹出 TextField 及键盘，可以直接输入。
5. **验证光标与画笔圆圈**：
   - 切换到画笔、荧光笔、模糊、马赛克工具：
     - 移动到画布内，验证十字「+」是否完全消失，只留下一个精美的黑白相间画笔圈。
     - 更改笔触粗细，验证圆形画笔圈的直径是否跟着同步变大或变小，且大小与涂抹出的笔画宽度完全契合。
     - 移动鼠标到画布外（如左侧工具栏、系统菜单栏），验证光标是否立刻恢复为常规的鼠标箭头，没有任何残余的「+」。
