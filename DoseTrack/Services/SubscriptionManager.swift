// DoseTrack/Services/SubscriptionManager.swift
import StoreKit
import Combine

/// Manages StoreKit 2 subscription state. Publishes `isProSubscriber` to drive
/// UI gating and CoreData container switching.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Published

    /// True if this account has Plus-equivalent access — either a real StoreKit subscription or
    /// an active promo-code grant. Every existing call site in the app treats this as "does the
    /// user get Plus features", not literally "are they a paying subscriber", so folding promo
    /// access in here (rather than threading a second check through every gate) keeps all
    /// existing gating correct for free.
    @Published private(set) var isProSubscriber: Bool = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var promoAccessExpiresAt: Date?

    // MARK: - Private

    private var updatesTask: Task<Void, Never>?
    private var storeKitEntitled = false

    // MARK: - Init

    init() {
        isProSubscriber = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        startListeningForTransactionUpdates()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
        applyDebugOverrideIfNeeded()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Public API

    func checkEntitlement() async -> Bool {
        await refreshEntitlement()
        return isProSubscriber
    }

    func purchase(_ product: Product) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlement()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Promo code

    enum PromoRedeemOutcome {
        case success
        case invalidCode
        case alreadyRedeemed
        case requiresAccount   // guest — no stable identity to enforce "once per account"
        case networkError
    }

    /// Redeems the shared promo code for the given account. Requires a real (non-guest) signed-in
    /// account — see PromoRedeemOutcome.requiresAccount — since "once per account, ever" has
    /// nothing to key off for a guest.
    func redeemPromoCode(_ code: String, userId: UUID?, isGuest: Bool) async -> PromoRedeemOutcome {
        guard let userId, !isGuest else { return .requiresAccount }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed == Constants.PromoCode.sharedCode else { return .invalidCode }
        switch await SupabaseSyncManager.shared.redeemPromoCode(
            userId: userId, code: trimmed, durationDays: Constants.PromoCode.durationDays
        ) {
        case .success(let expiresAt):
            applyPromoExpiry(expiresAt, identity: userId.uuidString)
            return .success
        case .alreadyRedeemed:
            return .alreadyRedeemed
        case .networkError:
            return .networkError
        }
    }

    /// Loads any active promo grant for this identity — local cache first (instant, offline-safe),
    /// then a server check for a real account with no local record (fresh login / reinstall).
    /// Mirrors DisclaimerManager's identity/cache split.
    func loadPromoStatus(userId: UUID?, isGuest: Bool) async {
        guard let userId, !isGuest else { return }
        let identity = userId.uuidString
        if let cached = cachedPromoExpiry(identity: identity) {
            promoAccessExpiresAt = cached
            recomputeEffectiveAccess()
            // Still worth a background refresh in case the cached value is stale (e.g. a promo
            // redeemed on another device), but don't block on it.
        }
        if let serverExpiry = await SupabaseSyncManager.shared.fetchActivePromoExpiry(userId: userId) {
            applyPromoExpiry(serverExpiry, identity: identity)
        }
    }

    /// If a reminder for the current days-remaining count hasn't been shown yet today, returns
    /// that count (1–5) and marks it shown. Returns nil otherwise — either promo access isn't
    /// active, it's outside the reminder window, or today's reminder already fired.
    func promoExpiryReminderDaysRemaining() -> Int? {
        guard let expiresAt = promoAccessExpiresAt, expiresAt > Date() else { return nil }
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day.map { $0 + 1 } ?? 0
        guard Constants.PromoCode.reminderThresholds.contains(daysRemaining) else { return nil }
        let key = Self.reminderShownKey(daysRemaining: daysRemaining)
        let today = Self.dayStamp(for: Date())
        if UserDefaults.standard.string(forKey: key) == today { return nil }
        UserDefaults.standard.set(today, forKey: key)
        return daysRemaining
    }

    private static func reminderShownKey(daysRemaining: Int) -> String { "promoReminderShown.\(daysRemaining)" }
    private static func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func cachedPromoExpiryKey(identity: String) -> String { "promoAccessExpiresAt.\(identity)" }

    private func cachedPromoExpiry(identity: String) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.cachedPromoExpiryKey(identity: identity))
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func applyPromoExpiry(_ date: Date, identity: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.cachedPromoExpiryKey(identity: identity))
        promoAccessExpiresAt = date
        recomputeEffectiveAccess()
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            availableProducts = try await Product.products(for: [
                Constants.StoreKit.proMonthly,
                Constants.StoreKit.proAnnual
            ])
        } catch {
            // Products unavailable in sandbox without network or missing StoreKit config
        }
    }

    @discardableResult
    private func refreshEntitlement() async -> Bool {
        if let override = debugForceProOverride {
            isProSubscriber = override
            return override
        }
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               (transaction.productID == Constants.StoreKit.proMonthly ||
                transaction.productID == Constants.StoreKit.proAnnual),
               transaction.revocationDate == nil {
                hasPro = true
                break
            }
        }
        storeKitEntitled = hasPro
        recomputeEffectiveAccess()
        return isProSubscriber
    }

    /// Combines the real StoreKit entitlement with any still-active promo grant into the single
    /// `isProSubscriber` flag every gate in the app reads, and keeps the legacy UserDefaults key
    /// (read directly by MedicationsViewModel's default closure) in sync with it.
    private func recomputeEffectiveAccess() {
        let promoActive = promoAccessExpiresAt.map { $0 > Date() } ?? false
        isProSubscriber = storeKitEntitled || promoActive
        UserDefaults.standard.set(isProSubscriber, forKey: Constants.UserDefaultsKeys.isProSubscriber)
    }

    private func startListeningForTransactionUpdates() {
        updatesTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Dev/TestFlight Pro override
    //
    // Lets Pro-gated features be tested without a real purchase — either during
    // local development or on a TestFlight build (where sandbox StoreKit purchases
    // are awkward to set up repeatedly). Gated by BuildEnvironment.isTestFlightOrDebug
    // rather than #if DEBUG so it survives into TestFlight archives; it self-disables
    // on a real App Store build (detected via the receipt filename), so it's safe to
    // ship without manual removal. The only way to reach the UI that flips this is the
    // hidden, passcode-gated Developer Options screen in Settings — see SettingsView.
    // There is no equivalent Supabase-side flag: subscription status isn't stored in
    // Supabase at all today, only cached locally from StoreKit's own entitlement check,
    // so this override is the only way to force it.

    private static let debugOverrideKey = "debugForceProOverride"

    /// `nil` = use the real StoreKit entitlement (default). `true`/`false` forces
    /// `isProSubscriber` to that value and skips the real entitlement check
    /// until cleared. No-ops on a real App Store build even if somehow invoked.
    var debugForceProOverride: Bool? {
        get {
            guard BuildEnvironment.isTestFlightOrDebug else { return nil }
            return UserDefaults.standard.object(forKey: Self.debugOverrideKey) as? Bool
        }
        set {
            guard BuildEnvironment.isTestFlightOrDebug else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.debugOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.debugOverrideKey)
            }
            applyDebugOverrideIfNeeded()
            if newValue == nil {
                Task { await refreshEntitlement() }
            }
        }
    }

    private func applyDebugOverrideIfNeeded() {
        guard BuildEnvironment.isTestFlightOrDebug else { return }
        if let override = debugForceProOverride {
            isProSubscriber = override
            // Several other places in the app (e.g. MedicationsViewModel's default
            // isProSubscriber closure) read Constants.UserDefaultsKeys.isProSubscriber
            // directly from UserDefaults instead of observing this class's @Published
            // property — that raw key is normally kept truthful by refreshEntitlement()
            // on every real purchase/restore, but the override path above returns
            // before reaching that write. Without this line, the debug override only
            // ever updates this in-memory property, leaving every UserDefaults-reading
            // consumer still seeing stale (usually `false`) Pro status.
            UserDefaults.standard.set(override, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        }
    }
}
