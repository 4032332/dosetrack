// DoseTrack/Views/Settings/CaregiverInviteView.swift
// Patient-side UI for inviting a caregiver to co-manage medications, and for
// viewing/cancelling/removing an existing caregiver relationship.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct CaregiverInviteView: View {
    @EnvironmentObject var caregiverManager: CaregiverManager
    @State private var invite: CaregiverManager.InviteResponse?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let relationship = caregiverManager.ownPatientRelationship {
                Section {
                    if relationship.isActive {
                        Text("Co-managed by your caregiver")
                        Button("Remove Caregiver", role: .destructive) {
                            Task { try? await caregiverManager.revoke(relationshipId: relationship.id) }
                        }
                    } else if relationship.isPending && !relationship.isExpired {
                        Text("Invite pending — share the code below, or cancel it to start over.")
                        Button("Cancel Invite", role: .destructive) {
                            Task { try? await caregiverManager.revoke(relationshipId: relationship.id) }
                        }
                    }
                }
            } else {
                Section {
                    Text("Invite someone to co-manage your medications — they'll be able to view and log doses on your behalf.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let invite {
                        qrCode(for: invite.link)
                        if let url = URL(string: invite.link) {
                            ShareLink(item: url) {
                                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Text("Couldn't create a shareable link. Please try generating a new invite.")
                                .font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            Task { await generateInvite() }
                        } label: {
                            if isLoading { ProgressView() } else { Text("Generate Invite") }
                        }
                        .disabled(isLoading)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Caregiver")
        .task { await caregiverManager.refresh() }
    }

    private func generateInvite() async {
        isLoading = true; defer { isLoading = false }
        do { invite = try await caregiverManager.createInvite() }
        catch { errorMessage = "Couldn't create an invite. Please try again." }
    }

    private func qrCode(for string: String) -> some View {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let context = CIContext()
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Image(decorative: cgImage, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
        )
    }
}
