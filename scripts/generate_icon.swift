import Cocoa

func shell(_ command: String) -> Int32 {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
}

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)

// macOS icon squircle shape
let cornerRadius: CGFloat = 224 // standard for 1024x1024
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

// Set background color
NSColor(white: 0.95, alpha: 1.0).setFill() // slight off-white or just white
path.fill()

// Draw the logo inside
let logoURL = URL(fileURLWithPath: "FYI/tm2.png")
if let logoImage = NSImage(contentsOf: logoURL) {
    // scale logo to fit nicely, maybe 80% of the size
    let logoSize = CGSize(width: 768, height: 768)
    let logoRect = NSRect(
        x: (size.width - logoSize.width) / 2,
        y: (size.height - logoSize.height) / 2,
        width: logoSize.width,
        height: logoSize.height
    )
    
    // Add some shadow to the logo
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    
    logoImage.draw(in: logoRect, from: NSRect(origin: .zero, size: logoImage.size), operation: .sourceOver, fraction: 1.0)
} else {
    print("Failed to load logo image at FYI/tm2.png")
}

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to generate PNG data")
    exit(1)
}

let outURL = URL(fileURLWithPath: "AppIcon_squircle.png")
try? pngData.write(to: outURL)
print("Saved AppIcon_squircle.png")

// Now generate iconset and build
let script = """
mkdir -p icon.iconset
sips -z 16 16 AppIcon_squircle.png --out icon.iconset/icon_16x16.png
sips -z 32 32 AppIcon_squircle.png --out icon.iconset/icon_16x16@2x.png
sips -z 32 32 AppIcon_squircle.png --out icon.iconset/icon_32x32.png
sips -z 64 64 AppIcon_squircle.png --out icon.iconset/icon_32x32@2x.png
sips -z 128 128 AppIcon_squircle.png --out icon.iconset/icon_128x128.png
sips -z 256 256 AppIcon_squircle.png --out icon.iconset/icon_128x128@2x.png
sips -z 256 256 AppIcon_squircle.png --out icon.iconset/icon_256x256.png
sips -z 512 512 AppIcon_squircle.png --out icon.iconset/icon_256x256@2x.png
sips -z 512 512 AppIcon_squircle.png --out icon.iconset/icon_512x512.png
sips -z 1024 1024 AppIcon_squircle.png --out icon.iconset/icon_512x512@2x.png
iconutil -c icns icon.iconset -o AppIcon.icns
bash scripts/build-app.sh
bash scripts/build-dmg.sh
"""
_ = shell(script)
