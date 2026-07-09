// DoseTrack/Views/Auth/AuthView.swift
import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct AuthView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var confirmPassword = ""
    @State private var showingReset = false
    @State private var showConfirmEmailBanner = false
    @FocusState private var focused: Field?

    enum Mode { case signIn, signUp }
    enum Field: Hashable { case name, email, password, confirm }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Hero character — Milli the pill bottle
                VStack(spacing: 6) {
                    // OnboardingWelcome.png has an opaque *white* background baked in. A white
                    // card behind it is invisible (white-on-white has no edge to see), so the
                    // backdrop must be a colour that actually contrasts with the artwork.
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.15)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 172, height: 172)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                        Image("OnboardingWelcome")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 124, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(spacing: 2) {
                        Text("DoseTrack")
                            .font(.title.bold())
                        Text("Never miss a dose.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("with Milli 💊")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 24)

                // MARK: Mode toggle
                Picker("", selection: $mode) {
                    Text("Sign In").tag(Mode.signIn)
                    Text("Create Account").tag(Mode.signUp)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in
                    auth.errorMessage = nil
                    showConfirmEmailBanner = false
                }

                // MARK: Email confirmation banner
                if showConfirmEmailBanner {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(.blue)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Check your inbox")
                                .font(.subheadline.weight(.semibold))
                            Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // MARK: Error
                if let err = auth.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                // MARK: Fields
                VStack(spacing: 10) {
                    if mode == .signUp {
                        AuthTextField("Full name", text: $fullName,
                                      icon: "person.fill", contentType: .name)
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .email }
                    }

                    AuthTextField("Email address", text: $email,
                                  icon: "envelope.fill", contentType: .emailAddress,
                                  keyboard: .emailAddress)
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    AuthTextField(mode == .signUp ? "Password (8+ characters)" : "Password",
                                  text: $password, icon: "lock.fill",
                                  contentType: mode == .signIn ? .password : .newPassword,
                                  secure: true)
                        .focused($focused, equals: .password)
                        .submitLabel(mode == .signUp ? .next : .go)
                        .onSubmit { mode == .signIn ? submitAction() : (focused = .confirm) }

                    if mode == .signUp {
                        AuthTextField("Confirm password", text: $confirmPassword,
                                      icon: "lock.fill", contentType: .newPassword, secure: true)
                            .focused($focused, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit { submitAction() }

                        // Inline hints
                        VStack(alignment: .leading, spacing: 4) {
                            Hint("At least 8 characters", met: password.count >= 8)
                            if !confirmPassword.isEmpty {
                                Hint("Passwords match", met: password == confirmPassword)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: Forgot password
                if mode == .signIn {
                    Button("Forgot password?") { showingReset = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // MARK: Primary button
                Button(action: submitAction) {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .signIn ? "Sign In" : "Create Account")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isLoading || !canSubmit)

                // MARK: Divider
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                    Text("or").font(.footnote).foregroundStyle(.secondary).fixedSize()
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                }

                // MARK: Social
                VStack(spacing: 10) {
                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    GoogleButton()
                }

                // MARK: Skip
                Button {
                    Task { await auth.continueAsGuest() }
                } label: {
                    Text("Continue without an account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .disabled(auth.isLoading)

                // MARK: Disclaimer
                Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.visible)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingReset) {
            PasswordResetView().environmentObject(auth)
        }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return !fullName.isEmpty && password.count >= 8 && password == confirmPassword
        }
        return true
    }

    private func submitAction() {
        focused = nil
        guard canSubmit else { return }
        showConfirmEmailBanner = false
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                let needsConfirm = await auth.signUp(email: email, password: password, fullName: fullName)
                if needsConfirm { showConfirmEmailBanner = true }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let a):
            if let cred = a.credential as? ASAuthorizationAppleIDCredential {
                Task { await auth.signInWithApple(credential: cred) }
            }
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled {
                auth.errorMessage = e.localizedDescription
            }
        }
    }
}

// MARK: - Sub-views

private struct Hint: View {
    let label: String; let met: Bool
    init(_ label: String, met: Bool) { self.label = label; self.met = met }
    var body: some View {
        Label(label, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.caption).foregroundStyle(met ? .green : .secondary)
    }
}

private struct GoogleButton: View {
    @EnvironmentObject private var auth: AuthManager
    var body: some View {
        Button {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            Task { await auth.signInWithGoogle(presenting: root) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 16, weight: .medium))
                Text("Sign in with Google").font(.body.weight(.medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false

    init(_ placeholder: String, text: Binding<String>, icon: String,
         contentType: UITextContentType? = nil,
         keyboard: UIKeyboardType = .default,
         secure: Bool = false) {
        self.placeholder = placeholder; self._text = text; self.icon = icon
        self.contentType = contentType; self.keyboard = keyboard; self.secure = secure
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            if secure {
                SecureField(placeholder, text: $text)
                    .textContentType(contentType).autocorrectionDisabled()
            } else {
                TextField(placeholder, text: $text)
                    .textContentType(contentType).keyboardType(keyboard)
                    .autocapitalization(keyboard == .emailAddress ? .none : .words)
                    .autocorrectionDisabled(keyboard == .emailAddress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PasswordResetView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "key.fill").font(.system(size: 44))
                        .foregroundStyle(.orange.gradient).padding(.top, 24)
                    Text("Reset Password").font(.title2.bold())
                    Text("Enter your email and we'll send a reset link.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)

                    if sent {
                        Label("Reset email sent — check your inbox.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).multilineTextAlignment(.center)
                    } else {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .autocapitalization(.none).padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                .padding(.horizontal, 24).padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }}
        }
    }
}

#Preview {
    AuthView().environmentObject(AuthManager.shared)
}
