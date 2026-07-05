// DoseTrack/App/SceneDelegate.swift
import UIKit
import SwiftUI
import GoogleSignIn

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appearanceObserver: NSObjectProtocol?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let persistence = PersistenceController.shared
        let rootView = RootView()
            .environment(\.managedObjectContext, persistence.viewContext)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(WatchConnectivityManager.shared)
            .environmentObject(AuthManager.shared)
            .environmentObject(CaregiverManager.shared)

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

        // Appearance override (Settings > Preferences > Appearance) is applied here at the
        // UIKit level, not via SwiftUI's `.preferredColorScheme`. A `.preferredColorScheme` +
        // `.id(appearanceOverride)` on RootView was tried first, but forcing SwiftUI to rebuild
        // the whole subtree on every change reset the entire view hierarchy's navigation state —
        // toggling the setting from inside Settings > Preferences popped the user straight back
        // to the root. `overrideUserInterfaceStyle` recolors in place without touching SwiftUI's
        // view identity, so navigation stacks stay exactly where they were.
        applyAppearanceOverride()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearanceOverride()
        }
    }

    private func applyAppearanceOverride() {
        let value = UserDefaults.standard.string(forKey: "appearanceOverride") ?? "system"
        let style: UIUserInterfaceStyle
        switch value {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        if window?.overrideUserInterfaceStyle != style {
            window?.overrideUserInterfaceStyle = style
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
        // Caregiver invite universal link: https://dosetrack.app/invite/<code>
        if let host = url.host, host == "dosetrack.app",
           url.pathComponents.count >= 3, url.pathComponents[1] == "invite" {
            let code = url.pathComponents[2]
            NotificationCenter.default.post(name: .caregiverInviteReceived, object: code)
            return
        }

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
