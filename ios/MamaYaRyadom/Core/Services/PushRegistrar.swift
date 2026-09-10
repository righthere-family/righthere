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
    @MainActor private static var pending: (category: String, parentId: String?)?

    @MainActor static var onOpen: ((String, String?) -> Void)? {
        didSet {
            if let pending, let onOpen {
                Self.pending = nil
                onOpen(pending.category, pending.parentId)
            }
        }
    }

    @MainActor private static func open(_ category: String, parentId: String?) {
        if let onOpen {
            onOpen(category, parentId)
        } else {
            pending = (category, parentId)
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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


// MARK: - Foreground Notifications

extension PushAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let parentId = content.userInfo["parent_id"] as? String
        await MainActor.run { Self.open(category, parentId: parentId) }
    }
}
