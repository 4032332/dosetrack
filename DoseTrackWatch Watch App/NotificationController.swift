// DoseTrackWatch Watch App/NotificationController.swift
import SwiftUI
import UserNotifications
import WatchKit

/// Handles medication notification display on Apple Watch.
/// The system presents this view when a MEDICATION_DUE notification arrives on the watch.
struct NotificationView: View {
    let notification: UNNotification

    private var medicationName: String {
        notification.request.content.title
    }
    private var body_: String {
        notification.request.content.body
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pills.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)

            Text(medicationName)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(body_)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// WatchKit notification hosting controller — shows the custom notification UI.
class NotificationController: WKUserNotificationHostingController<NotificationView> {

    var notification: UNNotification?

    override var body: NotificationView {
        NotificationView(notification: notification ?? makeEmptyNotification())
    }

    override func didReceive(_ notification: UNNotification) {
        self.notification = notification
    }

    private func makeEmptyNotification() -> UNNotification {
        // Safe fallback — should never be called in practice
        fatalError("Notification was nil in NotificationController")
    }
}
