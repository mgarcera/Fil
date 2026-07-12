import SwiftUI
import StoreKit

/// Fil Pro paywall, built on Apple's native `SubscriptionStoreView`: Apple renders the plan picker,
/// localized prices, trial eligibility, buy button, and restore; we supply a bespoke Fil marketing
/// header. Purchases flow through `Transaction.updates`, which `StoreManager` observes to flip
/// `isPro`, so app-wide gating updates automatically. See docs/monetization/blank-canvas-pivot-plan.md.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    private static let privacyURL = URL(string: "https://rootcause.ltd/fil/privacy")!
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        SubscriptionStoreView(productIDs: StoreManager.ProductID.all) {
            marketingHeader
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStorePickerItemBackground(.ultraThinMaterial)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .policies)
        .subscriptionStorePolicyDestination(url: Self.privacyURL, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: Self.termsURL, for: .termsOfService)
        .tint(Color(hex: "#33BF99"))
        .background(Theme.background)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result { dismiss() }
        }
        .overlay(alignment: .topTrailing) {
            Button("close") { dismiss() }
                .font(Theme.dmSans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(20)
        }
    }

    /// Fil's own marketing content above Apple's plan controls. Calm and anti-optimization: it
    /// invites, it never pressures.
    private var marketingHeader: some View {
        VStack(spacing: 20) {
            NoteBlobShape(seed: 0.62)
                .fill(Theme.accentGradient)
                .frame(width: 120, height: 120)
            VStack(spacing: 12) {
                AnimatedGradientRevealText(text: "surface your thoughts")
                    .font(Theme.dmSans(26, weight: .bold))
                Text("fil pro reads across your fils and reflects back what matters, when you ask. your thoughts stay yours.")
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}
