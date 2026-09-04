import SwiftUI

// MARK: - Typography

enum Typography {
    static let status = display(33)
    static let quote = display(26)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let timestamp = Font.system(size: 13, design: .monospaced)
    static let footnote = Font.footnote

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

}
