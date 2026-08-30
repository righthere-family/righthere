import SwiftUI

// MARK: - History

struct HistoryView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model = HistoryViewModel()
    @State private var isShowingPaywall = false
    @State private var reportURL: URL?
    private let purchases = PurchaseModel.shared

    private var hasPremium: Bool {
        purchases.hasSubscription || model.familyHasPlan
    }

    private var isSiblingLocked: Bool {
        model.isSibling && !model.familyHasPlan
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                parentSwitcher
                if isSiblingLocked {
                    PremiumHintCard(
                        title: L10n.siblingLocked,
                        hint: L10n.siblingLockedHint
                    ) {
                        isShowingPaywall = true
                    }
                } else {
                    calendarCard
                    premiumTail
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .background(Palette.background)
        .rootToolbar(title: L10n.tabHistory)
        .task {
            // Two parallel waves instead of four sequential jumps: the layout
            // settles once per wave, not once per request.
            async let familyLoaded: Void = model.loadFamily(using: dependencies.checkinService)
            async let purchasesLoaded: Void = purchases.load()
            _ = await (familyLoaded, purchasesLoaded)
            async let monthLoaded: Void = model.load(using: dependencies.historyService)
            async let trendsLoaded: Void = hasPremium ? model.loadTrends() : ()
            _ = await (monthLoaded, trendsLoaded)
        }
        .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
        .sheet(item: $model.selectedRecord) { record in
            DayDetailView(record: record, parent: model.parent, monthAnchor: model.monthAnchor)
                .presentationDetents([.height(280)])
        }
    }

    private var calendarCard: some View {
        Group {
                VStack(spacing: 16) {
                    monthSwitcher
                    weekdayHeader
                    if model.isLoading {
                        loadingGrid
                    } else {
                        monthGrid
                    }
                    if let summary = model.summary {
                        Rectangle()
                            .fill(Palette.accentBright.opacity(0.18))
                            .frame(height: 1)
                        summaryLine(summary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .background(Palette.card, in: .rect(cornerRadius: 24))
                .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
                .animation(.easeOut(duration: 0.25), value: model.isLoading)

                Spacer().frame(height: 14)
                legend
                    .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var premiumTail: some View {
        Spacer().frame(height: 14)
        if hasPremium {
            TrendsCard(trends: model.trends)
            Spacer().frame(height: 12)
            exportRow
        } else {
            PremiumHintCard(
                title: L10n.trendsPremium,
                hint: L10n.trendsPremiumHint
            ) {
                isShowingPaywall = true
            }
        }
        Spacer().frame(height: 28)
    }

    private var exportRow: some View {
        Button {
            Task { reportURL = await model.exportPDF() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                Text(L10n.exportButton)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Palette.card, in: .rect(cornerRadius: 18))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .sheet(item: $reportURL) { url in
            ShareSheet(url: url)
        }
    }

    // MARK: - Whose History

    @ViewBuilder
    private var parentSwitcher: some View {
        if model.parents.count > 1 {
            HStack(spacing: 8) {
                ForEach(model.parents) { member in
                    let isSelected = member.id == model.selectedParentId
                    Button {
                        Task { await model.select(member, using: dependencies.historyService) }
                    } label: {
                        Text(member.displayName)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isSelected ? Palette.accent : Palette.card, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Month Switcher

    private var monthSwitcher: some View {
        HStack {
            Button {
                if purchases.hasSubscription {
                    Task { await model.showPreviousMonth(using: dependencies.historyService) }
                } else {
                    isShowingPaywall = true
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            Spacer()
            Text(model.monthTitle)
                .font(Typography.display(26))
                .foregroundStyle(Palette.ink)
            Spacer()
            Button {
                Task { await model.showNextMonth(using: dependencies.historyService) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.canGoForward ? Palette.accent : Palette.inkSecondary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .disabled(!model.canGoForward)
        }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(-model.leadingBlanks..<0, id: \.self) { _ in
                Color.clear.frame(height: 46)
            }
            ForEach(1...model.skeletonDayCount, id: \.self) { day in
                DayCell(record: DayRecord(day: day, mark: .upcoming))
            }
        }
        .skeleton()
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(-model.leadingBlanks..<0, id: \.self) { _ in
                Color.clear.frame(height: 46)
            }
            ForEach(model.records) { record in
                DayCell(record: record)
                    .onTapGesture { model.select(record) }
            }
        }
    }

    // MARK: - Summary

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.display(20))
            .foregroundStyle(Palette.okStrong)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(L10n.statusAllGood) { Circle().fill(Palette.okStrong) }
            legendItem(L10n.historyLegendHerWords) { RoundedRectangle(cornerRadius: 2).fill(Palette.alert) }
            legendItem(L10n.historyLegendQuiet) { Circle().strokeBorder(Palette.inkSecondary.opacity(0.5), lineWidth: 1.5) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ title: String, @ViewBuilder shape: () -> some View) -> some View {
        HStack(spacing: 6) {
            shape().frame(width: 9, height: 9)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let record: DayRecord

    var body: some View {
        VStack(spacing: 5) {
            Text("\(record.day)")
                .font(.system(size: 13))
                .foregroundStyle(numberColor)
            mark
                .frame(width: 11, height: 11)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(cellBackground, in: .rect(cornerRadius: 10))
    }

    private var numberColor: Color {
        if case .upcoming = record.mark { return Palette.inkSecondary.opacity(0.35) }
        return Palette.ink
    }

    private var cellBackground: Color {
        switch record.mark {
        case .allGood: Palette.okTint
        case .notOk: Palette.alertTint
        default: .clear
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch record.mark {
        case .allGood:
            Circle().fill(Palette.okStrong)
        case .notOk:
            RoundedRectangle(cornerRadius: 2.5).fill(Palette.alert)
        case .missed:
            Circle().strokeBorder(Palette.inkSecondary.opacity(0.5), lineWidth: 1.5)
        case .paused:
            Capsule().fill(Palette.inkSecondary.opacity(0.6)).frame(width: 9, height: 3)
        case .upcoming:
            Color.clear
        }
    }
}

#Preview {
    NavigationStack { HistoryView() }
        .environment(AppRouter())
}
