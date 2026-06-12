import SwiftUI

struct MagnifierView: View {
    let baseImage: CGImage
    let hoverPoint: CGPoint
    let scaleFactor: CGFloat
    let onCopyColor: () -> Void
    
    // Settings
    let magnifierSize: CGFloat = 110
    let zoomLevel: CGFloat = 3.0
    
    @State private var hexString: String = ""
    @State private var rgbString: String = ""
    @State private var croppedImage: CGImage? = nil
    @State private var keyMonitor: Any? = nil
    
    var body: some View {
        VStack(spacing: 6) {
            // Magnifier Circle
            ZStack {
                if let cgImage = croppedImage {
                    Image(decorative: cgImage, scale: scaleFactor)
                        .resizable()
                        .interpolation(.none) // 取消抗锯齿，显示马赛克/像素格
                        .frame(width: magnifierSize, height: magnifierSize)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: magnifierSize, height: magnifierSize)
                }
                
                // Crosshair
                Path { path in
                    path.move(to: CGPoint(x: magnifierSize / 2, y: 0))
                    path.addLine(to: CGPoint(x: magnifierSize / 2, y: magnifierSize))
                    path.move(to: CGPoint(x: 0, y: magnifierSize / 2))
                    path.addLine(to: CGPoint(x: magnifierSize, y: magnifierSize / 2))
                }
                .stroke(Color.green, lineWidth: 1)
                .frame(width: magnifierSize, height: magnifierSize)
                
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: magnifierSize, height: magnifierSize)
                    .shadow(color: .black.opacity(0.3), radius: 3)
            }
            
            // Info panel
            VStack(spacing: 4) {
                HStack {
                    Text("X: \(Int(hoverPoint.x))")
                    Spacer()
                    Text("Y: \(Int(hoverPoint.y))")
                }
                HStack {
                    Text("HEX:")
                    Spacer()
                    Text(hexString)
                }
                HStack {
                    Text("RGB:")
                    Spacer()
                    Text(rgbString)
                }
                Text(LanguageManager.shared.localizedString(forKey: "按 ⌘C 复制颜色"))
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .padding(.top, 2)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white)
            .padding(8)
            .frame(width: magnifierSize + 30)
            .background(Color.black.opacity(0.75))
            .cornerRadius(8)
        }
        .onChange(of: hoverPoint) { _ in
            updateMagnifier()
        }
        .onAppear {
            updateMagnifier()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // keyCode 8 is 'C' or 'c', require Command modifier
                if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hexString, forType: .string)
                    NSSound(named: "Glass")?.play()
                    
                    DispatchQueue.main.async {
                        ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "色值已复制到剪贴板"))
                        onCopyColor()
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
    
    private func updateMagnifier() {
        // Source crop rect (in pixels)
        let pointX = hoverPoint.x * scaleFactor
        let pointY = hoverPoint.y * scaleFactor
        
        let cropPixels = (magnifierSize * scaleFactor) / zoomLevel
        
        let rect = CGRect(
            x: pointX - cropPixels / 2,
            y: pointY - cropPixels / 2,
            width: cropPixels,
            height: cropPixels
        )
        
        if let cropped = baseImage.cropping(to: rect) {
            self.croppedImage = cropped
        }
        
        // Extract center pixel color
        if let color = getColor(from: baseImage, at: CGPoint(x: pointX, y: pointY)) {
            let r = Int(color.redComponent * 255)
            let g = Int(color.greenComponent * 255)
            let b = Int(color.blueComponent * 255)
            
            self.hexString = String(format: "#%02X%02X%02X", r, g, b)
            self.rgbString = "(\(r), \(g), \(b))"
        }
    }
    
    private func getColor(from image: CGImage, at point: CGPoint) -> NSColor? {
        let x = Int(point.x)
        let y = Int(point.y)
        
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        
        let rect = CGRect(x: x, y: y, width: 1, height: 1)
        guard let cropped = image.cropping(to: rect) else { return nil }
        
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixel,
                                width: 1,
                                height: 1,
                                bitsPerComponent: 8,
                                bytesPerRow: 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        let a = CGFloat(pixel[3]) / 255.0
        
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}
