// DoseTrack/Services/AuthManager.swift
// Wraps Supabase Auth — handles email/password, Apple Sign In, and Google Sign In.
import SwiftUI
import Supabase
import AuthenticationServices
import GoogleSignIn

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    // Supabase client — shared across the app
    let client = SupabaseClient(
        supabaseURL: URL(string: Secrets.supabaseURL)!,
        supabaseKey: Secrets.supabaseAnonKey
    )

    @Published var session: Session? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var isSignedIn: Bool { session != nil }

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

    func signUp(email: String, password: String, fullName: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": AnyJSON(stringLiteral: fullName)]
            )
            session = response.session  // AuthResponse.session: Session?
        } catch {
            errorMessage = friendlyError(error)
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
            errorMessage = nil
        } catch {
            errorMessage = friendlyError(error)
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
                credentials: .init(
                    provider: .apple,
                    idToken: token,
                    nonce: nil
                )
            )
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle(presenting viewController: UIViewController) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

        do {
            let config = GIDConfiguration(clientID: Secrets.googleClientID)
            GIDSignIn.sharedInstance.configuration = config

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
        } catch GIDSignInError.canceled {
            // User tapped Cancel — not an error worth showing
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Profile

    /// Returns the user's display name from metadata or email prefix.
    var displayName: String {
        let meta = session?.user.userMetadata
        if let name = meta?["full_name"]?.stringValue, !name.isEmpty { return name }
        if let name = meta?["name"]?.stringValue, !name.isEmpty { return name }
        return session?.user.email?.components(separatedBy: "@").first ?? "User"
    }

    var userEmail: String { session?.user.email ?? "" }

    // MARK: - Helpers

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("invalid login") || msg.contains("invalid credentials") {
            return "Incorrect email or password."
        }
        if msg.contains("already registered") || msg.contains("already exists") {
            return "An account with that email already exists. Try signing in."
        }
        if msg.contains("network") || msg.contains("offline") {
            return "No internet connection. Please check your network and try again."
        }
        return error.localizedDescription
    }
}
