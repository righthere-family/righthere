import UIKit
import UserNotifications

// MARK: - Push Registrar

// Asks for notification permission only once a family exists: the first
// question the app asks must never be a system dialog.
@MainActor
enum PushRegistrar {
    static func requestAndRegister() async {
        guard AppConfig.hasFamily else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
        case .denied:
            return
        default:
            break
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func upload(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Xcode builds talk to the APNs sandbox; TestFlight and App Store
        // builds are Release and use production.
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "prod"
        #endif
        Task {
            try? await FamilyAPI().setPushToken(
                token,
                environment: environment,
                timezone: TimeZone.current.identifier,
                // Pushes from the worker arrive in the language this app
                // speaks; re-registered on every launch and language switch.
                language: L10n.effectiveLanguage
            )
        }
    }
}

// MARK: - App Delegate

final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.upload(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        NSLog("push registration failed: %@", String(describing: error))
        #endif
    }
}
