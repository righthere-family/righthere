import Foundation
import Supabase

// MARK: - Service

protocol FamilyLiveUpdates: Sendable {
    func stream() async -> AsyncStream<Void>
}

// MARK: - Realtime

struct RealtimeFamilyUpdates: FamilyLiveUpdates {
    private static let teardown = TeardownBox()

    func stream() async -> AsyncStream<Void> {
        guard let client = SupabaseHub.client, AppConfig.hasFamily else {
            return AsyncStream { $0.finish() }
        }
        await Self.teardown.replace(with: nil)?.value
        let channel = client.channel("family:\(AppConfig.familyToken)")
        let broadcasts = channel.broadcastStream(event: "family_update")

        return AsyncStream { continuation in
            let events = Task {
                for await _ in broadcasts {
                    continuation.yield(())
                }
            }
            let membership = Task {
                while !Task.isCancelled {
                    do {
                        try await channel.subscribeWithError()
                    } catch {
                        try? await Task.sleep(for: .seconds(5))
                        continue
                    }
                    continuation.yield(())
                    var lost = false
                    for await status in channel.statusChange {
                        if status == .subscribed {
                            continuation.yield(())
                        } else if status == .unsubscribed {
                            lost = true
                            break
                        }
                    }
                    if !lost { break }
                }
            }
            continuation.onTermination = { _ in
                events.cancel()
                membership.cancel()
                Self.teardown.replace(with: Task { await client.removeChannel(channel) })
            }
        }
    }
}

// MARK: - Teardown Box

private final class TeardownBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    @discardableResult
    func replace(with newTask: Task<Void, Never>?) -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        let previous = task
        task = newTask
        return previous
    }
}

// MARK: - Mock

struct MockFamilyUpdates: FamilyLiveUpdates {
    func stream() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
