import SwiftUI

public struct OCRResultPanel: View {
    @Binding var text: String
    var onClose: () -> Void
    var onTranslate: () -> Void
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("识别文字")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            
            Divider()
            
            // Text Editor
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack(spacing: 12) {
                Button(action: onTranslate) {
                    HStack(spacing: 4) {
                        Image(systemName: "translate")
                        Text("翻译")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("复制")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: 320, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
