import Foundation
import UIKit
import AuthenticationServices
import SwiftUI

/// Sign-in state. Sign in with Apple is fully native.
/// Google sign-in and the sign-in email need the app's backend (see README "Accounts").
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    enum Provider: String { case apple, google, email }

    @AppStorage("auth.userID") private(set) var userID: String = ""
    @AppStorage("auth.name") private(set) var name: String = ""
    @AppStorage("auth.email") private(set) var email: String = ""
    @AppStorage("auth.provider") private(set) var provider: String = ""
    @Published var errorMessage: String?

    var isSignedIn: Bool { !userID.isEmpty }

    /// Backend base URL from Info.plist (DaylineAPIBaseURL). Empty = not set up yet.
    private var apiBase: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "DaylineAPIBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    // MARK: Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends name and email the first time; keep what we already have after that.
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            let token = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            await finish(userID: credential.user, name: fullName.isEmpty ? name : fullName,
                         email: credential.email ?? email, provider: .apple, idToken: token)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        }
    }

    // MARK: Google

    /// Needs a Google OAuth client ID and the GoogleSignIn package; until then this explains what's missing.
    func signInWithGoogle() async {
        guard Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String != nil else {
            errorMessage = "Google sign-in isn't set up in this test build yet. Use Sign in with Apple."
            return
        }
        // With the GoogleSignIn package added:
        // let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        // await finish(userID: result.user.userID!, name: result.user.profile?.name ?? "",
        //              email: result.user.profile?.email ?? "", provider: .google, idToken: result.user.idToken?.tokenString)
    }

    // MARK: Shared

    /// Test/demo builds: sign in as a sample user so the flow can be shown without an account.
    func signInDemo(provider: Provider = .apple) async {
        await finish(userID: "demo", name: "Alex", email: "alex@example.com", provider: provider, idToken: nil)
    }

    private func finish(userID: String, name: String, email: String, provider: Provider, idToken: String?) async {
        self.userID = userID
        self.name = name
        self.email = email
        self.provider = provider.rawValue
        await sendSignInEmail(idToken: idToken, provider: provider)
    }

    /// Asks the backend to email the user: a welcome email the first time, a "new sign-in" notice after that.
    /// The server verifies the Apple/Google ID token before sending, so the app never holds email credentials.
    private func sendSignInEmail(idToken: String?, provider: Provider) async {
        guard let apiBase, let idToken, !email.isEmpty else { return }
        var request = URLRequest(url: apiBase.appending(path: "v1/auth/signed-in"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "provider": provider.rawValue,
            "id_token": idToken,
            "device": UIDevice.current.model,
            "time_zone": TimeZone.current.identifier
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    func signOut() {
        userID = ""; name = ""; email = ""; provider = ""
    }

    /// Deletes the account on the server (when a backend is set up) and signs out.
    /// Apple requires in-app account deletion for apps with sign-in.
    func deleteAccount() async {
        if let apiBase, !userID.isEmpty, userID != "demo" {
            var request = URLRequest(url: apiBase.appending(path: "v1/account"))
            request.httpMethod = "DELETE"
            request.setValue(userID, forHTTPHeaderField: "X-User-ID")
            _ = try? await URLSession.shared.data(for: request)
        }
        signOut()
    }
}
