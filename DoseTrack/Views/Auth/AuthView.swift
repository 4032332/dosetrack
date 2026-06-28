// DoseTrack/Views/Auth/AuthView.swift
// Sign-in / sign-up screen. Shown before onboarding for new sessions.
import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct AuthView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var confirmPassword = ""
    @State private var showingReset = false
    @FocusState private var focused: Field?

    enum Mode { case signIn, signUp }
    enum Field: Hashable { case name, email, password, confirm }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Logo
                    VStack(spacing: 10) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue.gradient)
                        Text("DoseTrack")
                            .font(.largeTitle.bold())
                        Text("Never miss a dose.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                    // Mode toggle
                    Picker("", selection: $mode) {
                        Text("Sign In").tag(Mode.signIn)
                        Text("Create Account").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                    // Form fields
                    VStack(spacing: 14) {
                        if mode == .signUp {
                            AuthTextField(
                                placeholder: "Full name",
                                text: $fullName,
                                icon: "person.fill",
                                contentType: .name
                            )
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .email }
                        }

                        AuthTextField(
                            placeholder: "Email address",
                            text: $email,
                            icon: "envelope.fill",
                            contentType: .emailAddress,
                            keyboardType: .emailAddress
                        )
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                        AuthTextField(
                            placeholder: "Password",
                            text: $password,
                            icon: "lock.fill",
                            contentType: mode == .signIn ? .password : .newPassword,
                            isSecure: true
                        )
                        .focused($focused, equals: .password)
                        .submitLabel(mode == .signUp ? .next : .go)
                        .onSubmit {
                            if mode == .signUp { focused = .confirm }
                            else { submitEmailAction() }
                        }

                        if mode == .signUp {
                            AuthTextField(
                                placeholder: "Confirm password",
                                text: $confirmPassword,
                                icon: "lock.fill",
                                contentType: .newPassword,
                                isSecure: true
                            )
                            .focused($focused, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit { submitEmailAction() }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Validation / error
                    if let err = auth.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    // Forgot password
                    if mode == .signIn {
                        Button("Forgot password?") { showingReset = true }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    // Primary CTA
                    Button {
                        submitEmailAction()
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == .signIn ? "Sign In" : "Create Account")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .disabled(auth.isLoading || !canSubmit)

                    // Divider
                    HStack {
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                        Text("or").font(.footnote).foregroundStyle(.secondary).fixedSize()
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                    // Social sign-in
                    VStack(spacing: 12) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                        .accessibilityLabel("Sign in with Apple")

                        GoogleSignInButton()
                            .padding(.horizontal, 24)
                    }

                    // Disclaimer
                    Text("By continuing, you agree to our terms. DoseTrack is a reminder tool, not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingReset) {
            PasswordResetView()
                .environmentObject(auth)
        }
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return !fullName.isEmpty && password == confirmPassword && password.count >= 8
        }
        return true
    }

    private func submitEmailAction() {
        focused = nil
        guard canSubmit else { return }
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                await auth.signUp(email: email, password: password, fullName: fullName)
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                Task { await self.auth.signInWithApple(credential: credential) }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                auth.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Google Sign-In Button (SwiftUI wrapper)

private struct GoogleSignInButton: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Button {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            Task { await auth.signInWithGoogle(presenting: root) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign in with Google")
    }
}

// MARK: - Reusable Text Field

private struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(contentType)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: $text)
                    .textContentType(contentType)
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                    .autocorrectionDisabled(keyboardType == .emailAddress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Password Reset Sheet

private struct PasswordResetView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange.gradient)
                        .padding(.top, 32)

                    Text("Reset Password")
                        .font(.title2.bold())

                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if sent {
                        Label("Reset email sent — check your inbox.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)

                        if let err = auth.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        Button("Send Reset Link") {
                            Task {
                                await auth.resetPassword(email: email)
                                if auth.errorMessage == nil { sent = true }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || auth.isLoading)
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager.shared)
}
