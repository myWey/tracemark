import Cocoa
import UniformTypeIdentifiers

public struct ScreenshotRecord: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let fileName: String
    public var fileSize: Int64
    public var annotations: [AnnotationItem]?
    
    // 我们只保存文件名，路径由 HistoryManager 动态拼接
}

public class HistoryManager {
    public static let shared = HistoryManager()
    
    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let historyDirURL: URL
    private let metadataURL: URL
    
    public private(set) var records: [ScreenshotRecord] = []
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    private init() {
        // App Sandbox Directory: ~/Library/Application Support/com.zerohsueh.TraceMark.App/History
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // macOS bundle ID defaults to the executable name if not set, but let's use a fixed string
            appSupportURL = appSupport.appendingPathComponent("com.zerohsueh.TraceMark.App")
        } else {
            // Fallback
            appSupportURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".screenshot_history")
        }
        
        historyDirURL = appSupportURL.appendingPathComponent("History")
        metadataURL = historyDirURL.appendingPathComponent("metadata.json")
        
        setupDirectory()
        loadRecords()
    }
    
    private func setupDirectory() {
        if !fileManager.fileExists(atPath: historyDirURL.path) {
            do {
                try fileManager.createDirectory(at: historyDirURL, withIntermediateDirectories: true, attributes: nil)
                print("✅ [HistoryManager] 创建历史记录目录: \(historyDirURL.path)")
            } catch {
                print("❌ [HistoryManager] 创建历史记录目录失败: \(error)")
            }
        }
    }
    
    private func loadRecords() {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            self.records = try decoder.decode([ScreenshotRecord].self, from: data)
        } catch {
            print("⚠️ [HistoryManager] 无法读取元数据: \(error)")
        }
    }
    
    private func saveRecords() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self.records)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("❌ [HistoryManager] 无法保存元数据: \(error)")
        }
    }
    
    /// 提供保存 URL 给 CaptureEngine
    public func generateNextFileURL(prefix: String = "Screenshot") -> (url: URL, fileName: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "\(prefix)_\(timestamp).png"
        let fileURL = historyDirURL.appendingPathComponent(fileName)
        return (fileURL, fileName)
    }
    
    /// 将新截图加入历史记录
    public func addRecord(fileName: String, fileSize: Int64, annotations: [AnnotationItem]? = nil) {
        let newRecord = ScreenshotRecord(id: UUID(), timestamp: Date(), fileName: fileName, fileSize: fileSize, annotations: annotations)
        // 插入到最前面（倒序排列）
        records.insert(newRecord, at: 0)
        
        // 限制最多保留 100 张
        if records.count > 100 {
            let removed = records.removeLast()
            deleteFile(for: removed.fileName)
        }
        
        saveRecords()
        
        // 发送通知，便于界面更新
        NotificationCenter.default.post(name: .HistoryDidUpdate, object: nil)
    }
    
    /// 获取完整的本地文件路径
    public func fileURL(for fileName: String) -> URL {
        return historyDirURL.appendingPathComponent(fileName)
    }
    
    /// 获取优化的缩略图并缓存，防止 LazyVGrid 滚动掉帧
    public func thumbnail(for fileName: String, maxSize: CGFloat = 320) -> NSImage? {
        let cacheKey = "\(fileName)_\(maxSize)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        
        let url = fileURL(for: fileName)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        let thumb = NSImage(cgImage: cgImage, size: .zero)
        thumbnailCache.setObject(thumb, forKey: cacheKey)
        return thumb
    }
    
    /// 获取某条记录的文件 URL (用于拖拽等)
    public func getSavedImageURL(for record: ScreenshotRecord) -> URL {
        return fileURL(for: record.fileName)
    }
    
    /// 删除某条记录
    public func removeRecord(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        deleteFile(for: record.fileName)
        saveRecords()
        
        NotificationCenter.default.post(name: .HistoryDidUpdate, object: nil)
    }
    
    /// 更新已存在的截图记录的标注和压制图
    public func updateRecord(id: UUID, annotations: [AnnotationItem], finalImage: CGImage) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        let fileURL = historyDirURL.appendingPathComponent(record.fileName)
        
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("❌ [HistoryManager] 无法创建图片写入目的地进行更新")
            return
        }
        
        CGImageDestinationAddImage(destination, finalImage, nil)
        
        if CGImageDestinationFinalize(destination) {
            print("💾 [HistoryManager] 历史截图已覆盖更新: \(fileURL.path)")
            
            var newSize = record.fileSize
            if let attr = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let size = attr[.size] as? Int64 {
                newSize = size
            }
            
            records[index].annotations = annotations
            records[index].fileSize = newSize
            
            saveRecords()
            
            NotificationCenter.default.post(name: .HistoryDidUpdate, object: nil)
        } else {
            print("❌ [HistoryManager] 保存更新图片失败")
        }
    }
    
    private func deleteFile(for fileName: String) {
        let url = fileURL(for: fileName)
        let originalFileName = fileName.replacingOccurrences(of: ".png", with: "_original.png")
        let originalURL = fileURL(for: originalFileName)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            if fileManager.fileExists(atPath: originalURL.path) {
                try fileManager.removeItem(at: originalURL)
            }
        } catch {
            print("❌ [HistoryManager] 删除文件失败: \(error)")
        }
    }
}

extension Notification.Name {
    public static let HistoryDidUpdate = Notification.Name("HistoryDidUpdate")
}
