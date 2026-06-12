# 标注画布与贴图交互遗留 5 大 Bug 修复任务

## 任务列表

- [x] **任务 1：修复贴图右上角停驻与强制置顶**
  - [x] 修改 `PinWindow.swift` 的默认坐标计算：在 `rect == nil` 时，将贴图默认放在主屏幕 of 右上角，并加上基于 count 的动态偏移。
  - [x] 在 `PinManager.pin` 中，调用 `panel.orderFrontRegardless()` 确保其强制在所有应用最前置顶。
- [x] **任务 2：修复关闭按钮被隐藏快捷键 Button 拦截的问题**
  - [x] 修改 `AnnotationRootView.swift` 中的隐藏撤销重做按钮：添加 `.allowsHitTesting(false)` 和 `.frame(width: 0, height: 0)`。
  - [x] 修改 `OverlayWindow.swift` 中的隐藏撤销重做按钮：添加 `.allowsHitTesting(false)` 和 `.frame(width: 0, height: 0)`。
- [x] **任务 3：修复序号 (Counter) 无法选中和删除的问题**
  - [x] 修改 `AnnotationModels.swift` 中的 `AnnotationItem.rect` 的 getter：为 `.counter` 计算出以 `endPoint` 为中心、直径为 `fontSize * 1.5` 的正方形。
- [x] **任务 4：修复刚进入编辑界面点击文本工具无法激活编辑的 Bug**
  - [x] 在 `AnnotationRootView.swift` 的 `handleDragStart` 点击文本工具创建 `textItem` 前，调用 `makeKey()` 强行激活当前的 `AnnotationWindow` 确保其成为 Key 窗口。
- [x] **任务 5：修复光标跟着「+」以及出界、大小、样式等问题**
  - [x] 在 `AnnotationRootView.swift` 的 `handleHover` 中，将所有的 `.push()` 替换为 `.set()`。
  - [x] 在 `OverlayWindow.swift` 的 `handleHover` 中，将所有的 `.push()` 替换为 `.set()`。
  - [x] 针对涂抹工具（pencil / highlighter / blur / mosaic）若未命中其他元素，则直接调用 `NSCursor.transparent.set()`，从而隐藏十字「+」光标。
  - [x] 优化圆形画笔光标的大小计算，使 `pencil` 对应 `lw`，`highlighter`/`blur`/`mosaic` 对应 `max(20.0, lw * 2.0)`，且在画布中乘上 `scale`。
  - [x] 优化圆形光标的样式为黑白相间：使用 1.5pt 宽的黑色 Circle 与 0.8pt 宽的白色 Circle 叠合。
- [x] **任务 6：构建与手动验证**
  - [x] 编译应用，检查是否有编译错误。
  - [x] 执行完整的 5 项 Bug 验证，确认无误。
