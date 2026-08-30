import Foundation

// MARK: - Service

protocol HistoryService: Sendable {
    func monthRecords(month: Date, parentId: UUID?) async throws -> [DayRecord]
}

// MARK: - Mock

struct MockHistoryService: HistoryService {
    func monthRecords(month: Date, parentId: UUID?) async throws -> [DayRecord] {
        let calendar = Calendar.current
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let isCurrentMonth = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        let today = calendar.component(.day, from: .now)

        return (1...dayCount).map { day in
            if isCurrentMonth && day > today {
                return DayRecord(day: day, mark: .upcoming)
            }
            return DayRecord(day: day, mark: Self.mark(for: day))
        }
    }

    private static func mark(for day: Int) -> DayMark {
        switch (day % 13, day % 10) {
        case (6, _): .notOk(quote: String(localized: "demo.notOkQuote"))
        case (_, 9): .missed
        case (_, 4) where day > 20: .paused
        default: .allGood(time: "9:\(String(format: "%02d", (day * 7) % 50 + 2))")
        }
    }
}
