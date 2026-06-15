#!/bin/bash
# scripts/generate-icon.sh

set -euo pipefail

# 检查参数
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_png>"
    echo "Example: $0 FYI/tm2.png"
    exit 1
fi

SOURCE_IMG="$1"
ICONSET_DIR="AppIcon.iconset"

if [ ! -f "$SOURCE_IMG" ]; then
    echo "Error: Source image not found at $SOURCE_IMG"
    exit 1
fi

echo "🧹 Cleaning old iconset..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

echo "🎨 Generating different sizes..."
sips -z 16 16     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_IMG" --out "$ICONSET_DIR/icon_512x512@2x.png"

echo "📦 Packaging to AppIcon.icns..."
iconutil -c icns "$ICONSET_DIR" -o AppIcon.icns

echo "🧹 Cleaning up intermediate files..."
rm -rf "$ICONSET_DIR"

echo "✅ AppIcon.icns has been successfully generated in the root directory!"
echo "You can now run 'sh scripts/build-app.sh' and the icon will be bundled automatically."
