import SwiftUI

// MARK: - Palette

enum Palette {
    static let background = dynamic(light: 0xF5F0E7, dark: 0x1E1913)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A241C)
    static let ink = dynamic(light: 0x33291F, dark: 0xEDE6D8)
    static let inkSecondary = dynamic(light: 0x7A6F62, dark: 0xA99C8B)
    static let accent = dynamic(light: 0x9A6410, dark: 0xC99B3F)
    static let accentBright = dynamic(light: 0xB8791A, dark: 0xD9B268)
    static let okStrong = dynamic(light: 0x3F7A4E, dark: 0x6FA97E)
    static let okTint = dynamic(light: 0xEAF0E6, dark: 0x24352B)
    static let warn = dynamic(light: 0xA5751B, dark: 0xC28E2E)
    static let alert = dynamic(light: 0x8E3A4C, dark: 0xC4818E)
    static let alertTint = dynamic(light: 0xF5E8EA, dark: 0x33222A)
    static let formDisabled = dynamic(light: 0xEDE6DA, dark: 0x363028)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Hex

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
