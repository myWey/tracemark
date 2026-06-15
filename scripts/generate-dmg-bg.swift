#!/usr/bin/swift
import Cocoa

let width: CGFloat = 640
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// Draw white background
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Draw arrow
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 60, weight: .light),
    .foregroundColor: NSColor(white: 0.6, alpha: 1.0),
    .paragraphStyle: paragraphStyle
]

let arrow = "→"
let textSize = arrow.size(withAttributes: attributes)

// 考虑到 appdmg 的图标分别在 x=160 和 x=480，中心在 x=320，y=180 (注意 macOS 坐标系 y 朝上，所以 y = 400 - 180 = 220)
let rect = NSRect(
    x: (width - textSize.width) / 2,
    y: height - 180 - (textSize.height / 2) + 10,
    width: textSize.width,
    height: textSize.height
)
arrow.draw(in: rect, withAttributes: attributes)

image.unlockFocus()

let url = URL(fileURLWithPath: "build/dmg_bg.png")
if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
    if let data = bitmap.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}
print("✅ 成功生成 DMG 背景图: build/dmg_bg.png")
