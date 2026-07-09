// DoseTrack/Views/Paywall/PaywallView.swift
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)
                        .padding(.top, 32)

                    Text("DoseTrack Pro")
                        .font(.largeTitle.weight(.bold))

                    Text("Unlimited medications, PDF reports, and caregiver sharing.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                            Button {
                                Task { try? await subscriptionManager.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName)
                                            .fontWeight(.semibold)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .fontWeight(.bold)
                                }
                                .padding()
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        if subscriptionManager.availableProducts.isEmpty {
                            // These rows used to render as plain, non-interactive Text
                            // styled to look exactly like the real tappable price buttons
                            // above — so when real StoreKit products aren't configured yet
                            // (e.g. Pro isn't live in App Store Connect), tapping them did
                            // nothing, which looked like a broken paywall rather than an
                            // honestly-labelled "not available yet" state.
                            VStack(spacing: 8) {
                                Label("Pro pricing is coming soon", systemImage: "hourglass")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal)

                    Button("Restore Purchases") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text("DoseTrack is a reminder tool, not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}
