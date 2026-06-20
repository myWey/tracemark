import Foundation

/// 交互相关常量
enum InteractionConfig {
    /// OverlayWindow 双击进入编辑态的最大间隔（秒）
    static let overlayDoubleClickInterval: TimeInterval = 0.3
    /// AnnotationRootView 双击兜底检测的最大间隔（秒，比 overlay 更宽松）
    static let annotationDoubleClickFallbackInterval: TimeInterval = 0.5
}
