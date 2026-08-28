// DoseTrack/Views/Settings/RedeemPromoCodeView.swift
// Lets a signed-in user redeem the shared DoseTrack Plus promo code (e.g. bundled with a
// physical product sold outside the app). "Once per account, ever" is enforced server-side —
// see SupabaseSyncManager.redeemPromoCode and the promo_redemptions migration.
import SwiftUI

struct RedeemPromoCodeView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @State private var redeemed = false

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Have a promo code for a free month of DoseTrack Plus? Enter it below to unlock unlimited medications, PDF reports, caregiving, and cross-device sync for 30 days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Promo code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(isRedeeming || redeemed)

                    if redeemed {
                        Label("DoseTrack Plus unlocked for 30 days", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            redeem()
                        } label: {
                            if isRedeeming { ProgressView() } else { Text("Redeem Code") }
                        }
                        .disabled(trimmedCode.isEmpty || isRedeeming)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Redeem Code")
                }

                Section {
                    Link(destination: Constants.ExternalLinks.store) {
                        SettingsLabel(title: "Get the DoseTrack Organiser", systemImage: "cart.fill", tint: .purple)
                    }
                } footer: {
                    Text("Don't have a code? Every DoseTrack Organiser comes with a free month of Plus.")
                }
            }
            .navigationTitle("Redeem Promo Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(redeemed ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func redeem() {
        let submitted = trimmedCode
        guard !submitted.isEmpty else { return }
        errorMessage = nil
        isRedeeming = true
        Task {
            let outcome = await subscriptionManager.redeemPromoCode(
                submitted, userId: auth.session?.user.id, isGuest: auth.isGuest
            )
            isRedeeming = false
            switch outcome {
            case .success:
                redeemed = true
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            case .invalidCode:
                errorMessage = "That code isn't valid. Double-check it and try again."
            case .alreadyRedeemed:
                errorMessage = "This code has already been redeemed on this account."
            case .requiresAccount:
                errorMessage = "Sign in with an account (not as a guest) to redeem a promo code."
            case .networkError:
                errorMessage = "Couldn't redeem right now — check your connection and try again."
            }
        }
    }
}

#Preview {
    RedeemPromoCodeView()
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthManager.shared)
}
