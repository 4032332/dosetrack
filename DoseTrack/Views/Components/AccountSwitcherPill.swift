// DoseTrack/Views/Components/AccountSwitcherPill.swift
// Compact toolbar-hosted account switcher for caregivers. Previously this lived in a
// full-width safeAreaInset bar pinned above every tab's own navigation bar — with zero
// clearance from each screen's own toolbar items, it visually competed with them (e.g.
// History's Export CSV/PDF menu rendered clipped behind it). As a real ToolbarItem instead,
// it's laid out by the same navigation bar system as every other toolbar button, so it can
// never overlap or hide them.
import SwiftUI

struct AccountSwitcherPill: View {
    @EnvironmentObject private var activeAccount: ActiveAccountContext
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(activeAccount.activeDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
        }
    }
}
