import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 模糊/马赛克效果的共享参数，确保实时绘制与导出一致
enum EffectConfig {
    static let blurRadius = 8.0
    static let mosaicBlockSize = 8
}

/// 同步将 blur/mosaic 画笔效果绘制到 CGImage 上。
/// 导出时使用，避免 SwiftUI ImageRenderer 无法等待 BlurMosaicLiveView 异步加载。
/// 与显示路径完全一致：全图预计算效果 + 笔触 mask blend，保证导出与屏幕显示相同。
func applyBrushEffects(to sourceImage: CGImage, annotations: [AnnotationItem], displaySize: CGSize) -> CGImage? {
    let blurItems = annotations.filter { $0.type == .blur }
    let mosaicItems = annotations.filter { $0.type == .mosaic }
    guard !blurItems.isEmpty || !mosaicItems.isEmpty else { return sourceImage }

    let ciContext = BlurMosaicLiveView.ciContext
    let scaleX = CGFloat(sourceImage.width) / displaySize.width
    let scaleY = CGFloat(sourceImage.height) / displaySize.height
    let avgScale = (scaleX + scaleY) / 2

    var workingImage = CIImage(cgImage: sourceImage)

    // 1. 预计算全图模糊版（如果有 blur 标注）
    var blurredFullImage: CGImage?
    if !blurItems.isEmpty {
        let ciImage = CIImage(cgImage: sourceImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage.clampedToExtent()
        filter.radius = Float(EffectConfig.blurRadius)
        if let out = filter.outputImage {
            blurredFullImage = ciContext.createCGImage(out, from: ciImage.extent)
        }
    }

    // 2. 预计算全图马赛克版（如果有 mosaic 标注）
    var mosaicFullImage: CGImage?
    if !mosaicItems.isEmpty {
        mosaicFullImage = createMosaicCGImage(sourceImage, blockSize: EffectConfig.mosaicBlockSize)
    }

    // 3. 对每个标注，用笔触 mask blend 效果图到全图
    for item in annotations {
        guard let points = item.points, points.count > 1 else { continue }

        let effectCGImage: CGImage?
        if item.type == .blur {
            effectCGImage = blurredFullImage
        } else if item.type == .mosaic {
            effectCGImage = mosaicFullImage
        } else {
            continue
        }
        guard let effectCG = effectCGImage else { continue }

        // 构建全图尺寸的笔触 mask（白色笔触，黑色背景）
        let maskWidth = sourceImage.width
        let maskHeight = sourceImage.height
        guard let maskCG = CGContext(
            data: nil,
            width: maskWidth,
            height: maskHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { continue }

        maskCG.setFillColor(gray: 0, alpha: 1)
        maskCG.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))
        maskCG.setStrokeColor(gray: 1, alpha: 1)
        maskCG.setLineWidth(item.lineWidth * avgScale)
        maskCG.setLineCap(.round)
        maskCG.setLineJoin(.round)

        // 笔触点从 SwiftUI 坐标（左上原点）转换到 CG 坐标（左下原点）
        let cgPoints = points.map { CGPoint(
            x: $0.x * scaleX,
            y: (displaySize.height - $0.y) * scaleY
        ) }

        maskCG.move(to: cgPoints[0])
        for i in 1..<cgPoints.count {
            maskCG.addLine(to: cgPoints[i])
        }
        maskCG.strokePath()

        guard let maskImage = maskCG.makeImage() else { continue }
        let maskCI = CIImage(cgImage: maskImage)
        let effectCI = CIImage(cgImage: effectCG)

        // 用 mask blend：笔触区域显示效果图，其余显示原图
        let blend = CIFilter.blendWithMask()
        blend.inputImage = effectCI
        blend.backgroundImage = workingImage
        blend.maskImage = maskCI

        if let output = blend.outputImage {
            workingImage = output
        }
    }

    return ciContext.createCGImage(workingImage, from: workingImage.extent)
}
