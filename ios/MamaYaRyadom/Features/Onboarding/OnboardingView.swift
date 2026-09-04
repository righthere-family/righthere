import SwiftUI

// MARK: - Onboarding

struct OnboardingView: View {
    @Binding var done: Bool
    @State private var step: Int
    @State private var momPresses = 0
    @State private var delivered = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(done: Binding<Bool>) {
        _done = done
        #if DEBUG
        _step = State(initialValue: UserDefaults.standard.integer(forKey: "onbStep"))
        #else
        _step = State(initialValue: 0)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 24)
                .opacity(leaving ? 0 : 1)

            Spacer()

            StoryScene(
                step: step,
                pulsing: !reduceMotion,
                leaving: leaving,
                onMomTap: pressMomButton
            )
            .frame(height: 330)

            captions
                .frame(height: 140, alignment: .top)
                .padding(.top, 26)
                .opacity(leaving ? 0 : 1)

            Spacer()

            footer
                .frame(height: 82)
                .padding(.bottom, 24)
                .opacity(leaving ? 0 : 1)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .overlay(alignment: .bottom) {
            if step == 3 && !leaving && !reduceMotion {
                WalkingCat()
                    .frame(height: 34)
                    .padding(.bottom, 116)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .onTapGesture { advance() }
        .sensoryFeedback(.impact(weight: .medium), trigger: momPresses)
        .sensoryFeedback(.success, trigger: delivered)
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "onbAuto") {
                Task {
                    for _ in 0..<3 {
                        try? await Task.sleep(for: .seconds(3.4))
                        if step == 1 {
                            pressMomButton()
                        } else {
                            forceAdvance()
                        }
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Steps

    private func advance() {
        if step == 1 {
            pressMomButton()
            return
        }
        guard step == 0 || step == 2 else { return }
        forceAdvance()
    }

    private func forceAdvance() {
        guard step < 3 else { return }
        withAnimation(.spring(duration: 0.55, bounce: 0.15)) { step += 1 }
    }

    private func pressMomButton() {
        guard step == 1 else { return }
        momPresses += 1
        withAnimation(.spring(duration: 0.55, bounce: 0.15)) { step = 2 }
        Task {
            try? await Task.sleep(for: .seconds(1.15))
            delivered = true
        }
    }

    private func finish() {
        withAnimation(.easeIn(duration: 0.32)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.14))
            withAnimation(.easeInOut(duration: 0.38)) { done = true }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { index in
                Capsule()
                    .fill(index <= step ? Palette.accent : Palette.ink.opacity(0.12))
                    .frame(width: 26, height: 3)
            }
        }
        .animation(.easeOut(duration: 0.3), value: step)
    }

    // MARK: - Captions

    private var captions: some View {
        ZStack {
            VStack(spacing: 12) {
                Text(captionTitle)
                    .font(Typography.display(23))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if step == 3 {
                    Text(L10n.onboardingStoryPrivacy)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 320)
                }
                if step == 0 {
                    hint(L10n.onboardingStoryHint)
                        .padding(.top, 6)
                }
                if step == 1 {
                    hint(L10n.onboardingStoryHintButton)
                        .padding(.top, 6)
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 12)),
                removal: .opacity
            ))
        }
    }

    private var captionTitle: String {
        switch step {
        case 0: L10n.onboardingStoryDistance
        case 1: L10n.onboardingStoryButton
        case 2: L10n.onboardingStoryDelivered
        default: L10n.onboardingStoryHabit
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if step == 3 {
            Button {
                finish()
            } label: {
                Text(L10n.onboardingStart)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.accent, in: .rect(cornerRadius: 16))
            }
            .transition(.opacity.combined(with: .offset(y: 14)))
        } else {
            Color.clear
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.inkSecondary.opacity(0.8))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Story Scene

private struct StoryScene: View {
    let step: Int
    let pulsing: Bool
    let leaving: Bool
    let onMomTap: () -> Void

    @State private var sparkT: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let baseY = geo.size.height - 56
            let momX: CGFloat = 30
            let childX = width - 30
            let arcStart = CGPoint(x: momX, y: baseY)
            let arcEnd = CGPoint(x: childX, y: baseY)
            let arcControl = CGPoint(x: width / 2, y: baseY - 162.5)

            ZStack {
                SignalArc()
                    .trim(from: 0, to: step >= 2 ? 1 : 0)
                    .stroke(
                        Palette.accentBright.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 5.2])
                    )
                    .animation(.easeInOut(duration: 1.15), value: step)
                    .frame(width: width - 60, height: 130)
                    .position(x: width / 2, y: baseY - 65)
                    .opacity(leaving ? 0 : 1)

                if pulsing && step == 1 {
                    SonarRing()
                        .position(x: momX, y: baseY)
                }

                Circle()
                    .fill(Palette.accentBright)
                    .frame(width: 15, height: 15)
                    .position(x: momX, y: baseY)
                    .opacity(leaving ? 0 : 1)

                Circle()
                    .fill(Palette.ink)
                    .frame(width: 15, height: 15)
                    .position(x: childX, y: baseY)
                    .opacity(leaving ? 0 : 1)

                Text(L10n.onboardingLabelMom)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
                    .position(x: momX + 4, y: baseY + 24)
                    .opacity(leaving ? 0 : 1)

                Text(L10n.onboardingLabelYou)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
                    .position(x: childX - 4, y: baseY + 24)
                    .opacity(leaving ? 0 : 1)

                MomPhone(step: step, pulsing: pulsing, onTap: onMomTap)
                    .scaleEffect(phoneScale, anchor: .bottomLeading)
                    .opacity(step == 1 || step == 2 ? (step == 2 ? 0 : 1) : 0)
                    .position(x: momX + 92, y: baseY - 138)
                    .animation(.spring(duration: 0.55, bounce: 0.18), value: step)

                if sparkT > 0.01 && sparkT < 0.97 {
                    Circle()
                        .fill(Palette.accentBright)
                        .frame(width: 7, height: 7)
                        .shadow(color: Palette.accentBright.opacity(0.8), radius: 5)
                        .modifier(SparkAlongArc(t: sparkT, from: arcStart, to: arcEnd, control: arcControl))
                }

                ChildPhone(step: step, leaving: leaving)
                    .position(x: childX - 84, y: baseY - 128)
            }
        }
        .onChange(of: step) { _, newStep in
            guard newStep == 2 else { return }
            sparkT = 0
            withAnimation(.easeInOut(duration: 1.15)) { sparkT = 1 }
        }
    }

    private var phoneScale: CGFloat {
        switch step {
        case 1: 1
        case 2: 0.05
        default: 0.05
        }
    }
}

// MARK: - Mom Phone

private struct MomPhone: View {
    let step: Int
    let pulsing: Bool
    let onTap: () -> Void

    @State private var breathe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.accentBright)
                    .frame(width: 11, height: 11)
                Text(L10n.onboardingPhoneBotName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }

            Text(L10n.onboardingPhoneGreeting)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Palette.background, in: .rect(cornerRadius: 12))

            Button {
                onTap()
            } label: {
                Text(L10n.onboardingSceneButton)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Palette.accentBright.opacity(0.16), in: .rect(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Palette.accentBright.opacity(0.55), lineWidth: 1.3)
                    )
            }
            .buttonStyle(.plain)
            .disabled(step != 1)
            .scaleEffect(breathe ? 1.07 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }

            Text(L10n.onboardingPhoneNotOk)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: 11))
        }
        .padding(14)
        .frame(width: 188)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Palette.ink.opacity(0.12), radius: 16, y: 7)
    }
}

// MARK: - Child Phone

private struct ChildPhone: View {
    let step: Int
    let leaving: Bool

    var body: some View {
        VStack(spacing: 10) {
            widget
            appRow
        }
        .padding(12)
        .frame(width: 168)
        .background(Palette.background, in: .rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Palette.ink.opacity(0.10), lineWidth: 1.2)
        )
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Palette.card.opacity(0.5))
        )
        .shadow(color: Palette.ink.opacity(0.12), radius: 16, y: 7)
        .opacity(step >= 2 ? 1 : 0)
        .scaleEffect(step >= 2 ? 1 : 0.7, anchor: .bottom)
        .animation(.spring(duration: 0.55, bounce: 0.25).delay(step >= 2 && !leaving ? 1.05 : 0), value: step)
    }

    private var widget: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.onboardingWidgetWho)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.inkSecondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.okStrong)
                    .frame(width: 7.5, height: 7.5)
                Text(L10n.statusAllGood)
                    .font(Typography.display(15))
                    .foregroundStyle(Palette.okStrong)
            }

            Text(L10n.onboardingWidgetTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)

            if step >= 3 {
                HStack(spacing: 6) {
                    ForEach(0..<7) { index in
                        Circle()
                            .fill(Palette.okStrong)
                            .frame(width: 5, height: 5)
                            .transition(.scale.combined(with: .opacity))
                            .animation(
                                .spring(duration: 0.35, bounce: 0.3).delay(0.15 + Double(index) * 0.07),
                                value: step
                            )
                    }
                }
                .padding(.top, 3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 16))
        .shadow(color: Palette.ink.opacity(0.07), radius: 8, y: 3)
    }

    private static let apps: [(symbol: String, tint: Color)] = [
        ("phone.fill", Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("safari.fill", Color(red: 0.00, green: 0.48, blue: 1.00)),
        ("message.fill", Color(red: 0.24, green: 0.80, blue: 0.28)),
        ("camera.fill", Color(red: 0.56, green: 0.56, blue: 0.58)),
    ]

    private var appRow: some View {
        HStack(spacing: 12) {
            ForEach(Self.apps, id: \.symbol) { app in
                RoundedRectangle(cornerRadius: 7)
                    .fill(app.tint)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: app.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    )
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Spark

private struct SparkAlongArc: ViewModifier, @preconcurrency Animatable {
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
        let x = mt * mt * from.x + 2 * mt * t * control.x + t * t * to.x
        let y = mt * mt * from.y + 2 * mt * t * control.y + t * t * to.y
        return content.position(x: x, y: y)
    }
}

// MARK: - Sonar Ring

private struct SonarRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Palette.accentBright.opacity(expanded ? 0 : 0.5), lineWidth: 1.5)
            .frame(width: 15, height: 15)
            .scaleEffect(expanded ? 3.2 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

// MARK: - Walking Cat

private struct WalkingCat: View {
    @State private var walking = false
    @State private var stepPhase = false

    var body: some View {
        GeometryReader { geo in
            SteppingCat(phase: stepPhase)
                .position(
                    x: walking ? geo.size.width + 50 : -50,
                    y: geo.size.height / 2 + (stepPhase ? -0.8 : 0.8)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                        stepPhase = true
                    }
                    withAnimation(.linear(duration: 7).delay(1.2)) {
                        walking = true
                    }
                }
        }
    }
}

private struct SteppingCat: View {
    let phase: Bool

    private var silhouette: Color {
        Palette.ink.opacity(0.78)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TailShape()
                .stroke(silhouette, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 14, height: 16)
                .offset(x: -19, y: -12)
                .rotationEffect(.degrees(phase ? 4 : -4), anchor: .bottomTrailing)

            legPair(xOffsets: [-10, 7], forward: phase)
            legPair(xOffsets: [-6, 11], forward: !phase)

            Capsule()
                .fill(silhouette)
                .frame(width: 30, height: 12)
                .offset(y: -7)

            Circle()
                .fill(silhouette)
                .frame(width: 12, height: 12)
                .offset(x: 16, y: -13)

            EarShape()
                .fill(silhouette)
                .frame(width: 4.5, height: 5)
                .offset(x: 12.5, y: -22)
            EarShape()
                .fill(silhouette)
                .frame(width: 4.5, height: 5)
                .offset(x: 18.5, y: -22)
        }
        .frame(width: 48, height: 28)
    }

    private func legPair(xOffsets: [CGFloat], forward: Bool) -> some View {
        ForEach(xOffsets, id: \.self) { x in
            Capsule()
                .fill(silhouette)
                .frame(width: 2.6, height: 9)
                .rotationEffect(.degrees(forward ? 14 : -14), anchor: .top)
                .offset(x: x)
        }
    }
}

private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 2, y: rect.minY + 2),
            control: CGPoint(x: rect.minX - 3, y: rect.maxY - 2)
        )
        return path
    }
}

private struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Signal Arc

private struct SignalArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.25)
        )
        return path
    }
}
