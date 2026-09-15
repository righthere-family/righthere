import Foundation

// MARK: - Parent

struct Parent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: Kind
    var gender: Gender
    var displayName: String
    var cityName: String
    var phone: String?
    var timezone: String
    var checkinTime: String
    var windowMinutes: Int
    var eveningTime: String?
    // The language the bot speaks to this parent: "ru" or "en".
    var botLanguage: String
    var reminders: Reminders = .on

    enum Kind: String, Codable, Sendable {
        case mom
        case dad
        case custom
    }

    // Whether the bot writes to this parent at all: paused for a while by
    // either side, or switched off by the family for good.
    enum Reminders: Codable, Hashable, Sendable {
        case on
        case paused(until: Date)
        case off
    }

    enum Gender: String, Codable, Sendable {
        case f
        case m
    }
}

// MARK: - Placeholder

extension Parent {
    static let placeholder = Parent(
        id: UUID(),
        kind: .mom,
        gender: .f,
        displayName: "",
        cityName: "",
        phone: nil,
        timezone: TimeZone.current.identifier,
        checkinTime: "09:00",
        windowMinutes: 180,
        eveningTime: nil,
        botLanguage: "ru"
    )
}

// MARK: - Sample

extension Parent {
    static let sample = Parent(
        id: UUID(),
        kind: .mom,
        gender: .f,
        displayName: String(localized: "parent.mom"),
        cityName: "Самара",
        phone: nil,
        timezone: "Europe/Samara",
        checkinTime: "09:00",
        windowMinutes: 180,
        eveningTime: nil,
        botLanguage: "ru"
    )
}
