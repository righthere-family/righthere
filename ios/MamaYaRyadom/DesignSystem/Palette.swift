import SwiftUI

// MARK: - Palette

enum Palette {
    static let background = dynamic(light: 0xF5F0E7, dark: 0x0F1115)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x20242C)
    static let ink = dynamic(light: 0x33291F, dark: 0xE8E6E1)
    static let inkSecondary = dynamic(light: 0x7A6F62, dark: 0x9BA0A8)
    static let accent = dynamic(light: 0x9A6410, dark: 0xC99B3F)
    static let accentBright = dynamic(light: 0xB8791A, dark: 0xD9B268)
    static let okStrong = dynamic(light: 0x3F7A4E, dark: 0x6FA97E)
    static let okTint = dynamic(light: 0xEAF0E6, dark: 0x203A2E)
    static let warn = dynamic(light: 0xA5751B, dark: 0xC28E2E)
    static let alert = dynamic(light: 0x8E3A4C, dark: 0xCF7E79)
    static let alertTint = dynamic(light: 0xF5E8EA, dark: 0x3A2A2E)
    static let formDisabled = dynamic(light: 0xEDE6DA, dark: 0x2A2F36)

    // A shadow is dark in both themes. Ink is cream at night, so shadows drawn
    // with it lit the cards up instead of lifting them off the background.
    static let shade = dynamic(light: 0x33291F, dark: 0x000000)

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
