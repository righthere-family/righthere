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
            guard granted else {
                await FamilyAPI().setPushDenied()
                return
            }
        case .denied:
            await FamilyAPI().setPushDenied()
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
        Self.registerCategories()
        return true
    }

    private static func registerCategories() {
        let wave = UNNotificationAction(identifier: "WAVE", title: L10n.pushActionWave, options: [])
        let checkin = UNNotificationCategory(identifier: "CHECKIN_OK", actions: [wave], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([checkin])
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


// MARK: - Notification Delegate

// The system hands over its completion blocks without a Sendable mark; this
// carries one onto the main actor, the only place UIKit accepts it.
private struct NotificationCompletion: @unchecked Sendable {
    let run: () -> Void
}

extension PushAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // UIKit finishes a notification response by refreshing the app snapshot
    // and asserts that this happens on the main thread. The async form of
    // this method returned its completion from a background executor, which
    // aborted the app whenever the response was handled before the scene was
    // active: a cold start from a tap, or the wave action.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let parentId = content.userInfo["parent_id"] as? String
        let isWave = response.actionIdentifier == "WAVE"
        let completion = NotificationCompletion(run: completionHandler)
        Task { @MainActor in
            if isWave {
                if let parentId, let id = UUID(uuidString: parentId) {
                    _ = try? await FamilyAPI().wave(parentId: id)
                }
            } else {
                Self.open(category, parentId: parentId)
            }
            completion.run()
        }
    }
}
