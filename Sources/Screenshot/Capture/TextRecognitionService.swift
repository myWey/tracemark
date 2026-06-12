import Cocoa
import Vision

public class TextRecognitionService {
    public static let shared = TextRecognitionService()
    
    private init() {}
    
    /// 执行 OCR 识别
    /// - Parameters:
    ///   - image: 要识别的 CGImage
    ///   - rect: 可选的裁剪区域（归一化坐标或相对于 image 的像素坐标）。如果为空则识别整张图。
    ///   - completion: 完成回调，返回识别结果与可能发生的错误
    public func recognizeText(from image: CGImage, in rect: CGRect? = nil, completion: @escaping (String?, Error?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    completion(nil, nil)
                }
                return
            }
            
            // 拼装所有识别到的文本
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            let fullText = recognizedStrings.joined(separator: "\n")
            DispatchQueue.main.async {
                completion(fullText, nil)
            }
        }
        
        // 配置识别语言与精度
        request.recognitionLevel = .accurate
        // 移除强制的语言指定，让系统按默认（英文+系统语言）识别，或使用更新的 API
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        // 如果支持语言自动修正，开启以提升效果
        request.usesLanguageCorrection = true
        
        // 如果提供了区域，可限定识别区域 (Region of Interest)
        // 注意：VNRecognizeTextRequest 的 regionOfInterest 必须是归一化坐标 (0~1)
        if let rect = rect {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            // 将像素坐标转换为归一化坐标
            // Vision 坐标系左下角为 (0,0)
            let normalizedRect = CGRect(
                x: rect.origin.x / width,
                y: (height - rect.origin.y - rect.height) / height,
                width: rect.width / width,
                height: rect.height / height
            )
            request.regionOfInterest = normalizedRect
        }
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }
}
