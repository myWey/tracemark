import Cocoa
import UniformTypeIdentifiers

public struct ScreenCapture {
    public let screen: NSScreen
    public let image: CGImage
}

public class CaptureEngine {
    public static let shared = CaptureEngine()
    
    private init() {}
    
    /// 检查并请求屏幕录制权限
    @discardableResult
    public func checkScreenCapturePermission() -> Bool {
        if #available(macOS 11.0, *) {
            let hasAccess = CGPreflightScreenCaptureAccess()
            if !hasAccess {
                print("⚠️ [CaptureEngine] 未检测到屏幕录制权限，正在向系统请求权限...")
                CGRequestScreenCaptureAccess()
                return false
            }
            return true
        }
        return true
    }
    
    /// 捕获当前所有屏幕的全屏画面
    public func captureAllScreens() -> [ScreenCapture] {
        let hasPermission = checkScreenCapturePermission()
        guard hasPermission else {
            print("❌ [CaptureEngine] 缺少屏幕录制权限，中止截屏逻辑以免引发清屏现象。")
            return []
        }
        
        var captures: [ScreenCapture] = []
        
        for screen in NSScreen.screens {
            // 获取 DisplayID
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = screenNumber.uint32Value
            
            // 抓取该显示器的全屏 CGImage
            if let image = CGDisplayCreateImage(displayID) {
                captures.append(ScreenCapture(screen: screen, image: image))
            } else {
                print("⚠️ [CaptureEngine] CGDisplayCreateImage 失败, 尝试使用 CGWindowListCreateImage 作为后备, DisplayID: \(displayID)")
                // 降级方案：使用 CGWindowListCreateImage 捕获该屏幕的区域
                let rect = screen.frame
                // CGWindowListCreateImage 使用的是 CoreGraphics 的坐标系（原点在左上角），而 NSScreen.frame 是 AppKit 坐标系（原点在左下角）。
                // 对于截取全屏画面，一般传入屏幕的 bounds
                let cgRect = CGRect(x: rect.origin.x, y: NSScreen.screens.first!.frame.height - rect.origin.y - rect.height, width: rect.width, height: rect.height)
                
                if let fallbackImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution) {
                    captures.append(ScreenCapture(screen: screen, image: fallbackImage))
                    print("✅ [CaptureEngine] 后备方案捕获成功")
                } else {
                    print("❌ [CaptureEngine] 后备方案也失败了")
                }
            }
        }
        
        return captures
    }
    
    /// 根据用户在屏幕 SwiftUI 坐标系（左上角为原点，Points 为单位）下的选区进行像素级裁剪
    public func cropImage(capture: ScreenCapture, rect: CGRect) -> CGImage? {
        let scale = capture.screen.backingScaleFactor
        
        // 1. 将 Points 坐标转换为实际像素（Pixel）坐标
        let pixelX = rect.origin.x * scale
        let pixelY = rect.origin.y * scale
        let pixelWidth = rect.size.width * scale
        let pixelHeight = rect.size.height * scale
        
        let pixelRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
        
        // 2. 使用 CGImage 进行裁剪
        guard let cropped = capture.image.cropping(to: pixelRect) else {
            print("❌ [CaptureEngine] 图像裁剪失败, pixelRect: \(pixelRect)")
            return nil
        }
        
        return cropped
    }
    
    /// 将 CGImage 保存为本地 PNG 文件，并支持保存原始未标注图与标注数据，返回文件保存的路径 URL
    @discardableResult
    public func saveToDisk(
        image: CGImage,
        originalImage: CGImage? = nil,
        fileName: String = "Screenshot",
        annotations: [AnnotationItem]? = nil
    ) -> URL? {
        // 使用 HistoryManager 生成保存路径
        let (fileURL, generatedFileName) = HistoryManager.shared.generateNextFileURL(prefix: fileName)
        
        // 创建 PNG 图像目的地 (最终有标注的预览图)
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("❌ [CaptureEngine] 无法创建图片写入目的地")
            return nil
        }
        
        CGImageDestinationAddImage(destination, image, nil)
        
        if CGImageDestinationFinalize(destination) {
            print("💾 [CaptureEngine] 截图成功保存至本地历史: \(fileURL.path)")
            
            // 保存原始未标注图 _original.png
            let origImageToSave = originalImage ?? image
            let originalFileName = generatedFileName.replacingOccurrences(of: ".png", with: "_original.png")
            let originalFileURL = HistoryManager.shared.fileURL(for: originalFileName)
            if let origDest = CGImageDestinationCreateWithURL(originalFileURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(origDest, origImageToSave, nil)
                CGImageDestinationFinalize(origDest)
                print("💾 [CaptureEngine] 原始未标注图已保存至: \(originalFileURL.path)")
            }
            
            // 获取文件大小
            var fileSize: Int64 = 0
            if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attr[.size] as? Int64 {
                fileSize = size
            }
            
            // 写入历史记录记录，并绑定标注
            HistoryManager.shared.addRecord(fileName: generatedFileName, fileSize: fileSize, annotations: annotations)
            
            return fileURL
        } else {
            print("❌ [CaptureEngine] 保存图片到磁盘失败")
            return nil
        }
    }

    /// 将 CGImage 编码为 PNG Data，使用 CGImageDestination 以保留 alpha 通道
    public func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            print("❌ [CaptureEngine] 无法创建 PNG 数据目的地")
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            print("❌ [CaptureEngine] PNG 数据编码失败")
            return nil
        }
        return data as Data
    }
}
