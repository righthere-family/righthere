import Foundation

// MARK: - Unread Messages

enum UnreadMessages {
    private static let seenKey = "messagesSeenAt"

    static func count() async -> Int {
        guard AppConfig.hasFamily else { return 0 }
        let seenAt = seenAt
        let feed = (try? await FamilyAPI().parentMessages(limit: 30)) ?? []
        return feed.filter { $0.createdAt > seenAt }.count
    }

    static var seenAt: Date {
        UserDefaults.standard.object(forKey: seenKey) as? Date ?? .distantPast
    }

    static func markSeen(through latest: Date?) {
        let stamp = max(Date(), latest ?? .distantPast)
        UserDefaults.standard.set(stamp, forKey: seenKey)
    }
}
