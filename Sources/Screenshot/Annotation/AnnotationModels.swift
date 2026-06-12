import SwiftUI

public enum TextStyle: String, CaseIterable, Codable {
    case standard = "Standard"
    case outlined = "Outlined"
    case boxed = "Boxed"
    case roundedBoxed = "Rounded Boxed"
}

public enum DragHandle: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case calloutOrigin // 专门用于 NumberedText 移动圆圈锚点
}

public func handlePosition(for handle: DragHandle, rect: CGRect) -> CGPoint {
    switch handle {
    case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
    case .top: return CGPoint(x: rect.midX, y: rect.minY)
    case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
    case .right: return CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
    case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
    case .left: return CGPoint(x: rect.minX, y: rect.midY)
    case .calloutOrigin: return .zero
    }
}

/// 标注工具类型
public enum AnnotationToolType: String, CaseIterable, Codable {
    case rectangle = "矩形"
    case filledRectangle = "实心矩形"
    case ellipse = "圆形"
    case line = "直线"
    case arrow = "箭头"
    case text = "文字"
    case numberedText = "序号文字"
    case counter = "计数器"
    case pencil = "画笔"
    case highlighter = "荧光笔"
    case blur = "模糊"
    case mosaic = "马赛克"
    case spotlight = "聚焦"
    
    public var isFreehandTool: Bool {
        return self == .pencil || self == .highlighter || self == .blur || self == .mosaic
    }
}

/// 独立的标注数据实体
public struct AnnotationItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var type: AnnotationToolType
    
    // 几何数据
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var points: [CGPoint]? // 自由画笔点集
    public var calloutOffset: CGSize? // 针对 Numbered Text 的独立避让控制偏移量
    
    // 样式数据
    public var color: Color
    public var lineWidth: CGFloat
    
    // 文本特有数据
    public var text: String?
    public var fontStyle: TextStyle?
    public var fontSize: CGFloat?
    
    // 计数器数据
    public var counterValue: Int?
    
    public init(
        id: UUID = UUID(),
        type: AnnotationToolType,
        startPoint: CGPoint,
        endPoint: CGPoint = .zero,
        points: [CGPoint]? = nil,
        color: Color = .red,
        lineWidth: CGFloat = 3.0,
        text: String = "",
        fontStyle: TextStyle? = nil,
        fontSize: CGFloat? = nil,
        counterValue: Int? = nil,
        calloutOffset: CGSize? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.counterValue = counterValue
        self.calloutOffset = calloutOffset
    }
    
    public var isFreehandTool: Bool {
        return type == .pencil || type == .highlighter || type == .blur || type == .mosaic
    }
    
    /// 标准化的 CGRect，处理反向拖拽
    public var rect: CGRect {
        if type == .counter {
            let size = (fontSize ?? 24.0) * 1.5
            return CGRect(
                x: endPoint.x - size / 2,
                y: endPoint.y - size / 2,
                width: size,
                height: size
            )
        }
        if type == .numberedText {
            // Numbered text box bounds based on callout offset
            let origin = CGPoint(x: startPoint.x + (calloutOffset?.width ?? 15.0),
                                 y: startPoint.y + (calloutOffset?.height ?? -60.0))
            return CGRect(
                x: min(origin.x, endPoint.x),
                y: min(origin.y, endPoint.y),
                width: abs(origin.x - endPoint.x),
                height: abs(origin.y - endPoint.y)
            )
        }
        
        if type == .text {
            return CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(startPoint.x - endPoint.x),
                height: abs(startPoint.y - endPoint.y)
            )
        }
        
        if let points = points, !points.isEmpty {
            let minX = points.map(\.x).min()!
            let maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!
            let maxY = points.map(\.y).max()!
            // 为滤镜留一点边距，避免边缘被裁剪得太死
            let padding = lineWidth
            return CGRect(x: minX - padding, y: minY - padding, width: maxX - minX + padding*2, height: maxY - minY + padding*2)
        }
        
        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(startPoint.x - endPoint.x),
            height: abs(startPoint.y - endPoint.y)
        )
    }
    
    public mutating func move(by offset: CGSize) {
        startPoint = CGPoint(x: startPoint.x + offset.width, y: startPoint.y + offset.height)
        endPoint = CGPoint(x: endPoint.x + offset.width, y: endPoint.y + offset.height)
        if let pts = points {
            points = pts.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }
    
    public mutating func resize(to newRect: CGRect, from oldRect: CGRect) {
        let scaleX = oldRect.width > 0 ? newRect.width / oldRect.width : 1
        let scaleY = oldRect.height > 0 ? newRect.height / oldRect.height : 1
        
        let mapPoint: (CGPoint) -> CGPoint = { p in
            return CGPoint(
                x: newRect.minX + (p.x - oldRect.minX) * scaleX,
                y: newRect.minY + (p.y - oldRect.minY) * scaleY
            )
        }
        
        if type == .numberedText {
            // ONLY resize the endPoint/text box bounds. The circle remains at startPoint!
            let origin = CGPoint(x: startPoint.x + (calloutOffset?.width ?? 70), y: startPoint.y + (calloutOffset?.height ?? -70))
            let mappedOrigin = mapPoint(origin)
            endPoint = mapPoint(endPoint)
            calloutOffset = CGSize(width: mappedOrigin.x - startPoint.x, height: mappedOrigin.y - startPoint.y)
        } else {
            startPoint = mapPoint(startPoint)
            endPoint = mapPoint(endPoint)
            if let pts = points {
                points = pts.map(mapPoint)
            }
        }
    }
    
    // MARK: - Codable Custom Mapping
    
    enum CodingKeys: String, CodingKey {
        case id, type, startPoint, endPoint, points, color, lineWidth, text, fontStyle, fontSize, counterValue
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(startPoint, forKey: .startPoint)
        try container.encode(endPoint, forKey: .endPoint)
        try container.encode(points, forKey: .points)
        
        // sRGB Color bridge
        let codableColor = color.toCodable()
        try container.encode(codableColor, forKey: .color)
        
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(text, forKey: .text)
        try container.encode(fontStyle, forKey: .fontStyle)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(counterValue, forKey: .counterValue)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(AnnotationToolType.self, forKey: .type)
        self.startPoint = try container.decode(CGPoint.self, forKey: .startPoint)
        self.endPoint = try container.decode(CGPoint.self, forKey: .endPoint)
        self.points = try container.decodeIfPresent([CGPoint].self, forKey: .points)
        
        let codableColor = try container.decode(CodableColor.self, forKey: .color)
        self.color = codableColor.color
        
        self.lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.fontStyle = try container.decodeIfPresent(TextStyle.self, forKey: .fontStyle)
        self.fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        self.counterValue = try container.decodeIfPresent(Int.self, forKey: .counterValue)
    }
}

// MARK: - Codable Color Support

public struct CodableColor: Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    
    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    public var color: Color {
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension Color {
    public func toCodable() -> CodableColor {
        let nsColor = NSColor(self)
        let rgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return CodableColor(
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent),
            alpha: Double(rgbColor.alphaComponent)
        )
    }
}
