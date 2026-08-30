import SwiftUI

// MARK: - Typography

enum Typography {
    static let status = display(40)
    static let quote = displayItalic(31)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let timestamp = Font.system(size: 13, design: .monospaced)
    static let footnote = Font.footnote

    static func display(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBold", size: size)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBoldItalic", size: size)
    }
}
