import SwiftUI

// MARK: - Skeleton

// Loading placeholders reuse the real layout: the actual view is rendered with
// sample data, redacted, and breathes slowly. No separate skeleton mockups to
// keep in sync, and the calm pulse fits the product better than a shimmer.
struct SkeletonModifier: ViewModifier {
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .opacity(isDimmed ? 0.45 : 0.8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

extension View {
    func skeleton() -> some View {
        modifier(SkeletonModifier())
    }
}
