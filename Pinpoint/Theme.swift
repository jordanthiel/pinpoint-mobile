import SwiftUI
import UIKit

enum PinpointTheme {
    static let accent = Color(red: 13 / 255, green: 93 / 255, blue: 229 / 255)
    static let accentMuted = Color(red: 10 / 255, green: 62 / 255, blue: 160 / 255)
    static let background = Color(red: 0.04, green: 0.06, blue: 0.05)
    static let surface = Color(red: 0.09, green: 0.12, blue: 0.10)
    static let surfaceElevated = Color(red: 0.13, green: 0.17, blue: 0.14)
    static let hairline = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.62)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
