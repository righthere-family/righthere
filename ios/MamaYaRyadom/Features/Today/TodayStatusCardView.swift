import SwiftUI

struct TodayStatusCardView: View {
    
    let state: TodayCardState
    let onMedicationsTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(state.name) · \(state.city)")
                .font(Typography.cardTitle)
                .tracking(0.3)
                .foregroundStyle(Palette.inkSecondary)
            
            statusContent

            if let eveningIsOk = state.eveningIsOk {
                HStack(spacing: 6) {
                    Image(systemName: eveningIsOk ? "moon.stars" : "moon")
                        .font(.system(size: 12))
                    Text(eveningIsOk ? L10n.eveningCardOk : L10n.eveningCardNotOk)
                        .font(.system(size: 13))
                }
                .foregroundStyle(eveningIsOk ? Palette.okStrong : Palette.inkSecondary)
                .padding(.top, 10)
            }
            
            Spacer().frame(height: 26)
            Rectangle()
                .fill(Palette.accentBright.opacity(0.18))
                .frame(height: 1)
            Spacer().frame(height: 18)
            
            weekStrip
            
            if state.medicationsInfo.total > 0 {
                Spacer().frame(height: 22)
                medicationsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
        .animation(.snappy, value: state.status)
    }
    
    @ViewBuilder
    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state.status {
            case .ok(let date):
                statusTitle(L10n.statusAllGood, color: Palette.okStrong)
                statusSubtitle(L10n.statusTodayAt(time(date), state.city))
                StreakBadge(count: state.streak)
            case .stillMorning(let usualBy):
                statusTitle(L10n.statusStillMorning, color: Palette.ink)
                if let usualBy {
                    statusSubtitle(L10n.statusUsuallyBy(time(usualBy)))
                }
            case .reminded(let date, let deadline):
                statusTitle(L10n.statusReminded, color: Palette.warn)
                statusSubtitle("\(time(date)) · \(L10n.statusWaitingUntil(time(deadline)))")
            case .quiet:
                statusTitle(L10n.statusQuiet, color: Palette.ink)
                hint(L10n.statusQuietHint)
            case .notOk(let kind, let quote):
                if let quote, !quote.isEmpty {
                    Text(L10n.statusHerWords)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSecondary)
                    Text("«\(quote)»")
                        .font(Typography.quote)
                        .foregroundStyle(Palette.alert)
                        .lineSpacing(3)
                } else {
                    statusTitle(notOkTitle(kind), color: Palette.warn)
                }
            case .paused(let until, _):
                statusTitle(L10n.statusPaused, color: Palette.ink)
                statusSubtitle(L10n.statusPausedUntil(day(until)))
            }
        }
    }
    
    private func statusTitle(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.status)
            .foregroundStyle(color)
    }

    private func statusSubtitle(_ text: String) -> some View {
        Text(text)
            .font(Typography.timestamp)
            .foregroundStyle(Palette.inkSecondary)
    }
    
    private func notOkTitle(_ kind: DayStatus.NotOkKind) -> String {
        switch kind {
        case .health: L10n.statusNotOkHealth
        case .mood: L10n.statusNotOkMood
        case .justDay: L10n.statusNotOkJustDay
        case .callMe: L10n.statusNotOkCallMe
        case .unspecified: L10n.statusNotOkGeneric
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.inkSecondary)
            .lineSpacing(3)
    }
    
    // MARK: - Formatting

    private func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale)
        if let zone = TimeZone(identifier: state.timezone) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }
    
    private func day(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L10n.locale)
        style.timeZone = .gmt
        return date.formatted(style)
    }
    
    // MARK: - Week
    
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(state.weekdays) { day in
                VStack(spacing: 7) {
                    let color = day.isToday ? Palette.ink : Palette.inkSecondary.opacity(0.65)
                    Text(day.title)
                        .font(.system(size: 10.5))
                        .fontWeight(day.isToday ? .bold : .regular)
                        .foregroundStyle(color)
                    weekDot(day.result)
                        .frame(width: 9, height: 9)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(day.isToday ? Palette.background : .clear, in: .rect(cornerRadius: 12))
            }
        }
    }
    
    @ViewBuilder
    private func weekDot(_ result: WeekDayResult) -> some View {
        switch result {
        case .ok:
            Circle()
                .fill(Palette.okStrong)
        case .alert:
            ZStack {
                Circle()
                    .strokeBorder(Palette.alert.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Palette.alert)
                    .frame(width: 8, height: 8)
            }
        case .missed:
            Circle()
                .strokeBorder(Palette.inkSecondary.opacity(0.45), lineWidth: 1.3)
        case .pending:
            Circle()
                .fill(Palette.inkSecondary.opacity(0.28))
                .frame(width: 3, height: 3)
        case .blank:
            Circle()
                .fill(Palette.inkSecondary.opacity(0.12))
                .frame(width: 2.5, height: 2.5)
        }
    }
    
    // MARK: - Medications
    
    private var medicationsRow: some View {
        Button {
            onMedicationsTap?()
        } label: {
            HStack {
                Text(L10n.todayMedications)
                    .foregroundStyle(Palette.accent)
                    .fontWeight(.medium)
                Spacer()
                let medicationsInfo = state.medicationsInfo
                let todayTaken = L10n.todayMedicationsTaken(medicationsInfo.taken, medicationsInfo.total)
                let color = medicationsInfo.taken >= medicationsInfo.total ? Palette.okStrong : Palette.warn
                Text(todayTaken)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
            .font(.system(size: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
    
}

// MARK: - Preview

private var previewWeek: [TodayCardState.WeekDay] {
    let titles = ["пт", "сб", "вс", "пн", "вт", "ср", "чт"]
    let results: [WeekDayResult] = [.blank, .ok, .missed, .ok, .alert, .ok, .pending]
    return zip(titles, results).enumerated().map { offset, day in
        TodayCardState.WeekDay(
            id: .now.addingTimeInterval(Double(offset - 6) * 86_400),
            title: day.0,
            isToday: offset == 6,
            result: day.1
        )
    }
}

private func previewState(
    status: DayStatus,
    streak: Int = 0,
    meds: TodayCardState.MedicationsInfo = .init(taken: 1, total: 3)
) -> TodayCardState {
    TodayCardState(
        id: UUID(),
        name: "Мама",
        city: "Самара",
        timezone: "Europe/Samara",
        status: status,
        streak: streak,
        weekdays: previewWeek,
        medicationsInfo: meds,
        eveningIsOk: nil
    )
}

#Preview {
    ScrollView {
        VStack(spacing: 14) {
            TodayStatusCardView(
                state: previewState(status: .ok(at: .now), streak: 12, meds: .init(taken: 2, total: 2)),
                onMedicationsTap: {}
            )
            TodayStatusCardView(
                state: previewState(status: .ok(at: .now), streak: 30),
                onMedicationsTap: {}
            )
            TodayStatusCardView(
                state: previewState(status: .stillMorning(usualBy: .now.addingTimeInterval(3_600))),
                onMedicationsTap: {}
            )
            TodayStatusCardView(
                state: previewState(status: .notOk(kind: .health, quote: "Давление с утра, полежу немного")),
                onMedicationsTap: {}
            )
            TodayStatusCardView(
                state: previewState(status: .paused(until: .now.addingTimeInterval(3 * 86_400), reason: nil), meds: .init(taken: 0, total: 0)),
                onMedicationsTap: {}
            )
        }
        .padding(20)
    }
    .background(Palette.background)
}
