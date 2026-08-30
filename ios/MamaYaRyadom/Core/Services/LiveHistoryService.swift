import Foundation

// MARK: - Live

struct LiveHistoryService: HistoryService {
    private let api = FamilyAPI()

    func monthRecords(month: Date, parentId: UUID?) async throws -> [DayRecord] {
        let calendar = Calendar(identifier: .gregorian)
        let payload = try await api.month(
            year: calendar.component(.year, from: month),
            month: calendar.component(.month, from: month),
            parentId: parentId
        )
        return payload.days.map { day in
            DayRecord(day: day.day, mark: Self.mark(for: day))
        }
    }

    private static func mark(for day: MonthPayload.Day) -> DayMark {
        switch day.mark {
        case "ok": .allGood(time: day.time ?? "")
        case "not_ok": .notOk(quote: day.quote)
        case "missed": .missed
        default: .upcoming
        }
    }
}
