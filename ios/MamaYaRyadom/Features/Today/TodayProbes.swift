#if DEBUG
import SwiftUI

// MARK: - Probe Config

enum ProbeVariant: String {
    case a = "A"
    case b = "B"
    case c = "C"
}

enum ProbeState: String {
    case ok
    case quote
    case quiet
}

// MARK: - Probe Host

struct ProbeHost: View {
    let variant: ProbeVariant
    let state: ProbeState

    var body: some View {
        switch variant {
        case .a: ProbeListSheet(state: state)
        case .b: ProbeLandingWorld(state: state)
        case .c: ProbeSilence(state: state)
        }
    }
}

// MARK: - Shared Probe Content

private enum ProbeContent {
    static let dateLine = "Среда, 13 августа"
    static let who = "Мама · Самара"
    static let okTime = "сегодня в 9:41 · по Самаре"
    static let quoteText = "давление поднялось, лежу"
    static let quietHint = "Весточки сегодня не было. Лучший способ узнать, как дела, — позвонить."
    static let week: [(String, WeekDayResult)] = [
        ("пн", .ok), ("вт", .ok), ("ср", .ok), ("чт", .alert),
        ("пт", .ok), ("сб", .missed), ("вс", .ok),
    ]
}

// MARK: - Variant A · List Sheet

private struct ProbeListSheet: View {
    let state: ProbeState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ProbeContent.dateLine.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, 24)

            Text(ProbeContent.who)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 6)

            Spacer().frame(height: 44)

            switch state {
            case .ok:
                Text("Всё хорошо")
                    .font(.system(size: 42, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.okStrong)
                Text(ProbeContent.okTime)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 10)
            case .quote:
                Text("Мама написала:")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSecondary)
                Text("«\(ProbeContent.quoteText)»")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Palette.alert)
                    .padding(.top, 8)
            case .quiet:
                Text("Тихое утро")
                    .font(.system(size: 42, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ink)
                Text(ProbeContent.quietHint)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(3)
                    .padding(.top, 10)
            }

            Spacer().frame(height: 36)
            Divider()
            Spacer().frame(height: 20)

            HStack(spacing: 0) {
                ForEach(Array(ProbeContent.week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 7) {
                        Text(day.0)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.inkSecondary.opacity(0.7))
                        weekDot(day.1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if state == .ok {
                Spacer().frame(height: 26)
                HStack {
                    Text("Лекарства")
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Text("2 из 2 ✓")
                        .foregroundStyle(Palette.okStrong)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
            }

            Spacer()

            if state != .ok {
                Button {} label: {
                    Label("Позвонить маме", systemImage: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 15))
                .tint(Palette.okStrong)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }

    @ViewBuilder
    private func weekDot(_ result: WeekDayResult) -> some View {
        switch result {
        case .ok:
            Circle().fill(Palette.okStrong).frame(width: 11, height: 11)
        case .alert:
            RoundedRectangle(cornerRadius: 3.5).fill(Palette.alert).frame(width: 11, height: 11)
        case .missed:
            Circle().strokeBorder(Palette.inkSecondary.opacity(0.4), lineWidth: 1.4).frame(width: 11, height: 11)
        case .pending, .blank:
            Circle().strokeBorder(Palette.inkSecondary.opacity(0.22), lineWidth: 1.4).frame(width: 11, height: 11)
        }
    }
}

// MARK: - Variant B · Landing World

private enum Honey {
    static let bg = Color(UIColor(hex: 0xF5F0E7))
    static let sheet = Color.white
    static let ink = Color(UIColor(hex: 0x33291F))
    static let inkSoft = Color(UIColor(hex: 0x33291F)).opacity(0.55)
    static let honey = Color(UIColor(hex: 0x9A6410))
    static let honeyBright = Color(UIColor(hex: 0xB8791A))
    static let cherry = Color(UIColor(hex: 0x8E3A4C))
    static let leaf = Color(UIColor(hex: 0x3F7A4E))
    static let moss = Color(UIColor(hex: 0x5E7A3C))
}

private enum ProbeAccent: String {
    case leaf
    case moss
    case graphite
}

private enum ProbeFont {
    static func display(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBold", size: size)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBoldItalic", size: size)
    }
}

private struct ProbeLandingWorld: View {
    let state: ProbeState

    private let accent = ProbeAccent(
        rawValue: UserDefaults.standard.string(forKey: "probeAccent") ?? "leaf"
    ) ?? .leaf

    private var okGreen: Color {
        accent == .moss ? Honey.moss : Honey.leaf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ProbeContent.dateLine)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Honey.inkSoft)
                Spacer()
                BrandMark()
                    .frame(width: 30, height: 19)
            }
            .padding(.top, 18)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(ProbeContent.who)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(Honey.inkSoft)

                switch state {
                case .ok:
                    HStack(spacing: 11) {
                        if accent == .graphite {
                            Circle().fill(Honey.leaf).frame(width: 10, height: 10)
                        }
                        Text("Всё хорошо")
                            .font(ProbeFont.display(40))
                            .foregroundStyle(accent == .graphite ? Honey.ink : okGreen)
                    }
                    .padding(.top, 12)
                    Text(ProbeContent.okTime)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Honey.inkSoft)
                        .padding(.top, 10)
                    Text("двенадцатое утро подряд")
                        .font(.system(size: 13))
                        .foregroundStyle(Honey.inkSoft.opacity(0.75))
                        .padding(.top, 3)
                case .quote:
                    Text("Мама — своими словами:")
                        .font(.system(size: 14))
                        .foregroundStyle(Honey.inkSoft)
                        .padding(.top, 14)
                    Text("«\(ProbeContent.quoteText)»")
                        .font(ProbeFont.displayItalic(31))
                        .foregroundStyle(Honey.cherry)
                        .lineSpacing(3)
                        .padding(.top, 10)
                case .quiet:
                    Text("Тихое утро")
                        .font(ProbeFont.display(40))
                        .foregroundStyle(Honey.ink)
                        .padding(.top, 12)
                    Text(ProbeContent.quietHint)
                        .font(.system(size: 15))
                        .foregroundStyle(Honey.inkSoft)
                        .lineSpacing(3)
                        .padding(.top, 10)
                }

                Spacer().frame(height: 26)
                Rectangle()
                    .fill(Honey.honeyBright.opacity(0.18))
                    .frame(height: 1)
                Spacer().frame(height: 18)

                HStack(spacing: 0) {
                    ForEach(Array(ProbeContent.week.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 7) {
                            Text(day.0)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Honey.inkSoft.opacity(0.65))
                            weekDot(day.1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if state == .ok {
                    Spacer().frame(height: 22)
                    HStack {
                        Text("Лекарства")
                            .foregroundStyle(Honey.inkSoft)
                        Spacer()
                        Text("2 из 2 ✓")
                            .foregroundStyle(okGreen)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .background(Honey.sheet, in: .rect(cornerRadius: 24))
            .shadow(color: Honey.ink.opacity(0.05), radius: 16, y: 6)

            if state != .ok {
                Spacer().frame(height: 16)
                Button {} label: {
                    Label("Позвонить маме", systemImage: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Honey.honey, in: .rect(cornerRadius: 16))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Honey.bg)
    }

    @ViewBuilder
    private func weekDot(_ result: WeekDayResult) -> some View {
        switch result {
        case .ok:
            Circle().fill(okGreen == Honey.moss ? Honey.moss : Honey.leaf).frame(width: 9, height: 9)
        case .alert:
            RoundedRectangle(cornerRadius: 3).fill(Honey.cherry).frame(width: 9, height: 9)
        case .missed:
            Circle().strokeBorder(Honey.inkSoft.opacity(0.45), lineWidth: 1.3).frame(width: 9, height: 9)
        case .pending, .blank:
            Circle().strokeBorder(Honey.inkSoft.opacity(0.28), lineWidth: 1.3).frame(width: 9, height: 9)
        }
    }
}

// MARK: - Variant C · Silence

private struct ProbeSilence: View {
    let state: ProbeState

    var body: some View {
        VStack(spacing: 0) {
            Text("среда · 13 августа · самара")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Palette.ink.opacity(0.45))
                .padding(.top, 28)

            Spacer()

            switch state {
            case .ok:
                Text("Всё хорошо")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(UIColor(hex: 0x0E7A57)))
                Text("сегодня в 9:41")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .padding(.top, 12)
            case .quote:
                Text("мама —")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                Text("«\(ProbeContent.quoteText)»")
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Color(UIColor(hex: 0x8E3A4C)))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 34)
                    .padding(.top, 10)
            case .quiet:
                Text("Тихое утро")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ink)
                Text(ProbeContent.quietHint)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 44)
                    .padding(.top, 14)
            }

            Spacer()

            HStack(spacing: 14) {
                ForEach(Array(ProbeContent.week.enumerated()), id: \.offset) { _, day in
                    weekDot(day.1)
                }
            }
            .padding(.bottom, state == .ok ? 60 : 24)

            if state != .ok {
                Button {} label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Palette.ink, in: .circle)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    @ViewBuilder
    private func weekDot(_ result: WeekDayResult) -> some View {
        switch result {
        case .ok:
            Circle().fill(Color(UIColor(hex: 0x0E7A57))).frame(width: 8, height: 8)
        case .alert:
            Circle().fill(Color(UIColor(hex: 0x8E3A4C))).frame(width: 8, height: 8)
        case .missed:
            Circle().strokeBorder(Palette.ink.opacity(0.3), lineWidth: 1.2).frame(width: 8, height: 8)
        case .pending, .blank:
            Circle().strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1.2).frame(width: 8, height: 8)
        }
    }
}
#endif
