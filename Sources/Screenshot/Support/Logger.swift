import Foundation
import os

/// 统一日志系统，按子系统分类
/// 使用 os.Logger 替代 print，支持 Console.app 按级别和子系统过滤
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tracemark"

    /// UI 模块日志
    static let ui = Logger(subsystem: subsystem, category: "ui")
    /// 截图捕获模块日志
    static let capture = Logger(subsystem: subsystem, category: "capture")
    /// 标注模块日志
    static let annotation = Logger(subsystem: subsystem, category: "annotation")
    /// 历史记录模块日志
    static let history = Logger(subsystem: subsystem, category: "history")
    /// 快捷键模块日志
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    /// 主应用模块日志
    static let app = Logger(subsystem: subsystem, category: "app")
}
