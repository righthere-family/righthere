import SwiftUI

// MARK: - Trends Card

// Premium answers the question a glance cannot: is anything slowly changing?
// Not tappable by design — it is a reading, not a door; rows with icons keep
// it from looking like a button.
struct TrendsCard: View {
    let trends: TrendsPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.trendsTitle)
                    .font(Typography.display(22))
                    .foregroundStyle(Palette.ink)
                Text(L10n.trendsPeriod)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.8))
            }

            if let usual = usualLine {
                row(icon: "clock", tint: Palette.accentBright) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(usual)
                            .foregroundStyle(Palette.ink)
                        if let shift = shiftLine {
                            Text(shift)
                                .foregroundStyle(shiftColor)
                        }
                    }
                }
                if let missed = trends?.missed30d {
                    row(
                        icon: missed == 0 ? "checkmark.circle" : "circle.dashed",
                        tint: missed == 0 ? Palette.okStrong : Palette.warn
                    ) {
                        Text(L10n.trendsMissed(missed))
                            .foregroundStyle(missed == 0 ? Palette.okStrong : Palette.ink)
                    }
                }
            } else {
                row(icon: "hourglass", tint: Palette.inkSecondary) {
                    Text(L10n.trendsEmpty)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    private func row(icon: String, tint: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
            content()
                .font(.system(size: 14))
        }
    }

    private var usualLine: String? {
        guard let minute = trends?.recentAvgMinute else { return nil }
        return L10n.trendsUsualTime(String(format: "%d:%02d", minute / 60, minute % 60))
    }

    private var shiftLine: String? {
        guard let shift = trends?.shiftMinutes else { return nil }
        if abs(shift) < 15 { return L10n.trendsShiftNone }
        return shift > 0 ? L10n.trendsShiftLater(shift) : L10n.trendsShiftEarlier(-shift)
    }

    private var shiftColor: Color {
        guard let shift = trends?.shiftMinutes, abs(shift) >= 15 else { return Palette.inkSecondary }
        return shift > 0 ? Palette.warn : Palette.okStrong
    }
}
