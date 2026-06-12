---
id: adr-0001
slug: foundation
status: active
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
ratified-retroactively: false
original-decision-time: null
related-flows: []
---

# ADR-0001: Foundation

> 本 ADR 锁定截图工具的初始技术栈与架构分层方案。

## 上下文

我们需要为 macOS 截图工具选定高品质、低开销的开发语言与框架，确保软件在后台安静、极速、并能完美融入 macOS 原生系统交互。

## 决策

- **语言**：Swift
- **前端框架**：SwiftUI + AppKit (用于需要底层窗口交互和菜单控制的场景)
- **状态管理**：Swift 原生 Combine / Observable 机制，构建截图工具的状态流转状态机 (State Machine)
- **后端 / API 风格**：无（纯本地离线运行，遵循 P1 隐私优先）
- **数据库**：无（使用本地磁盘目录、UserDefaults 存储偏好和历史记录）
- **部署**：macOS App (.app / DMG 镜像发行)
- **分层**：
  - `CaptureCore`: 屏幕录制/截图捕获、全局快捷键注册、多屏幕坐标转换。
  - `AnnotationLayer`: SwiftUI 实现的轻量标注绘制画布（包含箭头、马赛克、文字、精美阴影控制等）。
  - `WindowOverlay`: 全屏幕透明遮罩窗口（用于截图时的区域选择绘制）、贴图 Pin 窗口、右下角悬浮缩略图。

## 备选方案

- **Tauri (Rust + React/Vue)**: Web 开发门槛低，但难以完美兼容 macOS 的高阶系统窗口层级交互（如全局快捷键下发、多屏实时坐标捕捉等），性能不如原生，且空载内存稍高。
- **Electron (JS)**: 开发效率高，但空载占用 150MB+ 内存，严重违反 A2 反模式。

## 后果

### 正面

- 起点明确；后续 ADR 可以引用并 supersede。
- 分层是机械的（lint 强制），不是口号。

### 负面 / 代价

- 一些早期选择会是错的。可接受——这就是 supersedes 的意义。

## 影响

- **代码涉及**：`apps/`、`packages/`、`shared/` 的初始 scaffold
- **Schema 涉及**：`shared/schemas/` 初始化
- **Spec 涉及**：无（先于 spec）
- **Flow 涉及**：无
- **ADR 涉及**：本身就是 ADR-0001
- **迁移任务**：无

## 验证

第一个 vertical-slice feature 端到端通过，未触发任何分层违反，未引入未在
glossary 中登记的术语。

## 引用

- 调用了哪些原则：全部（基础性 ADR）
- 相关 ADR：—
- 相关 flow：—
- 相关 spec：—
