import Foundation

// MARK: - Widget Snapshot

struct WidgetSnapshot: Decodable, Sendable {
    let parent: ParentInfo
    let status: StatusInfo
    let streak: Int

    struct ParentInfo: Decodable, Sendable {
        let displayName: String
        let city: String?
        let timezone: String
    }

    struct StatusInfo: Decodable, Sendable {
        let state: String
        let at: Date?
        let quote: String?
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot?.self, from: data) ?? nil
    }
}
