// DoseTrack/Views/Settings/AcceptCaregiverInviteView.swift
// Presented as a sheet when the app is opened via a caregiver invite universal link
// (https://dosetrack.app/invite/<code>), routed through SceneDelegate -> RootView.
import SwiftUI

struct AcceptCaregiverInviteView: View {
    let code: String
    @EnvironmentObject var caregiverManager: CaregiverManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Caregiver Invitation")
                .font(.title2.bold())
            Text("Accepting this invite gives you full access to view and manage this person's medications, schedules, and dose history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if accepted {
                Label("Invite accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    Task { await accept() }
                } label: {
                    if isLoading { ProgressView() } else { Text("Accept") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                Button("Decline") { dismiss() }
            }
        }
        .padding()
    }

    private func accept() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await caregiverManager.acceptInvite(code: code)
            accepted = true
        } catch {
            errorMessage = "This invite is no longer valid."
        }
    }
}
