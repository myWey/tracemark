#!/bin/bash
set -e

APP_NAME="TraceMark"
APP_PATH="build/${APP_NAME}.app"
DMG_PATH="build/${APP_NAME}.dmg"

echo "📦 开始打包 DMG..."

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到 $APP_PATH，请先运行 build-app.sh"
    exit 1
fi

if [ -f "$DMG_PATH" ]; then
    rm "$DMG_PATH"
fi

echo "🖼️ 正在处理 DMG 背景图片尺寸..."
sips -z 400 640 "/Users/zerohsueh/.gemini/antigravity-ide/brain/d661d8a8-43c7-4bc2-8373-2405d0b7d303/dmg_bg_minimal_dark_arrow_1781407893045.png" --out build/dmg_bg_resized.png

echo "💿 正在使用 appdmg 构建标准的 macOS 安装磁盘映像..."
# 生成 appdmg 的配置 JSON
cat << 'EOF' > build/appdmg.json
{
  "title": "TraceMark",
  "background": "dmg_bg_resized.png",
  "contents": [
    { "x": 160, "y": 180, "type": "file", "path": "TraceMark.app" },
    { "x": 480, "y": 180, "type": "link", "path": "/Applications" }
  ],
  "window": {
    "size": {
      "width": 640,
      "height": 400
    }
  }
}
EOF

# 使用 appdmg 可以自动生成带引导界面、Applications 快捷方式的漂亮 DMG 且不会强制要求开发者证书
npx --yes appdmg build/appdmg.json "$DMG_PATH"

echo "✅ DMG 打包完成: $DMG_PATH"
