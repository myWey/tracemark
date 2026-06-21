import Foundation
import CoreGraphics

/// 标注几何计算工具（纯函数，无状态）
enum AnnotationGeometry {
    /// 测试点是否命中标注的拖拽 handle
    /// - Parameters:
    ///   - point: 测试点
    ///   - rect: 标注矩形
    ///   - handleHitZone: 整体命中区外扩距离（两视图均为 20）
    ///   - cornerMinHitZone: 角落命中区最小值（AnnotationRootView=10, OverlayWindow=5）
    ///   - edgeHitZone: 边缘中点命中区（nil 时用 cornerHitZone，即不区分角落和边缘；OverlayWindow 传 20）
    /// - Returns: 命中的 DragHandle 类型，未命中返回 nil
    static func hitTestHandle(
        point: CGPoint,
        in rect: CGRect,
        handleHitZone: CGFloat = 20.0,
        cornerMinHitZone: CGFloat,
        edgeHitZone: CGFloat? = nil
    ) -> DragHandle? {
        let hitRect = rect.insetBy(dx: -handleHitZone, dy: -handleHitZone)
        guard hitRect.contains(point) else { return nil }

        let hitZoneX = min(handleHitZone, max(cornerMinHitZone, rect.width / 3.0))
        let hitZoneY = min(handleHitZone, max(cornerMinHitZone, rect.height / 3.0))

        let isNearX = { (val: CGFloat, target: CGFloat) in abs(val - target) <= hitZoneX }
        let isNearY = { (val: CGFloat, target: CGFloat) in abs(val - target) <= hitZoneY }

        let edgeX = edgeHitZone ?? hitZoneX
        let edgeY = edgeHitZone ?? hitZoneY
        let isNearXEdge = { (val: CGFloat, target: CGFloat) in abs(val - target) <= edgeX }
        let isNearYEdge = { (val: CGFloat, target: CGFloat) in abs(val - target) <= edgeY }

        if isNearX(point.x, rect.minX) && isNearY(point.y, rect.minY) { return .topLeft }
        if isNearX(point.x, rect.maxX) && isNearY(point.y, rect.minY) { return .topRight }
        if isNearX(point.x, rect.minX) && isNearY(point.y, rect.maxY) { return .bottomLeft }
        if isNearX(point.x, rect.maxX) && isNearY(point.y, rect.maxY) { return .bottomRight }
        if isNearXEdge(point.x, rect.minX) { return .left }
        if isNearXEdge(point.x, rect.maxX) { return .right }
        if isNearYEdge(point.y, rect.minY) { return .top }
        if isNearYEdge(point.y, rect.maxY) { return .bottom }
        return nil
    }

    /// 将标注钳制到指定边界内
    /// - Parameters:
    ///   - item: 原始标注
    ///   - bounds: 边界矩形（nil 时返回原 item 不做钳制）
    /// - Returns: 钳制后的标注
    static func clampedAnnotation(_ item: AnnotationItem, to bounds: CGRect?) -> AnnotationItem {
        guard let bounds = bounds, bounds.width > 0, bounds.height > 0 else { return item }
        var item = item
        let boundingRect = item.rect
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if boundingRect.minX < bounds.minX { dx = bounds.minX - boundingRect.minX }
        if boundingRect.minY < bounds.minY { dy = bounds.minY - boundingRect.minY }
        if boundingRect.maxX > bounds.maxX { dx = bounds.maxX - boundingRect.maxX }
        if boundingRect.maxY > bounds.maxY { dy = bounds.maxY - boundingRect.maxY }
        if dx != 0 || dy != 0 {
            item.move(by: CGSize(width: dx, height: dy))
        }
        return item
    }
}
