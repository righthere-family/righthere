import Foundation

// MARK: - Shared Store

enum SharedStore {
    static let suiteName = "group.family.righthere.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static var supabaseURL: String {
        get { defaults?.string(forKey: "supabaseURL") ?? "" }
        set { defaults?.set(newValue, forKey: "supabaseURL") }
    }

    static var supabaseAnonKey: String {
        get { defaults?.string(forKey: "supabaseAnonKey") ?? "" }
        set { defaults?.set(newValue, forKey: "supabaseAnonKey") }
    }

    static var familyToken: String {
        get { defaults?.string(forKey: "familyToken") ?? "" }
        set { defaults?.set(newValue, forKey: "familyToken") }
    }

    static var cachedSnapshot: Data? {
        get { defaults?.data(forKey: "cachedSnapshot") }
        set { defaults?.set(newValue, forKey: "cachedSnapshot") }
    }

    // The in-app language override ("" = system). The widget runs in its own
    // process and cannot see the app's UserDefaults, so the choice rides the
    // app group — otherwise a Russian app sits next to an English widget.
    static var appLanguage: String {
        get { defaults?.string(forKey: "appLanguage") ?? "" }
        set { defaults?.set(newValue, forKey: "appLanguage") }
    }
}
