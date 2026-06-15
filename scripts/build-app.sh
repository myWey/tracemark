#!/bin/bash
# scripts/build-app.sh
# 自动编译 Swift SPM 二进制并打包为 macOS .app 格式

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

# 0. 终止正在运行的旧版进程，防止覆盖文件时被占用导致编译卡死
echo "⏳ 正在检查并清除旧的 TraceMark 进程..."
pkill -x "TraceMark" || true

# 清理旧的编译产物，防止 SwiftPM 缓存定位到旧二进制
echo "🧹 正在清理旧的编译二进制文件..."
find .build -type f -name "TraceMark" -delete 2>/dev/null || true

echo "========================================"
echo "🚧 [build-app] 开始编译 Swift 可执行程序..."
echo "========================================"

# 1. 运行 swift build 分别构建两种架构
echo "🚧 正在编译 arm64 架构..."
swift build -c release --arch arm64

echo "🚧 正在编译 x86_64 架构..."
swift build -c release --arch x86_64

# 2. 确定编译生成的二进制文件路径并使用 lipo 合并
BIN_ARM64=$(find .build/arm64-apple-macosx -type f -name "TraceMark" ! -path "*/checkouts/*" ! -path "*.dSYM/*" -print0 | xargs -0 ls -t 2>/dev/null | head -n 1 || true)
BIN_X86_64=$(find .build/x86_64-apple-macosx -type f -name "TraceMark" ! -path "*/checkouts/*" ! -path "*.dSYM/*" -print0 | xargs -0 ls -t 2>/dev/null | head -n 1 || true)

if [ -z "${BIN_ARM64}" ] || [ -z "${BIN_X86_64}" ]; then
    echo "❌ 错误: 找不到某一个架构的二进制文件。"
    exit 1
fi

echo "🔄 正在使用 lipo 合并为通用二进制文件 (Universal Binary)..."
lipo -create -output .build/TraceMark_universal "${BIN_ARM64}" "${BIN_X86_64}"
BIN_PATH=".build/TraceMark_universal"

if [ -z "${BIN_PATH}" ] || [ ! -f "${BIN_PATH}" ]; then
    echo "❌ 错误: 找不到编译生成的可执行二进制文件。"
    exit 1
fi

echo "✅ 编译成功: ${BIN_PATH}"

# 3. 创建 .app 目录结构
APP_DIR="build/TraceMark.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "🧹 正在清理旧包并创建新目录结构..."
rm -rf "${APP_DIR}"
rm -rf "build/Screenshot.app" # 强制清理残留的旧版本
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. 移动二进制和拷贝 Info.plist
echo "📦 正在复制二进制文件和 Info.plist..."
cp "${BIN_PATH}" "${MACOS_DIR}/TraceMark"
cp Info.plist "${APP_DIR}/Contents/Info.plist"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/"
fi

# 拷贝资源 bundle (如 Assets 和 lproj)
# Find the bundle inside the specific architecture release folder instead of the universal binary folder
BUNDLE_PATH=$(find .build -type d -name "*.bundle" | grep -E "(TraceMark_TraceMark|TraceMark_Screenshot|Screenshot_Screenshot)\.bundle" | head -n 1 || true)
if [ -n "${BUNDLE_PATH}" ] && [ -d "${BUNDLE_PATH}" ]; then
    echo "📦 找到资源 Bundle: ${BUNDLE_PATH}"
    cp -R "${BUNDLE_PATH}/"* "${RESOURCES_DIR}/"
else
    echo "⚠️ 警告: 未找到资源 Bundle，图标或多语言可能失效。"
fi

# 5. 给整个 .app 进行 ad-hoc 签名（防止 macOS 录屏权限等安全机制失效）
echo "🔒 正在进行签名..."
codesign --force --deep --sign - -i "com.zerohsueh.TraceMark.App" "${APP_DIR}"

echo "========================================"
echo "🎉 [build-app] 打包成功!"
echo "📍 本地路径: ${PROJECT_ROOT}/${APP_DIR}"

# 6. 打包完成
echo "✅ 请使用 dmg 安装包或手动将 TraceMark.app 移入应用程序文件夹中。"
echo "========================================"
