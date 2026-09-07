import Foundation

// MARK: - Unread Messages

enum UnreadMessages {
    private static let seenKey = "messagesSeenAt"

    static func count() async -> Int {
        guard AppConfig.hasFamily else { return 0 }
        let seenAt = UserDefaults.standard.object(forKey: seenKey) as? Date ?? .distantPast
        let feed = (try? await FamilyAPI().parentMessages(limit: 30)) ?? []
        return feed.filter { $0.createdAt > seenAt }.count
    }

    static func markSeen() {
        UserDefaults.standard.set(Date(), forKey: seenKey)
    }
}
