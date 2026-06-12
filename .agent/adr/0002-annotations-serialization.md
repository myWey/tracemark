---
id: adr-0002
slug: annotations-serialization
status: proposed
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
ratified-retroactively: false
original-decision-time: null
related-flows: [FLOW-003]
---

# ADR-0002: 标注的序列化与历史记录再编辑架构

## 上下文（Context）

当前截图工具生成截图后，用户可以进行标注（画矩形、写字等），完成后图片被合并压制（Flatten）为一张静态 PNG 并存储在历史记录中。由于历史记录中仅保存了最终压制后的图片，导致：
1. 历史截图无法被“再编辑”（已压制的图形无法分离、移动或修改）。
2. 用户写错的字、画偏的箭头在保存后成为不可逆操作，严重影响工作效率（违反原则 P3 零摩擦交互）。

为了实现历史截图的“再编辑”能力，我们必须将标注信息从只读的位图格式升级为可读写的矢量格式，并在本地持久化存储这些标注数据。

## 决策（Decision）

1. **原图与效果图分离存储**：
   - 历史截图生成时，在 `History` 目录下保存两个文件：
     - `Screenshot_yyyyMMdd_HHmmss.png`：压制了最新标注图层的最终预览图。用于 Finder 浏览、拖拽分发和剪贴板复制。
     - `Screenshot_yyyyMMdd_HHmmss_original.png`：干净的原始屏幕快照（无标注）。用于在再编辑时作为纯净的画布背景。
   - 这避免了多次编辑时由于图层多次重叠压制导致的画面模糊，且保证了再编辑是无损的。

2. **标注矢量序列化 (JSON)**：
   - 在 `ScreenshotRecord` 结构体中新增 `annotations: [AnnotationItem]?` 属性。
   - 使 `AnnotationItem` 及其依赖项（`AnnotationToolType`、`TextStyle` 等）遵循 Swift 的 `Codable` 协议。
   - 由于 SwiftUI `Color` 不是原生 `Codable`，设计一个辅助结构体 `CodableColor`：
     ```swift
     struct CodableColor: Codable {
         let red: Double
         let green: Double
         let blue: Double
         let alpha: Double
     }
     ```
     并在 `AnnotationItem` 的 `Codable` 实现中进行双向桥接转换。
   - 所有标注的矢量坐标均已在画布显示比例下标准化，保存到 `metadata.json` 中。

3. **再编辑生命周期**：
   - 用户从历史界面点击“再编辑”时，从 `HistoryManager` 读取对应的 `ScreenshotRecord`，并加载其 `_original.png` 原图和 `annotations` 矢量列表。
   - 启动 `AnnotationRootView`，用户修改标注后点击“完成”：
     - `HistoryManager` 重新压制“原图 + 修正后的标注”并替换覆盖 `Screenshot_yyyyMMdd_HHmmss.png` 预览文件。
     - 更新 `metadata.json` 中的 `annotations` 数据，并保存。
     - 刷新历史界面缩略图。

## 备选方案（Alternatives considered）

- **备选 A：单独的矢量描述文件（如 .json 伴随文件）**
  - *优点*：各个截图独立，删除和移动方便。
  - *缺点*：引入了文件散落问题，历史目录内文件数量加倍，容易不同步。
  - *选择原因*：由于我们已在 `metadata.json` 中集中维护 `[ScreenshotRecord]`，直接在 JSON 字段里存储 `annotations` 更加简单、集中，不会增加新的磁盘文件。

- **备选 B：PSD 或 SVG 格式存储**
  - *优点*：兼容外部编辑器。
  - *缺点*：解析和渲染 PSD/SVG 在原生 SwiftUI/AppKit 中开销巨大，我们并不需要被外部工具编辑，仅需在 App 内部再编辑，因此私有的 JSON 序列化是最轻量（A2）且开发成本最低的。

## 后果（Consequences）

### 正面

- 实现了真正的“无损再编辑”功能，用户随时可以微调历史截图中的某行文本或线条（符合 P3/P4）。
- `metadata.json` 数据自包含，保持了良好的本地隐私性和离线工作的稳定性（符合 P1）。

### 负面 / 代价

- 每个历史截图现在需要存储两个图片文件（原图 + 压制图），磁盘空间开销增加了一倍（对普通截图通常增加几百 KB 至 1MB，在 100 张的额度限制下完全可接受）。
- 数据结构发生变更，需要做好对老版本 `metadata.json`（不含 `annotations` 字段）的向前兼容。

## 影响（Impact）

- **代码涉及**：
  - `Sources/Screenshot/Annotation/AnnotationModels.swift` (实现 Codable 协议)
  - `Sources/Screenshot/History/HistoryManager.swift` (修改数据模型、保存/覆盖逻辑)
  - `Sources/Screenshot/UI/HistoryRootView.swift` (新增“再编辑”按钮及跳转逻辑)
  - `Sources/Screenshot/UI/AnnotationRootView.swift` (适配传入初始标注并回调保存修改)
- **Schema 涉及**：
  - `ScreenshotRecord` schema 新增 `annotations` 可空字段。
- **Spec 涉及**：
  - 更新 `implementation_plan.md`。
- **Flow 涉及**：
  - 新增 `FLOW-003`。
- **ADR 涉及**：
  - 本 ADR-0002。
- **迁移任务**：
  - 在 `HistoryManager` 读取 JSON 时，若没有 `annotations` 字段则默认解析为 `nil`，从而向前兼容老版本的历史记录。

## 验证（Validation）

- 对同一个截图进行 3 次重复编辑，每次修改不同的元素，验证最终保存出来的 PNG 图片不模糊、图层没有二次重叠叠加。
- 退出 App 后重新打开，验证历史记录中上次修改的元素依然保持选中、移动和修改状态。

## 引用（References）

- 调用了哪些原则：P1 (本地优先), P3 (零摩擦), P4 (精致视觉)
- 相关 ADR：ADR-0001
- 相关 flow：FLOW-003
