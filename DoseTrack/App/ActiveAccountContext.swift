// DoseTrack/App/ActiveAccountContext.swift
import Foundation

/// Tracks which account's data the app should currently display/act on.
/// Defaults to the signed-in user's own account; a caregiver can switch it
/// to a linked patient via the account switcher.
@MainActor
final class ActiveAccountContext: ObservableObject {
    @Published private(set) var activeUserId: UUID
    @Published private(set) var activeDisplayName: String

    let ownUserId: UUID
    let ownDisplayName: String

    var isViewingOtherAccount: Bool { activeUserId != ownUserId }

    init(ownUserId: UUID, ownDisplayName: String) {
        self.ownUserId = ownUserId
        self.ownDisplayName = ownDisplayName
        self.activeUserId = ownUserId
        self.activeDisplayName = ownDisplayName
    }

    func switchTo(userId: UUID, displayName: String) {
        activeUserId = userId
        activeDisplayName = displayName
    }

    func switchToOwnAccount() {
        activeUserId = ownUserId
        activeDisplayName = ownDisplayName
    }
}
