---
id: flow-004
slug: ocr-and-image-translation
status: proposed
supersedes: []
superseded-by: null
epoch: epoch-0
related-adrs: ["adr-0003"]
related-specs: []
---

# FLOW-004: OCR文字识别与图像一键翻译流程

> 用户对截图区域内的文字进行智能识别、框选复制，或一键替换为翻译后的多国语言文本。

## 入口

- **截图编辑工具栏**：在截图后的编辑工具栏中，点击 "OCR" 按钮（使用 `text.viewfinder` 图标）。
- **右键菜单/快捷键**：选中历史记录截图后，在右键菜单或侧边栏点击 "识别文本"。

## 路径（步骤）

1. **触发识别** —— 用户在截图编辑界面点击工具栏的 "OCR" 按钮。
   - 界面进入 `OCR Loading` 状态，当前截图区域上覆盖一层微光扫描动画（Shimmer/Scanner effect）并显示加载提示。
2. **文本区域高亮展示** —— 识别完成后，系统识别出的所有文本块以半透明高亮框（Text Blocks Overlay）覆盖在截图的对应位置。
   - 顶部/侧边显示工具浮条，包含：`复制全部`、`一键翻译`、`退出OCR`。
   - 关键交互：用户可以直接用鼠标在截图上像选择普通文本一样进行“拖拽划选”或“双击选中”，只复制特定段落或单词。
3. **选择目标语言** —— 当用户点击 "一键翻译" 时，若系统未下载对应语言包，会弹出目标语言选择菜单（如 `中文 -> 英文`、`英文 -> 中文`）。
4. **一键翻译与就地替换** —— 确认语言后，进入 `Translation Loading` 状态。翻译成功后：
   - 翻译文本将以几乎相同的排版（背景底色智能擦除、相近字号与颜色）直接替换原本截图上的文字（就地图片翻译）。
   - 用户也可以切换为“对照视图”：左边原文，右边译文。

## 交互态矩阵

| 页面/组件 | 交互态 | 视觉参考 | 状态机 |
|---|---|---|---|
| 编辑画布 | OCR Loading (扫描中) | 微光扫描动画覆盖截图 | `states/ocr.machine` |
| 编辑画布 | OCR Result (识别完毕) | 高亮划选框叠层，显示文字选择光标 | `states/ocr.machine` |
| 编辑画布 | Translation Loading (翻译中) | 文字高亮框闪烁加载态 | `states/translation.machine` |
| 编辑画布 | Translation Result (翻译结果) | 译文原位覆盖，或双栏对照卡片 | `states/translation.machine` |

## 边界条件 / 失败模式

- **无文本识别到 (Empty State)**：如果 Vision 框架返回零结果，退出 OCR 状态，并显示 Toast 提示 `“未在当前区域识别到文本”`。
- **首次下载语言包**：如果 Translation 框架检测到需要下载离线语言包，调用系统级下载，显示进度提示。
- **识别区域极小**：如果用户选择的划选区域太小，自动放大至最小可识别尺寸，避免文字过小导致无法触达。

## 引用

- **组件**：`Sources/Screenshot/UI/AnnotationRootView.swift`
- **服务**：`Sources/Screenshot/Services/OCRService.swift`
- **服务**：`Sources/Screenshot/Services/TranslationService.swift`
- **ADR**：`ADR-0003`
- **原则**：`P1` (本地隐私第一)、`P3` (零摩擦交互)

## 不在范围内（out of scope）

- **手写体高精度识别**：仅依赖 Vision 原生模型，不做专业级手写体模型训练。
- **云端翻译引擎集成**：第一版仅支持系统原生 Translation 框架，暂不开放自定义云端 API 密钥。

## 验收

- **视觉**：OCR Loading 的微光扫描特效足够平滑流畅，文字高亮选择框的边界与其下方的像素文字对齐精准。
- **行为**：双击文字块能选中对应的单词，拖拽可连续选择文本，复制到剪贴板后的文本不带乱码。
- **体验**：全程无弹窗广告或联网鉴权等待，保持极简极速。
