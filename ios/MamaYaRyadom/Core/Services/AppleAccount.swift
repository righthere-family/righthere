import AuthenticationServices
import CryptoKit
import Foundation
import Security
import Supabase

// MARK: - Apple Account

// The account behind the app is anonymous, so a phone that loses its
// keychain loses the family. Tying an Apple ID to that account keeps the
// user id and everything attached to it; a new phone then signs in with the
// same Apple ID and finds the family again.
enum AppleAccount {
    // Sign in with Apple wants the hash in the request and Supabase wants the
    // original to check the token against it.
    struct Attempt {
        let nonce: String
        let hashedNonce: String

        init() {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            nonce = bytes.map { String(format: "%02x", $0) }.joined()
            hashedNonce = SHA256.hash(data: Data(nonce.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    enum LinkOutcome {
        case linked
        case taken
        case failed
    }

    static var isLinked: Bool {
        guard let user = SupabaseHub.client?.auth.currentSession?.user else { return false }
        return user.identities?.contains { $0.provider == "apple" } == true
    }

    static func credentials(
        _ result: Result<ASAuthorization, any Error>,
        attempt: Attempt
    ) -> OpenIDConnectCredentials? {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return OpenIDConnectCredentials(provider: .apple, idToken: token, nonce: attempt.nonce)
    }

    static func wasCancelled(_ result: Result<ASAuthorization, any Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        return (error as? ASAuthorizationError)?.code == .canceled
    }

    // Keeps the current user id, so memberships, purchases and history stay.
    static func link(_ credentials: OpenIDConnectCredentials) async -> LinkOutcome {
        guard let client = SupabaseHub.client else { return .failed }
        do {
            if client.auth.currentSession == nil {
                try await client.auth.signInAnonymously()
            }
            _ = try await client.auth.linkIdentityWithIdToken(credentials: credentials)
            return .linked
        } catch let error as AuthError where error.errorCode == .identityAlreadyExists {
            return .taken
        } catch {
            return .failed
        }
    }

    // A fresh phone: the session becomes the account behind this Apple ID.
    static func signIn(_ credentials: OpenIDConnectCredentials) async -> Bool {
        guard let client = SupabaseHub.client else { return false }
        return (try? await client.auth.signInWithIdToken(credentials: credentials)) != nil
    }
}
