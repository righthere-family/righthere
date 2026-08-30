import Foundation

// MARK: - Day Status

enum DayStatus: Equatable, Sendable {
    case ok(at: Date)
    case stillMorning(usualBy: Date?)
    case reminded(at: Date, deadline: Date)
    case quiet(since: Date?)
    case notOk(kind: NotOkKind, quote: String?)
    case paused(until: Date, reason: String?)
}

// MARK: - Not OK Kind

extension DayStatus {
    enum NotOkKind: String, Codable, Sendable {
        case health
        case mood
        case justDay = "just_day"
        case callMe = "call_me"
        case unspecified = "private"
    }
}
