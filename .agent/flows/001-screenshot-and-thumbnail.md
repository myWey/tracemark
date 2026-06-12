---
id: flow-001
slug: screenshot-and-thumbnail
status: active
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
related-adrs: [ADR-0001]
related-specs: [Spec-1]
---

# FLOW-001: 区域截图与悬浮分发流程

> 一句话：用户触发区域截图并利用右下角悬浮窗快速复制、保存或拖拽分发截图的完整闭环。

## 入口

- **全局快捷键**：在任意界面按下 `Control + Command + A` 组合键触发。
- **状态栏图标**：点击 macOS 顶部状态栏（Menu Bar）的摄像头图标 `camera.viewfinder`，在下拉菜单中点击“区域截图”。

## 路径（步骤）

1. **全屏变暗遮罩 (Overlay Canvas)** —— 触发后，所有显示器上瞬间覆盖一层半透明暗色遮罩窗口（45% 不透明度），并将当前的屏幕快照渲染为背景（使用户感觉屏幕被瞬间“冻结”）。
   - **关键交互**：
     - 用户按下鼠标左键开始拖拽：以起点和当前鼠标位置划定一个矩形，该矩形内呈高亮状态（无暗色遮罩覆盖），且在高亮框左上方实时气泡显示 `宽 × 高` 的 points 大小。
     - 用户按下 `Esc` 键：立即取消截图，关闭所有遮罩窗口。
2. **像素抓取与隐藏** —— 用户松开鼠标左键。
   - **判定条件**：
     - 若矩形宽高均大于 `5pt`：系统根据比例换算并像素级裁剪图片，将图片同时暂存到临时目录并默认静默复制一份到 `~/Downloads`。同时播放喀嚓声，瞬间关闭遮罩。进入**步骤 3**。
     - 若宽高小于等于 `5pt`：判定为误触，直接关闭遮罩并退出流程。
3. **右下角悬浮缩略图 (Floating Thumbnail)** —— 截图成功后，屏幕右下角平滑淡入一个无边框、带圆角与平滑阴影的精致图片卡片。
   - **关键交互与交互态**：
     - **Idle 态**：展示截图缩略图，开启 5s 自动淡出倒计时。
     - **Hover 态**：鼠标移入缩略图卡片。暂停 5s 倒计时；卡片上叠加 25% 半透明黑色蒙版，并浮现“复制到剪贴板”、“保存到下载”两个微型圆形按钮，卡片右上角显示“X”关闭按钮。鼠标移开后，重新开启 3s 倒计时。
     - **Drag 态**：鼠标按住缩略图可以直接拖拽出窗口，拖动到 Finder、微信或桌面上释放，系统会自动将图片临时文件分发到对应应用，缩略图窗口瞬间消失。
     - **点击动作**：
       - 点击“复制”：调用剪贴板 API 写入图片，窗口淡出销毁。
       - 点击“保存”：将文件拷贝至 `~/Downloads`，窗口淡出销毁。
       - 点击“X”：窗口淡出销毁。

## 交互态矩阵

| 页面/组件 | 交互态 | 视觉参考 | 状态机 |
|---|---|---|---|
| OverlayWindow | Idle / Selecting / Dragging | 半透明全屏变暗背景 + 镂空选区框 + 尺寸提示 | SwiftUI `OverlayRootView` |
| ThumbnailWindow | Idle (5s 倒计时) | 圆角卡片阴影，展示截图缩略图 | SwiftUI `ThumbnailRootView` |
| ThumbnailWindow | Hover | 蒙版加深，显示“复制”、“保存”与右上角关闭按钮 | SwiftUI `ThumbnailRootView` |
| ThumbnailWindow | Dragging | 系统原生拖拽光标，缩略图可被拖离窗口 | SwiftUI `onDrag` 拖拽源 |

## 边界条件 / 失败模式

- **多屏幕支持**：在有双屏或多屏的 Mac 下，每个屏幕必须同时覆盖独立的遮罩窗口，且截图裁剪出的图片必须是鼠标释放所在的那个屏幕的像素内容。
- **系统录屏权限缺失**：若 macOS 系统的“屏幕录制”授权被用户拒绝，系统截图将捕获到黑屏或空白。我们在 `Info.plist` 中声明 `NSScreenCaptureUsageDescription`。在首次截图发生时，系统会自动向用户申请授权，我们需要优雅提示。
- **Esc 取消**：任何时候按下 `Esc` 均需无条件瞬间清理所有透明窗口和内存，不留痕迹。

## 引用

- **组件**：
  - `Sources/Screenshot/UI/OverlayWindow.swift` (全屏遮罩与手势)
  - `Sources/Screenshot/UI/ThumbnailWindow.swift` (悬浮卡片与交互)
- **核心逻辑**：
  - `Sources/Screenshot/Hotkey/HotkeyManager.swift` (Carbon 热键)
  - `Sources/Screenshot/Capture/CaptureEngine.swift` (Core Graphics 捕捉与裁剪)
- **ADR**：[ADR-0001](file:///Users/zerohsueh/Gemini/screenshot/.agent/adr/0001-foundation.md)
- **原则**：P1 (隐私本地优先), P2 (极简), P3 (零摩擦), P4 (精致视觉), A2 (极低后台开销)

## 不在范围内（out of scope）

- **截图后进入重度编辑画布**：这是 `FLOW-002` (精致标注与画布美化) 的职责，本 Flow 仅负责截图和右下角缩略图分发。
- **长网页滚动拼接**：归到 `FLOW-003` (置顶贴图与长图滚动)。

## 验收

- **视觉**：右下角悬浮缩略图卡片拥有平滑过渡的淡入淡出动画，在 Hover 时按钮过渡自然，整体具有 Apple 官方原生软件的精致感 (符合 P4)。
- **体验**：
  - 截图动作在 Control + Command + A 触发后瞬间唤醒，无卡顿或延迟 (符合 P3 / A2)。
  - 支持直接将右下角缩略图拖拽入微信或 Finder 进行文件流发送 (符合 P3 零摩擦)。
