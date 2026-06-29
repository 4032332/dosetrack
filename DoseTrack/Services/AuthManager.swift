// DoseTrack/Services/AuthManager.swift
import SwiftUI
import Supabase
import AuthenticationServices
import GoogleSignIn

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    let client = SupabaseClient(
        supabaseURL: URL(string: Secrets.supabaseURL)!,
        supabaseKey: Secrets.supabaseAnonKey
    )

    @Published var session: Session? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var isSignedIn: Bool { session != nil }
    var isGuest: Bool { session?.user.isAnonymous == true }

    private init() {
        Task { await refreshSession() }
    }

    // MARK: - Session

    func refreshSession() async {
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    // MARK: - Email / Password

    /// Returns `true` if the user needs to confirm their email before the session is active.
    @discardableResult
    func signUp(email: String, password: String, fullName: String) async -> Bool {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": AnyJSON(stringLiteral: fullName)]
            )
            if let s = response.session {
                // Email confirmations disabled in Supabase — session granted immediately
                session = s
                return false
            } else {
                // Supabase returned no session — email confirmation required
                return true
            }
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            session = try await client.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func resetPassword(email: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.resetPasswordForEmail(email)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Guest / Anonymous

    /// Signs in anonymously so the user can use the app without creating an account.
    /// Their data is stored locally; they can upgrade to a full account later.
    func continueAsGuest() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            session = try await client.auth.signInAnonymously()
        } catch {
            // If anonymous auth is disabled in Supabase, fall back to a local-only flag
            errorMessage = nil
            UserDefaults.standard.set(true, forKey: "guestMode")
            // Publish a synthetic signed-in state so RootView advances
            session = nil
            NotificationCenter.default.post(name: .guestModeActivated, object: nil)
        }
    }

    // MARK: - Apple Sign In

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            errorMessage = "Apple Sign In failed — missing token."
            return
        }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: token, nonce: nil)
            )
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle(presenting viewController: UIViewController) async {
        guard !Secrets.googleClientID.isEmpty else {
            errorMessage = "Google Sign-In is not configured yet. Please use email to sign in."
            return
        }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Secrets.googleClientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google Sign In failed — missing ID token."
                return
            }
            session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
        } catch GIDSignInError.canceled { /* user dismissed */ }
        catch { errorMessage = friendlyError(error) }
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        UserDefaults.standard.removeObject(forKey: "guestMode")
        do {
            try await client.auth.signOut()
        } catch { /* session cleared locally regardless */ }
        session = nil
    }

    // MARK: - Profile

    var displayName: String {
        let meta = session?.user.userMetadata
        if let name = meta?["full_name"]?.stringValue, !name.isEmpty { return name }
        if let name = meta?["name"]?.stringValue, !name.isEmpty { return name }
        if isGuest { return "Guest" }
        return session?.user.email?.components(separatedBy: "@").first ?? "User"
    }

    var userEmail: String {
        isGuest ? "Guest account" : (session?.user.email ?? "")
    }

    // MARK: - Error strings

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("invalid login") || msg.contains("invalid credentials") {
            return "Incorrect email or password."
        }
        if msg.contains("already registered") || msg.contains("already exists") {
            return "An account with that email already exists. Try signing in instead."
        }
        if msg.contains("email not confirmed") {
            return "Please confirm your email first, then sign in."
        }
        if msg.contains("network") || msg.contains("offline") || msg.contains("connection") {
            return "No internet connection. Check your network and try again."
        }
        return error.localizedDescription
    }
}

// MARK: - Notification for guest mode fallback

extension Notification.Name {
    static let guestModeActivated = Notification.Name("guestModeActivated")
}
