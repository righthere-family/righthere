import Foundation

// MARK: - App Config

enum AppConfig {
    static var supabaseURL: URL? {
        URL(string: infoValue("SupabaseURL"))
    }

    static var supabaseAnonKey: String {
        infoValue("SupabaseAnonKey")
    }

    static var botHandle: String {
        infoValue("BotHandle")
    }

    static var joinBaseURL: String {
        infoValue("JoinBaseURL")
    }

    static var familyToken: String {
        let created = UserDefaults.standard.string(forKey: "createdFamilyToken") ?? ""
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceSetup") {
            return created
        }
        #endif
        return created.isEmpty ? infoValue("FamilyToken") : created
    }

    static var hasFamily: Bool {
        !familyToken.isEmpty
    }

    static var isLiveConfigured: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty
    }

    static func storeFamilyToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "createdFamilyToken")
        syncShared()
    }

    static func clearFamily() {
        UserDefaults.standard.removeObject(forKey: "createdFamilyToken")
        syncShared()
    }

    static func syncShared() {
        SharedStore.supabaseURL = infoValue("SupabaseURL")
        SharedStore.supabaseAnonKey = supabaseAnonKey
        SharedStore.familyToken = familyToken
        SharedStore.appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    }

    private static func infoValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
