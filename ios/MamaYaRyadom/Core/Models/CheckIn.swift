import Foundation

// MARK: - Check-in

struct CheckIn: Identifiable, Codable, Sendable {
    let id: UUID
    let parentID: UUID
    let localDate: String
    let status: Status
    let source: Source
    let createdAt: Date

    enum Status: String, Codable, Sendable {
        case ok
        case notOk = "not_ok"
        case accidentalOk = "accidental_ok"
    }

    enum Source: String, Codable, Sendable {
        case button
        case text
        case voice
        case reaction
        case late
    }
}
