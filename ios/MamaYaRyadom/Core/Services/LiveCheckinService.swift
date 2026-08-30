import Foundation

// MARK: - Live

struct LiveCheckinService: CheckinService {
    private let api = FamilyAPI()

    func todaySnapshot() async throws -> TodaySnapshot {
        try await api.snapshot()
    }

    func weekResults(parentId: UUID?, timezone: String) async throws -> [WeekDayResult] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let now = Date.now
        let current = try await api.month(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            parentId: parentId
        )
        guard let today = current.today else { return [] }

        var marks: [String] = []
        if today < 7, let previousAnchor = calendar.date(byAdding: .month, value: -1, to: now) {
            let previous = try await api.month(
                year: calendar.component(.year, from: previousAnchor),
                month: calendar.component(.month, from: previousAnchor),
                parentId: parentId
            )
            marks += previous.days.suffix(7 - today).map(\.mark)
        }
        marks += current.days.prefix(today).map(\.mark)

        return marks.suffix(7).map { mark in
            switch mark {
            case "ok": .ok
            case "not_ok": .alert
            case "missed": .missed
            case "today": .pending
            default: .blank
            }
        }
    }
}
