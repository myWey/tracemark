import Cocoa
import Vision

/// 单个 OCR 识别文本块，包含文字内容与在图片中的归一化位置
public struct RecognizedTextBlock: Identifiable {
    public let id = UUID()
    public let text: String
    /// Vision 坐标系下的归一化 boundingBox（origin 为左下角）
    public let boundingBox: CGRect
    /// 每个字符在 Vision 坐标系下的归一化 boundingBox，用于图像上的精确选择
    public let charBoundingBoxes: [CGRect]
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, charBoundingBoxes: [CGRect] = [], confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.charBoundingBoxes = charBoundingBoxes
        self.confidence = confidence
    }

    /// 将 Vision 归一化坐标转换为以左上角为原点的视图坐标
    public func rectInView(size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let x = boundingBox.origin.x * size.width
        let y = (1.0 - boundingBox.origin.y - boundingBox.height) * size.height
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 将每个字符的归一化坐标转换为视图坐标
    public func charRectsInView(size: CGSize) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        return charBoundingBoxes.map { box in
            CGRect(
                x: box.origin.x * size.width,
                y: (1.0 - box.origin.y - box.height) * size.height,
                width: box.width * size.width,
                height: box.height * size.height
            )
        }
    }
}

public class TextRecognitionService {
    public static let shared = TextRecognitionService()

    private init() {}

    /// 执行 OCR 识别
    /// - Parameters:
    ///   - image: 要识别的 CGImage
    ///   - rect: 可选的裁剪区域（归一化坐标或相对于 image 的像素坐标）。如果为空则识别整张图。
    ///   - completion: 完成回调，返回识别结果与可能发生的错误
    public func recognizeText(from image: CGImage, in rect: CGRect? = nil, completion: @escaping (String?, Error?) -> Void) {
        recognizeTextWithBoundingBoxes(from: image, in: rect) { blocks, error in
            if let error = error {
                completion(nil, error)
                return
            }
            let fullText = blocks?.map(\.text).joined(separator: "\n") ?? ""
            completion(fullText, nil)
        }
    }

    /// 执行 OCR 识别并返回每个文本块的位置信息
    /// - Parameters:
    ///   - image: 要识别的 CGImage
    ///   - rect: 可选的裁剪区域（像素坐标）。如果为空则识别整张图。
    ///   - completion: 完成回调，返回识别文本块数组与可能发生的错误
    public func recognizeTextWithBoundingBoxes(from image: CGImage, in rect: CGRect? = nil, completion: @escaping ([RecognizedTextBlock]?, Error?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    completion([], nil)
                }
                return
            }

            var blocks: [RecognizedTextBlock] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                guard !text.isEmpty else { continue }

                let confidence: Float
                if #available(macOS 13.0, *) {
                    confidence = observation.confidence
                } else {
                    confidence = 1.0
                }

                // 计算每个字符的 bounding box，用于图像上的精确选择
                var charBoundingBoxes: [CGRect] = []
                let textStart = text.startIndex
                for i in 0..<text.count {
                    let start = text.index(textStart, offsetBy: i)
                    let end = text.index(start, offsetBy: 1)
                    if let charObservation = try? candidate.boundingBox(for: start..<end) {
                        charBoundingBoxes.append(charObservation.boundingBox)
                    }
                }

                let block = RecognizedTextBlock(
                    text: text,
                    boundingBox: observation.boundingBox,
                    charBoundingBoxes: charBoundingBoxes,
                    confidence: confidence
                )
                blocks.append(block)
            }

            DispatchQueue.main.async {
                completion(blocks, nil)
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
