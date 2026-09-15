import Foundation

// MARK: - Day Record

struct DayRecord: Identifiable, Equatable, Sendable {
    let day: Int
    let mark: DayMark

    var id: Int { day }
}

// MARK: - Day Mark

enum DayMark: Equatable, Sendable {
    case allGood(time: String)
    case notOk(quote: String?)
    case missed
    case paused
    // Nobody asked that day: the bot was off, blocked, or not yet writing.
    case off
    case upcoming
}
