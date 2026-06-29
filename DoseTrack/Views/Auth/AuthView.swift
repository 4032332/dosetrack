// DoseTrack/Views/Auth/AuthView.swift
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
    @State private var showConfirmEmailBanner = false
    @FocusState private var keyboardActive: Bool

    enum Mode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Logo — shrinks when keyboard is up so fields stay visible
                    VStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: keyboardActive ? 36 : 56))
                            .foregroundStyle(.blue.gradient)
                        Text("DoseTrack")
                            .font(keyboardActive ? .title2.bold() : .largeTitle.bold())
                        if !keyboardActive {
                            Text("Never miss a dose.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, keyboardActive ? 16 : 36)
                    .padding(.bottom, keyboardActive ? 16 : 28)
                    .animation(.spring(response: 0.3), value: keyboardActive)

                    // Mode toggle
                    Picker("", selection: $mode) {
                        Text("Sign In").tag(Mode.signIn)
                        Text("Create Account").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .onChange(of: mode) { _, _ in
                        auth.errorMessage = nil
                        showConfirmEmailBanner = false
                    }

                    // Confirm-email banner
                    if showConfirmEmailBanner {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check your inbox")
                                    .font(.subheadline.weight(.semibold))
                                Text("We sent a confirmation link to \(email). Click it to activate your account, then sign in.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }

                    // Form fields
                    VStack(spacing: 12) {
                        if mode == .signUp {
                            AuthTextField(
                                placeholder: "Full name",
                                text: $fullName,
                                icon: "person.fill",
                                contentType: .name
                            )
                            .focused($keyboardActive)
                            .submitLabel(.next)
                        }

                        AuthTextField(
                            placeholder: "Email address",
                            text: $email,
                            icon: "envelope.fill",
                            contentType: .emailAddress,
                            keyboardType: .emailAddress
                        )
                        .focused($keyboardActive)
                        .submitLabel(.next)

                        AuthTextField(
                            placeholder: mode == .signUp ? "Password (8+ characters)" : "Password",
                            text: $password,
                            icon: "lock.fill",
                            contentType: mode == .signIn ? .password : .newPassword,
                            isSecure: true
                        )
                        .focused($keyboardActive)
                        .submitLabel(mode == .signUp ? .next : .go)
                        .onSubmit { if mode == .signIn { submitEmailAction() } }

                        if mode == .signUp {
                            AuthTextField(
                                placeholder: "Confirm password",
                                text: $confirmPassword,
                                icon: "lock.fill",
                                contentType: .newPassword,
                                isSecure: true
                            )
                            .focused($keyboardActive)
                            .submitLabel(.go)
                            .onSubmit { submitEmailAction() }

                            // Inline password validation hints
                            VStack(alignment: .leading, spacing: 4) {
                                ValidationHint(
                                    text: "At least 8 characters",
                                    met: password.count >= 8
                                )
                                if !confirmPassword.isEmpty {
                                    ValidationHint(
                                        text: "Passwords match",
                                        met: password == confirmPassword
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Error message
                    if let err = auth.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity)
                    }

                    // Forgot password
                    if mode == .signIn {
                        Button("Forgot password?") { showingReset = true }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
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
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .disabled(auth.isLoading || !canSubmit)

                    // Social divider
                    HStack {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                        Text("or").font(.footnote).foregroundStyle(.secondary).fixedSize()
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                    // Social buttons
                    VStack(spacing: 10) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 24)

                        GoogleSignInButtonView()
                            .padding(.horizontal, 24)
                    }

                    // Skip / guest access
                    Button {
                        Task { await auth.continueAsGuest() }
                    } label: {
                        Text("Continue without an account")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .padding(.top, 20)
                    .disabled(auth.isLoading)

                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingReset) {
            PasswordResetView().environmentObject(auth)
        }
    }

    // MARK: - Helpers

    @Environment(\.colorScheme) private var colorScheme

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 1 else { return false }
        if mode == .signUp {
            return !fullName.isEmpty && password.count >= 8 && password == confirmPassword
        }
        return true
    }

    private func submitEmailAction() {
        keyboardActive = false
        guard canSubmit else { return }
        showConfirmEmailBanner = false
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                let needsConfirmation = await auth.signUp(
                    email: email, password: password, fullName: fullName
                )
                if needsConfirmation {
                    showConfirmEmailBanner = true
                }
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let a):
            if let credential = a.credential as? ASAuthorizationAppleIDCredential {
                Task { await auth.signInWithApple(credential: credential) }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                auth.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Validation hint row

private struct ValidationHint: View {
    let text: String
    let met: Bool
    var body: some View {
        Label(text, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(met ? .green : .secondary)
    }
}

// MARK: - Google button

private struct GoogleSignInButtonView: View {
    @EnvironmentObject private var auth: AuthManager
    var body: some View {
        Button {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            Task { await auth.signInWithGoogle(presenting: root) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text field

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
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Password reset sheet

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
                    Text("Reset Password").font(.title2.bold())
                    Text("Enter your email and we'll send a reset link.")
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)

                    if sent {
                        Label("Reset email sent — check your inbox.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).multilineTextAlignment(.center).padding(.horizontal)
                    } else {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .autocapitalization(.none).padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal)

                        if let err = auth.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        Button("Send Reset Link") {
                            Task {
                                await auth.resetPassword(email: email)
                                if auth.errorMessage == nil { sent = true }
                            }
                        }
                        .buttonStyle(.borderedProminent).disabled(email.isEmpty || auth.isLoading)
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

#Preview {
    AuthView().environmentObject(AuthManager.shared)
}
