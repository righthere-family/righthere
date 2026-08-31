import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("appLanguage") private var appLanguage = ""
    @AppStorage("appTheme") private var appTheme = "light"
    @State private var isLaunching = true

    var body: some View {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "designProbe"),
           let variant = ProbeVariant(rawValue: raw) {
            let state = ProbeState(rawValue: UserDefaults.standard.string(forKey: "probeState") ?? "ok") ?? .ok
            ProbeHost(variant: variant, state: state)
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder
    private var main: some View {
        ZStack {
            Group {
                if onboardingDone {
                    tabs
                        .transition(.opacity)
                        .zIndex(0)
                } else {
                    OnboardingView(done: $onboardingDone)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // L10n resolves lazily against the selected bundle; rebuilding the
            // tree on change is what makes the switch instant.
            .id(appLanguage)
            .offset(y: isLaunching ? 12 : 0)
            .animation(.easeOut(duration: 0.5), value: isLaunching)
            if isLaunching {
                LaunchOverlay(isPresented: $isLaunching)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: onboardingDone)
        .preferredColorScheme(preferredScheme)
        .onChange(of: appLanguage) { _, newValue in
            // The widget lives in another process: hand it the choice through
            // the app group and ask it to redraw in the new language.
            SharedStore.appLanguage = newValue
            WidgetCenter.shared.reloadAllTimelines()
            // The server pushes in the language registered with the token, so
            // a language switch re-registers it.
            Task { await PushRegistrar.requestAndRegister() }
        }
        .onOpenURL { url in
            guard url.scheme == "righthere", url.host() == "join" else { return }
            let token = url.lastPathComponent.lowercased()
            guard UUID(uuidString: token) != nil, !AppConfig.hasFamily else { return }
            AppConfig.storeFamilyToken(token)
            onboardingDone = true
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appTheme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    // MARK: - Tabs

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            NavigationStack(path: $router.todayPath) {
                TodayView()
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(L10n.tabToday, systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack(path: $router.historyPath) {
                HistoryView()
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(L10n.tabHistory, systemImage: "calendar") }
            .tag(AppTab.history)

            NavigationStack(path: $router.familyPath) {
                FamilyView()
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(L10n.tabFamily, systemImage: "person.2") }
            .tag(AppTab.family)
        }
        // Permission is asked here, past onboarding, when a family exists —
        // the first thing the app says must never be a system dialog.
        .task { await PushRegistrar.requestAndRegister() }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .parentProfile(let id):
            ParentEditView(parentId: id)
        case .medications(let id):
            MedsView(parentId: id)
        case .escalation:
            PlaceholderScreen(title: L10n.routeEscalation)
        case .addParent:
            AddParentView()
        case .dates:
            DatesView()
        case .stories:
            StoriesView()
        case .messages:
            MessagesView()
        case .inviteSibling:
            PlaceholderScreen(title: L10n.routeInviteSibling)
        case .paywall:
            PaywallView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Placeholder

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
    }
}
