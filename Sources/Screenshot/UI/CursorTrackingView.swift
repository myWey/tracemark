import SwiftUI
import AppKit

public struct CursorTrackingView: NSViewRepresentable {
    let cursor: NSCursor?
    
    public init(cursor: NSCursor?) {
        self.cursor = cursor
    }
    
    public func makeNSView(context: Context) -> CursorTrackingNSView {
        let view = CursorTrackingNSView()
        view.cursor = cursor
        return view
    }
    
    public func updateNSView(_ nsView: CursorTrackingNSView, context: Context) {
        nsView.cursor = cursor
    }
}

public class CursorTrackingNSView: NSView {
    var cursor: NSCursor? {
        didSet {
            self.window?.invalidateCursorRects(for: self)
        }
    }
    
    public override func resetCursorRects() {
        if let cursor = cursor {
            self.addCursorRect(self.bounds, cursor: cursor)
        } else {
            super.resetCursorRects()
        }
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks pass through to the views underneath
        return nil
    }
}
