import Foundation
import Supabase

// MARK: - Hub

enum SupabaseHub {
    static let client: SupabaseClient? = {
        guard AppConfig.isLiveConfigured, let url = AppConfig.supabaseURL else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}
