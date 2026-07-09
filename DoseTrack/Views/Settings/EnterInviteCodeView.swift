// DoseTrack/Views/Settings/EnterInviteCodeView.swift
// Always-reachable way to accept a caregiver invite by typing the code, independent of
// whether you already oversee a patient. This is the primary entry point into becoming a
// caregiver: the invite *link* (https://dosetrack.app/invite/<code>) is a universal link
// that only opens the app if Associated Domains + an AASA file are configured for that
// domain — until then, the code path here is how a caregiver accepts their first invite.
// (The manual field inside AccountSwitcherView is unreachable for a first-time caregiver,
// because the account-switcher pill only appears once you already oversee someone.)
import SwiftUI

struct EnterInviteCodeView: View {
    @EnvironmentObject var caregiverManager: CaregiverManager
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""
    @State private var isAccepting = false
    @State private var errorMessage: String?
    @State private var accepted = false

    private var trimmedCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("If someone shared a DoseTrack invite code with you, enter it here to start co-managing their medications. You'll be able to view and log doses on their behalf.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(isAccepting || accepted)

                    if accepted {
                        Label("Invite accepted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            acceptInvite()
                        } label: {
                            if isAccepting { ProgressView() } else { Text("Accept Invite") }
                        }
                        .disabled(trimmedCode.isEmpty || isAccepting)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Have an Invite Code?")
                }
            }
            .navigationTitle("Care for Someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(accepted ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func acceptInvite() {
        let code = trimmedCode
        guard !code.isEmpty else { return }
        errorMessage = nil
        isAccepting = true
        Task {
            do {
                _ = try await caregiverManager.acceptInvite(code: code)
                // acceptInvite() already refreshed CaregiverManager, so the new patient now
                // appears in overseenPatients (which makes the account-switcher pill appear).
                isAccepting = false
                accepted = true
                // Give the user a moment to see the confirmation, then close.
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                isAccepting = false
                errorMessage = "Couldn't accept that code. Check it and try again — invites expire, and can only be used once."
            }
        }
    }
}

#Preview {
    EnterInviteCodeView()
        .environmentObject(CaregiverManager.shared)
}
