// DoseTrack/Services/SubscriptionManager.swift
import StoreKit
import Combine

/// Manages StoreKit 2 subscription state. Publishes `isProSubscriber` to drive
/// UI gating and CoreData container switching.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Published

    @Published private(set) var isProSubscriber: Bool = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false

    // MARK: - Private

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        isProSubscriber = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        startListeningForTransactionUpdates()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
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
        isProSubscriber = hasPro
        UserDefaults.standard.set(hasPro, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        return hasPro
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
}
