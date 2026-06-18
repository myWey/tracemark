import SwiftUI

public struct TMDesign {
    public struct Colors {
        // Curated Premium Palette for professional annotations
        public static let red = Color(hex: "FF3B30")
        public static let orange = Color(hex: "FF9500")
        public static let yellow = Color(hex: "FFCC00")
        public static let green = Color(hex: "28CD41")
        public static let cyan = Color(hex: "5AC8FA")
        public static let blue = Color(hex: "007AFF")
        public static let purple = Color(hex: "AF52DE")
        
        public static let dark = Color(hex: "1C1C1E")
        public static let white = Color.white
        
        // The default palette to show in the toolbar
        public static let toolbarPalette: [Color] = [
            red, orange, yellow, green, cyan, blue, purple, dark, white
        ]
    }
}

// Helper to convert SwiftUI Color to hex for serialization if needed
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
