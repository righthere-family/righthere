import SwiftUI
import Observation

// MARK: - Tabs

enum AppTab: Hashable {
    case today
    case history
    case family
}

// MARK: - Routes

enum Route: Hashable {
    case parentProfile(Parent.ID)
    case medications(Parent.ID)
    case escalation(Parent.ID)
    case inviteSibling
    case addParent
    case dates
    case stories
    case messages
    case paywall
    case settings
}

// MARK: - Router

@Observable
@MainActor
final class AppRouter {
    var tab: AppTab = .today
    var todayPath = NavigationPath()
    var historyPath = NavigationPath()
    var familyPath = NavigationPath()

    func push(_ route: Route) {
        switch tab {
        case .today: todayPath.append(route)
        case .history: historyPath.append(route)
        case .family: familyPath.append(route)
        }
    }

    func popToRoot() {
        switch tab {
        case .today: todayPath = NavigationPath()
        case .history: historyPath = NavigationPath()
        case .family: familyPath = NavigationPath()
        }
    }
}
