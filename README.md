# TraceMark

[English](README.md) | [简体中文](README_zh.md) | [繁體中文](README_zh-Hant.md) | [日本語](README_ja.md) | [한국어](README_ko.md)

TraceMark is an efficient, lightweight, system-level screenshot and annotation tool built for macOS (macOS 13 and above). It helps you quickly make clear and organized annotations based on your screenshots.

## ✨ Core Features

- **Recommended Features**:
  - 💬 **Numbered Text (Callouts)**: Automatically incrementing numbers with freely draggable callout text boxes, making step-by-step instructions clear and highly readable.
  - **History Dashboard**: Supports re-editing of historical screenshots and annotations, avoiding the need to retake screenshots for minor detail tweaks. Historical screenshots can also be pinned to the desktop for easy reference.
  - **OCR (Optical Character Recognition)**: Extract text from screenshots instantly.
  - **Translation**: One-click translation (macOS 14.4 and above only).
  - Multi-language support (i18n): Natively supports English, Chinese, Japanese, and Korean interfaces.

- **Rich Annotation Tools**:
  - 🖌️ **Brush & Highlight**: Freehand drawing and text highlighting.
  - 📏 **Shapes**: Standardized shapes including rectangles, ellipses, and arrows.
  - 💧 **Mosaic & Blur**: Essential tools for protecting privacy and sensitive data.
  - **Global Shortcut**: Customizable global shortcut to instantly freeze the screen.

## 📥 Installation Guide

> ⚠️ **Note**: Since the current version does not yet have an Apple Developer signature, macOS's default Gatekeeper mechanism will block apps from unidentified developers. Please follow the steps below to authorize and run the app.

### Download & Install
1. Go to the [Releases](#) page of this repository and download the latest `TraceMark.dmg`.
2. Open the DMG file and drag `TraceMark.app` into your **Applications** folder.

### Bypass Gatekeeper (Installation Must-Read)

If you encounter a "TraceMark is damaged and can't be opened" or "Unidentified developer" prompt, the most effective way is to remove the quarantine attribute using the Terminal.

**Step-by-step Instructions:**
1. Open the **Terminal** app (you can find it using Spotlight search `Cmd + Space` and typing "Terminal").
2. Copy and paste the following command into the Terminal:
   ```bash
   sudo xattr -rd com.apple.quarantine /Applications/TraceMark.app
   ```
3. Press **Enter**.
4. The Terminal will prompt you for a `Password:`. Type your Mac login password (note: no characters will show up as you type, this is normal).
5. Press **Enter** again.
6. Done! You can now double-click to open TraceMark from your Applications folder normally.

### Permissions Guide (First Run)

To ensure TraceMark functions properly, the system needs to acquire necessary permissions upon first launch. When you run TraceMark for the first time, the system will automatically prompt you for authorization:

1. **Screen Recording (Required)**: Used to capture screen images. Click "Open System Settings" in the prompt, find TraceMark, and toggle it on.
2. **Accessibility (Recommended)**: Used to listen for global hotkeys. Click "Open System Settings" in the prompt, find TraceMark, and toggle it on.

> If you accidentally deny the prompts, you can always manually enable them later by going to System Settings > Privacy & Security.

### Customizing Shortcuts

TraceMark's default screenshot shortcut is `Option + A`. If you find this conflicts with other system shortcuts, you can customize it:

1. After opening TraceMark, click the TraceMark icon in the menu bar (top right of your screen).
2. Select **Preferences...**.
3. In the settings window, locate the "Screenshot Shortcut" option.
4. Click the current shortcut button, then press your desired key combination (e.g., `Cmd + Shift + A` or `Control + Cmd + A`).
5. The new shortcut will take effect immediately.

## 🛠 Development & Build

If you wish to build TraceMark from source, please ensure you have macOS 13+ and Xcode 14+ installed.

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/TraceMark.git
   cd TraceMark
   ```
2. Build and package the application:
   ```bash
   sh scripts/build-app.sh && sh scripts/build-dmg.sh
   ```
3. The built product will appear at `build/TraceMark.dmg`.

## 📄 License

[MIT License](LICENSE)
