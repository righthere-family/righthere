import Foundation

// MARK: - Service

protocol CheckinService: Sendable {
    func todaySnapshot() async throws -> TodaySnapshot
    func weekResults(parentId: UUID?, timezone: String) async throws -> [WeekDayResult]
}

// MARK: - Week Result

enum WeekDayResult: Sendable {
    case ok
    case alert
    case missed
    case pending
    case blank
}

// MARK: - Mock

struct MockCheckinService: CheckinService {
    func todaySnapshot() async throws -> TodaySnapshot {
        TodaySnapshot(parent: .sample, status: .ok(at: .now), streak: 12)
    }

    func weekResults(parentId: UUID?, timezone: String) async throws -> [WeekDayResult] {
        [.ok, .ok, .ok, .alert, .ok, .ok, .pending]
    }
}
