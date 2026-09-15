import Foundation

// MARK: - Day Status

enum DayStatus: Equatable, Sendable {
    case ok(at: Date)
    case stillMorning(usualBy: Date?)
    case reminded(at: Date, deadline: Date)
    case quiet(since: Date?, signal: Signal?)
    case notOk(kind: NotOkKind, quote: String?)
    case paused(until: Date, reason: String?)
    case blocked
    case archived
}

// MARK: - Signal

// A sign of life on a morning without the button: a message, a voice note,
// a photo, or a medication marked as taken.
extension DayStatus {
    struct Signal: Equatable, Sendable {
        enum Kind: String, Sendable {
            case text
            case voice
            case photo
            case med
        }

        let kind: Kind
        let at: Date
    }
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
