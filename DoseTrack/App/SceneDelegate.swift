// DoseTrack/App/SceneDelegate.swift
import UIKit
import SwiftUI
import GoogleSignIn

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let persistence = PersistenceController.shared
        let rootView = RootView()
            .environment(\.managedObjectContext, persistence.viewContext)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(WatchConnectivityManager.shared)
            .environmentObject(AuthManager.shared)

        let hosting = UIHostingController(rootView: rootView)
        hosting.sizingOptions = []

        // On iOS 26, UIHostingController as the root view controller has its view
        // sized to the safe area. Embedding it as a child of a plain UIViewController
        // and pinning edge-to-edge forces it to fill the full window bounds.
        let container = UIViewController()
        container.view.backgroundColor = .systemBackground
        container.addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        hosting.didMove(toParent: container)

        let win = UIWindow(frame: windowScene.screen.bounds)
        win.windowScene = windowScene
        win.rootViewController = container
        win.makeKeyAndVisible()
        window = win

        // iOS 26 windowed iPhone mode: lock window to full screen size
        let screenSize = windowScene.screen.bounds.size
        if let restrictions = windowScene.sizeRestrictions {
            restrictions.minimumSize = screenSize
            restrictions.maximumSize = screenSize
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let screenSize = windowScene.screen.bounds.size
        if let restrictions = windowScene.sizeRestrictions {
            restrictions.minimumSize = screenSize
            restrictions.maximumSize = screenSize
        }
    }

    // MARK: - Deep link handling (Supabase email confirm, password reset, OAuth callbacks)

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleIncomingURL(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        handleIncomingURL(url)
    }

    private func handleIncomingURL(_ url: URL) {
        // Google Sign-In callback
        if GIDSignIn.sharedInstance.handle(url) { return }

        // Supabase auth deep link (email confirm, password reset, magic link)
        // Supabase redirects to: io.supabase.dosetrack://login-callback#access_token=...
        // or the custom URL scheme set in the Supabase dashboard
        Task {
            do {
                try await AuthManager.shared.client.auth.session(from: url)
                await AuthManager.shared.refreshSession()
            } catch {
                // Not a Supabase URL — ignore
            }
        }
    }
}
