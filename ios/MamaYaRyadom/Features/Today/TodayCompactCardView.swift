import SwiftUI

// MARK: - Compact Card

struct TodayCompactCardView: View {
    let state: TodayCardState
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 13) {
                Circle()
                    .fill(dot)
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSecondary)
                }

                Spacer(minLength: 8)

                if state.medicationsInfo.total > 0 {
                    Text("\(state.medicationsInfo.taken)/\(state.medicationsInfo.total)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(
                            state.medicationsInfo.taken >= state.medicationsInfo.total
                                ? Palette.okStrong
                                : Palette.inkSecondary
                        )
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var dot: Color {
        switch state.status {
        case .ok: Palette.okStrong
        default: Palette.inkSecondary
        }
    }

    private var line: String {
        switch state.status {
        case .ok(let date):
            "\(L10n.statusAllGood) · \(time(date))"
        case .paused(let until, _):
            L10n.statusPausedUntil(day(until))
        default:
            state.city
        }
    }

    private func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale)
        if let zone = TimeZone(identifier: state.timezone) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }

    private func day(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L10n.locale)
        if let zone = TimeZone(identifier: state.timezone) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }
}
