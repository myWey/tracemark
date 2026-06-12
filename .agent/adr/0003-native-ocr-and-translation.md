---
id: adr-0003
slug: native-ocr-and-translation
status: proposed
supersedes: []
superseded-by: null
epoch: epoch-0
related-flows: ["flow-004"]
---

# ADR-0003: 调用 macOS 原生 Vision 与 Translation 框架实现 OCR 与翻译

## 上下文（Context）

在完成基础截图与标注交互后，下一个 Spec 要求引入 OCR（文字识别）与图片/文本翻译功能。
该功能需要满足以下核心设计原则：
1. **P1. 本地与隐私优先**：OCR 和翻译应尽量在本地设备上进行，不强制依赖云端服务器，保障用户数据隐私。
2. **P2. 高价值杠杆与极简**：利用 macOS 平台提供的原生强大框架，避免引入庞大的第三方依赖包或复杂的网络 API。
3. **A2. 后台静默运行高开销**：避免引入常驻后台的重量级推理引擎。

## 决策（Decision）

我们决定**完全基于 macOS 原生的系统框架**实现该 Spec 的核心功能：

1. **OCR 文字识别**：使用 Apple 的 **Vision 框架**（`VNRecognizeTextRequest` 和 `VNImageRequestHandler`）。
   - **理由**：自 macOS 10.15 起支持，至 macOS 12+ 已经非常成熟，支持实时多语言本地识别，识别率高，执行速度快，完全本地运行且免费。
2. **文本翻译**：使用 Apple 的 **Translation 框架**（`Translation` 框架，使用 `TranslationSession`）。
   - **理由**：macOS 14+ / iOS 17+ 提供了原生 Translation API，支持完全本地和系统级的多语言翻译，体验原生且速度快，且不产生任何 API 密钥管理或第三方服务计费的麻烦。
3. **交互形式**：
   - 用户在截图编辑区或通过悬浮按钮一键触发 OCR。
   - OCR 识别出的文字支持就地复制、框选、或一键调用系统翻译。
   - 翻译结果可以直接在截图的原位置进行图层替换渲染（图片翻译），或在侧边弹窗展示。

## 备选方案（Alternatives considered）

- **备选 A：集成百度/有道/Google Cloud 等第三方云端 OCR 与翻译 API**
  - *缺点*：违反 **P1 (本地与隐私优先)**，必须联网才能使用；需要用户配置自己的 API Key 或者由我们搭建中转服务器，带来安全、隐私和服务器运行成本风险，增加交互摩擦（违反 P3）。
- **备选 B：本地打包轻量级 OCR 模型（如 EasyOCR 或 Tesseract ONNX）**
  - *缺点*：会显著增加二进制文件体积（数十MB甚至上百MB），加载速度慢，且内存开销巨大，违反 **A2 (后台高开销)**。

## 后果（Consequences）

### 正面

- **绝对的隐私安全**：100% 本地运算，没有任何网络请求发出，完美契合 **P1**。
- **极致的性能和零开销**：Vision 框架利用 Apple Silicon 的 Neural Engine，OCR 识别在 50ms 内完成；空载时零内存占用。
- **完美的系统融合度**：翻译语言包由 macOS 系统级下载和缓存管理，与 Safari 浏览器的翻译体验对齐。
- **免维护性**：不需要维护任何云端账户和收费中转服务。

### 负面 / 代价

- **系统版本限制**：由于原生 Translation 框架在 macOS 14 (Sonoma) 起才提供较好的 Swift API，本项目将最低支持系统锁定在 macOS 14 及以上。
- **语言包下载依赖**：首次翻译非缓存语言时，系统会提示用户下载语言包（由系统弹窗托管，有轻微首次交互摩擦）。

## 影响（Impact）

- **代码涉及**：
  - 新增 `Sources/Screenshot/Services/OCRService.swift`
  - 新增 `Sources/Screenshot/Services/TranslationService.swift`
  - 修改 `Sources/Screenshot/UI/OverlayWindow.swift` 和 `Sources/Screenshot/UI/AnnotationRootView.swift` 引入 OCR 触发按钮。
- **Schema 涉及**：无
- **Spec 涉及**：无
- **Flow 涉及**：
  - 新增 `FLOW-004`
- **ADR 涉及**：无
- **迁移任务**：无

## 验证（Validation）

- **单元测试**：编写 `OCRServiceTests.swift` 传入带文本的测试 CGImage，验证能正确识别出对应的 String。
- **集成测试**：在标注画布中，验证点击 "OCR" 按钮后，能识别出选区内的文本并更新为可复制文本状态。

## 引用

- 调用了哪些原则：`P1`、`P2`、`P3`
- 相关 flow：`FLOW-004`
- 相关 adr：`ADR-0001`
