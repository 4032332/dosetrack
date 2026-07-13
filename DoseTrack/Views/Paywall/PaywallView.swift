// DoseTrack/Views/Paywall/PaywallView.swift
import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var selectedProductId: String? = nil
    @State private var purchaseError: String? = nil

    private var monthly: Product? {
        subscriptionManager.availableProducts.first { $0.id == Constants.StoreKit.proMonthly }
    }
    private var annual: Product? {
        subscriptionManager.availableProducts.first { $0.id == Constants.StoreKit.proAnnual }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader

                    VStack(spacing: 28) {
                        featureList

                        if subscriptionManager.availableProducts.isEmpty {
                            comingSoonNotice
                        } else {
                            pricingCards
                            legalFooter
                        }

                        if let purchaseError {
                            Text(purchaseError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await subscriptionManager.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)

                        Text("DoseTrack is a reminder tool, not medical advice.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                }
            }
            .onAppear {
                // Default the selection to whichever plan should be pre-highlighted — annual,
                // since it's the better value, matching the "Best Value" badge below.
                if selectedProductId == nil {
                    selectedProductId = annual?.id ?? monthly?.id
                }
            }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#5B8AF0"), Color(hex: "#3B5FCC")],
                startPoint: .top, endPoint: .bottom
            )
            Image(systemName: "pills.fill")
                .font(.system(size: 160))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 110, y: -30)

            VStack(spacing: 10) {
                // SplashHero is now a transparent cut-out (white background knocked out), so it
                // drops straight onto the gradient with no box and no circle clip — clipping to a
                // Circle here would crop the mascot's outstretched arms and the floating pills.
                Image("SplashHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                Text("DoseTrack Plus")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Unlimited medications, PDF reports,\nand caring for a loved one.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 52)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(icon: "infinity", color: .blue,
                       title: "Unlimited medications",
                       subtitle: "No cap at 5 — track everything you take")
            FeatureRow(icon: "doc.richtext.fill", color: .purple,
                       title: "PDF doctor reports",
                       subtitle: "A polished adherence report ready to share")
            FeatureRow(icon: "person.badge.shield.checkmark", color: .teal,
                       title: "Care for someone else",
                       subtitle: "Manage a loved one's medications remotely")
            FeatureRow(icon: "icloud.fill", color: .orange,
                       title: "Cross-device sync",
                       subtitle: "Your data, backed up and synced across your devices")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pricing

    private var pricingCards: some View {
        VStack(spacing: 12) {
            if let annual {
                PricingCard(
                    product: annual,
                    isSelected: selectedProductId == annual.id,
                    badge: annualSavingsBadge,
                    subtitle: "Just \(perMonthPrice(annual))/mo, billed yearly"
                ) {
                    selectedProductId = annual.id
                }
            }
            if let monthly {
                PricingCard(
                    product: monthly,
                    isSelected: selectedProductId == monthly.id,
                    badge: "7-day free trial",
                    subtitle: "Then \(monthly.displayPrice)/mo"
                ) {
                    selectedProductId = monthly.id
                }
            }

            Button {
                purchaseSelected()
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedProductId == nil || subscriptionManager.purchaseInProgress)
            .padding(.top, 4)
        }
    }

    // Auto-renewable-subscription disclosure required by App Store Review Guideline 3.1.2:
    // renewal terms in the binding, plus functional Terms of Use (EULA) and Privacy Policy links.
    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("DoseTrack Plus is an auto-renewable subscription. It renews at the price shown unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings. Payment is charged to your Apple ID at confirmation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: Constants.ExternalLinks.termsOfUse)
                Link("Privacy Policy", destination: Constants.ExternalLinks.privacyPolicy)
            }
            .font(.caption2.weight(.semibold))
        }
    }

    private var comingSoonNotice: some View {
        // These rows used to render as plain, non-interactive Text styled to look exactly like
        // the real tappable price buttons — so when real StoreKit products aren't configured yet
        // (e.g. Pro isn't live in App Store Connect), tapping them did nothing, which looked like
        // a broken paywall rather than an honestly-labelled "not available yet" state.
        VStack(spacing: 8) {
            Label("Plus pricing is coming soon", systemImage: "hourglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private func perMonthPrice(_ product: Product) -> String {
        let monthlyValue = product.price / 12
        return monthlyValue.formatted(product.priceFormatStyle)
    }

    /// The annual saving vs paying monthly for a year, computed from the LIVE prices so it's
    /// accurate in every currency (e.g. ~44% at A$5.99/A$39.99) — not a hard-coded number that's
    /// only right in one region. Falls back to a plain "Best Value" if prices aren't loaded.
    private var annualSavingsBadge: String {
        guard let annual, let monthly else { return "Best Value" }
        let yearlyIfMonthly = NSDecimalNumber(decimal: monthly.price).doubleValue * 12
        let annualValue = NSDecimalNumber(decimal: annual.price).doubleValue
        guard yearlyIfMonthly > 0, annualValue < yearlyIfMonthly else { return "Best Value" }
        let pct = Int((((yearlyIfMonthly - annualValue) / yearlyIfMonthly) * 100).rounded())
        return pct > 0 ? "Best Value — Save \(pct)%" : "Best Value"
    }

    private func purchaseSelected() {
        guard let id = selectedProductId,
              let product = subscriptionManager.availableProducts.first(where: { $0.id == id })
        else { return }
        purchaseError = nil
        Task {
            do {
                try await subscriptionManager.purchase(product)
            } catch {
                purchaseError = "Something went wrong. Please try again."
            }
        }
    }
}

// MARK: - Pricing Card

private struct PricingCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(badge.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.body.weight(.bold))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}
