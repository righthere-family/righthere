import Foundation
import Observation

// MARK: - View Model

@Observable
@MainActor
final class HistoryViewModel {
    private(set) var parent: Parent = .sample
    private(set) var parents: [Parent] = []
    private(set) var selectedParentId: UUID?
    private(set) var monthAnchor: Date = .now
    private(set) var records: [DayRecord] = []
    private(set) var isLoading = true
    private(set) var trends: TrendsPayload?
    private(set) var isSibling = false
    private(set) var familyHasPlan = false
    var selectedRecord: DayRecord?

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }()

    // MARK: Loading

    func load(using service: any HistoryService) async {
        records = (try? await service.monthRecords(month: monthAnchor, parentId: selectedParentId)) ?? []
        isLoading = false
    }

    func loadFamily(using service: any CheckinService) async {
        guard let snapshot = try? await service.todaySnapshot() else { return }
        parents = snapshot.everyone.map(\.parent)
        if selectedParentId == nil {
            selectedParentId = parents.first?.id
        }
        parent = parents.first { $0.id == selectedParentId } ?? snapshot.parent
        // Siblings read the shared family entitlement, not their own StoreKit:
        // the owner's Family plan is what unlocks them.
        isSibling = (try? await FamilyAPI().myRole()) == "sibling"
        familyHasPlan = (try? await FamilyAPI().familyEntitlement()) != nil
    }

    var skeletonDayCount: Int {
        calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }

    func loadTrends() async {
        trends = try? await FamilyAPI().trends(parentId: selectedParentId)
    }

    func exportPDF() async -> URL? {
        let meds = (try? await FamilyAPI().meds(parentId: selectedParentId)) ?? []
        return DoctorReportPDF.render(
            parent: parent,
            monthTitle: monthTitle,
            records: records.filter { if case .upcoming = $0.mark { false } else { true } },
            meds: meds
        )
    }

    func select(_ member: Parent, using service: any HistoryService) async {
        guard selectedParentId != member.id else { return }
        selectedParentId = member.id
        parent = member
        await load(using: service)
    }

    func showPreviousMonth(using service: any HistoryService) async {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: monthAnchor) else { return }
        monthAnchor = previous
        await load(using: service)
    }

    func showNextMonth(using service: any HistoryService) async {
        guard canGoForward,
              let next = calendar.date(byAdding: .month, value: 1, to: monthAnchor) else { return }
        monthAnchor = next
        await load(using: service)
    }

    // MARK: Derived

    var canGoForward: Bool {
        !calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let title = formatter.string(from: monthAnchor)
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var leadingBlanks: Int {
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    var summary: String? {
        let tracked = records.filter { record in
            switch record.mark {
            case .upcoming: false
            default: true
            }
        }
        guard !tracked.isEmpty else { return nil }
        let good = tracked.filter { record in
            if case .allGood = record.mark { return true }
            return false
        }
        return L10n.historySummary(good.count, tracked.count)
    }

    func select(_ record: DayRecord) {
        if case .upcoming = record.mark { return }
        selectedRecord = record
    }
}
