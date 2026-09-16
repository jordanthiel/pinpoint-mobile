import SwiftUI
import UIKit

enum PinpointTheme {
    static let accent = BrandPalette.coral
    static let accentMuted = BrandPalette.coralWash
    static let accentText = BrandPalette.coralText
    static let background = BrandPalette.canvas
    static let surface = BrandPalette.surface
    static let surfaceElevated = BrandPalette.inset
    static let primaryText = BrandPalette.ink
    static let secondaryText = BrandPalette.secondary
    static let hairline = BrandPalette.ink.opacity(0.07)
    static let onDark = Color.white
    static let mapSurface = BrandPalette.ink.opacity(0.94)

    enum Space {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let page: CGFloat = 20
        static let section: CGFloat = 24
    }
    enum Radius {
        static let field: CGFloat = 16
        static let card: CGFloat = 24
        static let sheet: CGFloat = 30
    }
    enum TypeStyle {
        static let hero = Font.system(.largeTitle, design: .default, weight: .semibold)
        static let section = Font.system(.title2, design: .default, weight: .semibold)
        static let label = Font.system(.subheadline, design: .default, weight: .semibold)
        static let number = Font.system(.title, design: .default, weight: .semibold).monospacedDigit()
    }
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
