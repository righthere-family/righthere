import SwiftUI

// MARK: - Launch Overlay

// The static launch screen (storyboard) shows LaunchScene over the beige
// field with the tagline at the bottom. This overlay opens on the exact same
// pixels — the same image assets — so the hand-off is invisible. Then the
// scene comes alive: a spark runs the arc from the honey dot to the graphite
// one, and the whole scene lifts away into the app.
struct LaunchOverlay: View {
    @Binding var isPresented: Bool
    @State private var sparkT: CGFloat = 0
    @State private var isLifting = false

    // LaunchScene geometry, in the image's own 220x105pt space: the same
    // quadratic curve the dotted arc is drawn along, so the spark rides the
    // dots instead of floating above them.
    private static let arcFrom = CGPoint(x: 66.33, y: 44)
    private static let arcTo = CGPoint(x: 153.33, y: 44)
    private static let arcControl = CGPoint(x: 109.83, y: -4.67)

    var body: some View {
        ZStack {
            Palette.background

            ZStack {
                Image("LaunchScene")
                Circle()
                    .fill(Palette.accentBright)
                    .frame(width: 7, height: 7)
                    .shadow(color: Palette.accentBright.opacity(0.85), radius: 5)
                    .modifier(SparkOnArc(
                        t: sparkT,
                        from: Self.arcFrom,
                        to: Self.arcTo,
                        control: Self.arcControl
                    ))
            }
            .frame(width: 220, height: 105)
            .offset(y: isLifting ? -36 : 0)

            VStack {
                Spacer()
                Image("LaunchTagline")
                    .padding(.bottom, 64)
            }
        }
        // The storyboard centers in the full screen; without this the overlay
        // would center in the safe area, a dozen points lower, and the scene
        // would visibly hop at hand-off.
        .ignoresSafeArea()
        .opacity(isLifting ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear { run() }
    }

    // MARK: - Choreography

    private func run() {
        withAnimation(.easeInOut(duration: 0.7).delay(0.25)) {
            sparkT = 1
        }
        withAnimation(.easeIn(duration: 0.45).delay(1.1)) {
            isLifting = true
        } completion: {
            isPresented = false
        }
    }
}

// MARK: - Spark Path

// A plain withAnimation over t would tween .position in a straight line;
// Animatable re-evaluates every frame, so the spark truly rides the arc.
private struct SparkOnArc: ViewModifier, @preconcurrency Animatable {
    var t: CGFloat
    let from: CGPoint
    let to: CGPoint
    let control: CGPoint

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let mt = 1 - t
        let fade = min(1.0, Double(1 - t) * 12)
        content
            .opacity(t <= 0 ? 0 : fade)
            .position(
                x: mt * mt * from.x + 2 * mt * t * control.x + t * t * to.x,
                y: mt * mt * from.y + 2 * mt * t * control.y + t * t * to.y
            )
    }
}
