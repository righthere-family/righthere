import SwiftUI

// MARK: - Day Detail

struct DayDetailView: View {
    let record: DayRecord
    let parent: Parent
    let monthAnchor: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dateTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)

            content

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Palette.background)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch record.mark {
        case .allGood(let time):
            Text(L10n.statusAllGood)
                .font(Typography.display(28))
                .foregroundStyle(Palette.okStrong)
            Text("\(time) · \(timezoneLabel)")
                .font(Typography.timestamp)
                .foregroundStyle(Palette.inkSecondary)
        case .notOk(let quote):
            Text(L10n.parentQuote(parent.displayName, quote ?? ""))
                .font(Typography.display(24))
                .foregroundStyle(Palette.alert)
            Text(L10n.historyDayHerWords)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        case .missed:
            Text(L10n.historyDayNoWord)
                .font(Typography.display(24))
                .foregroundStyle(Palette.ink)
            Text(L10n.historyDayNoWordNote)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        case .paused:
            Text(L10n.statusPaused)
                .font(Typography.display(24))
                .foregroundStyle(Palette.inkSecondary)
            Text(L10n.historyDayPausedNote)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        case .upcoming:
            EmptyView()
        }
    }

    // MARK: - Formatting

    private var dateTitle: String {
        var components = Calendar.current.dateComponents([.year, .month], from: monthAnchor)
        components.day = record.day
        guard let date = Calendar.current.date(from: components) else { return "\(record.day)" }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: L10n.locale))
    }

    private var timezoneLabel: String {
        String(format: String(localized: "status.cityTime"), parent.cityName)
    }
}
