import SwiftUI

// MARK: - Container

struct AppDependencies: Sendable {
    var checkinService: any CheckinService
    var historyService: any HistoryService
    var familyUpdates: any FamilyLiveUpdates

    static let live: AppDependencies = AppConfig.isLiveConfigured
        ? AppDependencies(
            checkinService: LiveCheckinService(),
            historyService: LiveHistoryService(),
            familyUpdates: RealtimeFamilyUpdates()
        )
        : .preview

    static let preview = AppDependencies(
        checkinService: MockCheckinService(),
        historyService: MockHistoryService(),
        familyUpdates: MockFamilyUpdates()
    )
}

// MARK: - Environment

private struct DependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.preview
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}
