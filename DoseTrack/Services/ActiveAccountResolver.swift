// DoseTrack/Services/ActiveAccountResolver.swift
import Foundation

/// Non-SwiftUI-scoped holder for "whose account is the UI currently acting on".
/// `nil` means the signed-in user's own account. `ActiveAccountContext` (a SwiftUI
/// EnvironmentObject) drives the UI; this mirror lets service/UIKit code — AppDelegate's
/// notification-action handler, DoseLoggingService — resolve the same value without an
/// environment. RootView keeps the two in sync on every account switch.
@MainActor
final class ActiveAccountResolver: ObservableObject {
    static let shared = ActiveAccountResolver()

    /// `nil` = own account; otherwise the overseen patient's userId.
    private(set) var activeUserId: UUID?

    func set(activeUserId: UUID?) {
        self.activeUserId = activeUserId
    }
}
