import SwiftUI

@main
struct MamaApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var router = AppRouter()

    init() {
        AppConfig.syncShared()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.dependencies, .live)
                .tint(Palette.accent)
        }
    }
}
