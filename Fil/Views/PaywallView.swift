import SwiftUI
import StoreKit

/// Fil Pro paywall, built on Apple's native `SubscriptionStoreView`: Apple renders the plan picker,
/// localized prices, trial eligibility, buy button, and restore; we supply a bespoke Fil marketing
/// header. Purchases flow through `Transaction.updates`, which `StoreManager` observes to flip
/// `isPro`, so app-wide gating updates automatically. See docs/monetization/blank-canvas-pivot-plan.md.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    /// Gradient pairs for the static fil-blobs beside the gooey creating blob (mirrors the website's
    /// "creating blob + a set of fils" composition).
    private static let headerBlobs: [(String, String)] = [
        ("#F24D59", "#E67333"),
        ("#33BF99", "#408CD9"),
        ("#6659CC", "#E8196A"),
        ("#4DB366", "#D9A626"),
    ]

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
        .tint(Theme.filProIndigo)
        .background(Theme.background)
        .onInAppPurchaseCompletion { _, result in
            // Refresh entitlement deterministically here rather than racing the Transaction.updates
            // listener, so isPro is true before the paywall dismisses and the next query routes to
            // the cloud.
            if case .success(.success) = result {
                await StoreManager.shared.refresh()
                dismiss()
            }
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
            blobRow
            VStack(spacing: 12) {
                AnimatedGradientRevealText(text: "a smarter search")
                    .font(Theme.dmSans(26, weight: .bold))
                Text("don't just get words back, get what you were thinking.")
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Plain-language data disclosure, shown at the moment of opting in. Pairs with the
                // privacy-policy link SubscriptionStoreView renders below.
                Text("surfacing sends the relevant fil text to our ai provider (anthropic) to answer. it's never used to train models, and is deleted within 30 days. free keyword search stays on your device.")
                    .font(Theme.dmSans(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    /// The gooey "creating" blob (Fil's real one) on the left, then a row of static gradient fils —
    /// mirrors the website's "mid-capture" composition and reuses the app's own blob pieces.
    private var blobRow: some View {
        HStack(spacing: 10) {
            CreatingFilBlobView()
                .frame(width: 60, height: 60)
            ForEach(Array(Self.headerBlobs.enumerated()), id: \.offset) { index, pair in
                NoteBlobShape(seed: Double(index) * 0.37 + 0.1)
                    .fill(Theme.gradient(startHex: pair.0, endHex: pair.1, seed: Double(index)))
                    .frame(width: 48, height: 48)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
