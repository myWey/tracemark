import Foundation

extension Notification.Name {
    // 截图后操作触发（打开标注、复制、保存等）
    static let triggerPostCaptureAction = Notification.Name("TriggerPostCaptureAction")
    // 打开标注画布
    static let openAnnotationCanvas = Notification.Name("OpenAnnotationCanvas")
    // 序号双击（进入序号编辑）
    static let counterDoubleTapped = Notification.Name("CounterDoubleTapped")
    // 标注双击（进入文本编辑）
    static let annotationDoubleTapped = Notification.Name("AnnotationDoubleTapped")
    // 语言切换
    static let languageDidChange = Notification.Name("LanguageDidChange")
    // 工具切换
    static let selectedToolChanged = Notification.Name("SelectedToolChanged")
}
