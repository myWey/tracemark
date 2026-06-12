import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImageEffectView: View {
    let type: AnnotationToolType
    let rect: CGRect
    let baseImage: CGImage?
    let displaySize: CGSize?
    
    @State private var processedImage: NSImage?
    
    var body: some View {
        Group {
            if let img = processedImage {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            } else {
                // 占位
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .onAppear {
            processImage()
        }
        .onChange(of: rect) { _ in
            processImage()
        }
    }
    
    private func processImage() {
        guard let cgImage = baseImage, let size = displaySize, rect.width > 0, rect.height > 0 else { return }
        
        let scaleX = CGFloat(cgImage.width) / size.width
        let scaleY = CGFloat(cgImage.height) / size.height
        
        // UIKit/AppKit coordinate (0,0 at bottom-left in CoreGraphics vs top-left in SwiftUI)
        // SwiftUI rect origin is top-left
        let cropRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        
        guard let cropped = cgImage.cropping(to: cropRect) else { return }
        
        let ciImage = CIImage(cgImage: cropped)
        let context = CIContext()
        var outputImage: CIImage?
        
        if type == .blur {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciImage.clampedToExtent()
            // Scale blur radius based on rect size so it looks consistent
            filter.radius = Float(max(10, min(rect.width, rect.height) * 0.1))
            outputImage = filter.outputImage?.cropped(to: ciImage.extent)
        } else if type == .mosaic {
            // 1. 先高斯模糊，彻底打散文字与图像边缘特征
            let blurFilter = CIFilter.gaussianBlur()
            blurFilter.inputImage = ciImage.clampedToExtent()
            blurFilter.radius = Float(max(8, min(rect.width, rect.height) * 0.08))
            
            // 2. 去色为黑白灰，防止原图周围鲜艳颜色暴露特征
            let colorFilter = CIFilter.colorControls()
            colorFilter.inputImage = blurFilter.outputImage?.cropped(to: ciImage.extent)
            colorFilter.saturation = 0.0
            
            // 3. 最后执行大比例尺的马赛克像素化
            let pixellateFilter = CIFilter.pixellate()
            pixellateFilter.inputImage = colorFilter.outputImage?.cropped(to: ciImage.extent)
            pixellateFilter.scale = Float(max(15, min(rect.width, rect.height) * 0.12))
            
            outputImage = pixellateFilter.outputImage?.cropped(to: ciImage.extent)
        }
        
        if let out = outputImage, let resultCGImage = context.createCGImage(out, from: out.extent) {
            self.processedImage = NSImage(cgImage: resultCGImage, size: rect.size)
        }
    }
}
