import Foundation

// MARK: - Today Snapshot

struct TodaySnapshot: Sendable {
    struct Evening: Sendable, Equatable {
        var isOk: Bool
        var at: Date?
    }

    var parent: Parent
    var status: DayStatus
    var streak: Int
    var isWaitingParent = false
    var inviteCode: String?
    var medsTaken = 0
    var medsTotal = 0
    struct UpcomingDate: Sendable, Equatable {
        var title: String
        var daysLeft: Int
    }

    var evening: Evening?
    var upcomingDate: UpcomingDate?
    var others: [TodaySnapshot] = []

    var everyone: [TodaySnapshot] {
        [withOthers([])] + others
    }

    func withOthers(_ others: [TodaySnapshot]) -> TodaySnapshot {
        var copy = self
        copy.others = others
        return copy
    }
}
