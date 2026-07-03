// DoseTrack/Views/Components/AccountSwitcherView.swift
// Lets a caregiver switch between their own account and any patient accounts
// they oversee. Presented as a sheet from MainTabView.
import SwiftUI

struct AccountSwitcherView: View {
    @EnvironmentObject var activeAccount: ActiveAccountContext
    @EnvironmentObject var caregiverManager: CaregiverManager
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode: String = ""
    @State private var isAccepting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        activeAccount.switchToOwnAccount()
                        dismiss()
                    } label: {
                        HStack {
                            Text(activeAccount.ownDisplayName)
                            Spacer()
                            if !activeAccount.isViewingOtherAccount {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }

                    ForEach(caregiverManager.overseenPatients) { relationship in
                        Button {
                            activeAccount.switchTo(userId: relationship.patientUserId, displayName: relationship.patientDisplayName)
                            dismiss()
                        } label: {
                            HStack {
                                Text(relationship.patientDisplayName)
                                Spacer()
                                if activeAccount.activeUserId == relationship.patientUserId {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Switch Account")
                }

                // Manual fallback for accepting a caregiver invite without tapping a link.
                Section {
                    TextField("Enter invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button {
                        acceptInvite()
                    } label: {
                        if isAccepting {
                            ProgressView()
                        } else {
                            Text("Accept Invite")
                        }
                    }
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAccepting)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Have an Invite Code?")
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func acceptInvite() {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        errorMessage = nil
        isAccepting = true
        Task {
            do {
                _ = try await caregiverManager.acceptInvite(code: code)
                await MainActor.run {
                    isAccepting = false
                    inviteCode = ""
                }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    errorMessage = "Couldn't accept invite. Check the code and try again."
                }
            }
        }
    }
}
