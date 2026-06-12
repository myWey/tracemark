import Cocoa
import SwiftUI

public class ToastManager {
    public static let shared = ToastManager()
    private var toastWindow: NSWindow?
    
    private init() {}
    
    public func showToast(message: String) {
        if toastWindow != nil {
            toastWindow?.close()
        }
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        
        // Measure text size loosely
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        
        let width = textSize.width + 60
        let height: CGFloat = 50
        
        // Position at the bottom center of the screen (higher up for better visibility)
        let x = screen.visibleFrame.midX - width / 2
        let y = screen.visibleFrame.minY + screen.visibleFrame.height * 0.25
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        
        let textField = NSTextField(labelWithString: message)
        textField.font = .systemFont(ofSize: 18, weight: .semibold)
        textField.textColor = .white
        textField.alignment = .center
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])
        
        window.contentView = visualEffect
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        }
        
        self.toastWindow = window
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.toastWindow == window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                window.animator().alphaValue = 0.0
            }) {
                window.close()
                if self?.toastWindow == window {
                    self?.toastWindow = nil
                }
            }
        }
    }
}
