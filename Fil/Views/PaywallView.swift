import SwiftUI
import StoreKit

/// Fil Extra paywall, built on Apple's native `SubscriptionStoreView`: Apple renders the plan picker,
/// localized prices, trial eligibility, buy button, and restore; we supply a bespoke Fil marketing
/// header. Purchases flow through `Transaction.updates`, which `StoreManager` observes to flip
/// `isPro`, so app-wide gating updates automatically. See docs/monetization/blank-canvas-pivot-plan.md.
struct PaywallView: View {
    /// When embedded in the Settings sheet the sheet has its own dismissal (tabs + drag), so the
    /// native close (X) button is redundant; standalone presentation keeps it.
    var showsDismiss: Bool = true

    @Environment(\.dismiss) private var dismiss

    /// Gradient pairs for the static fil-blobs beside the gooey creating blob (mirrors the website's
    /// "creating blob + a set of fils" composition).
    private static let headerBlobs: [(String, String)] = [
        ("#F24D59", "#E67333"),
        ("#33BF99", "#408CD9"),
        ("#6659CC", "#E8196A"),
        ("#4DB366", "#D9A626"),
    ]

    private static let privacyURL = URL(string: "https://smidgecraft.com/fil/privacy")!
    private static let termsURL = URL(string: "https://smidgecraft.com/fil/terms")!
    /// The web feature page detailing everything smart search can find (free vs Pro).
    private static let smartSearchURL = URL(string: "https://smidgecraft.com/fil/smart-search")!

    var body: some View {
        SubscriptionStoreView(productIDs: StoreManager.ProductID.all) {
            marketingHeader
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStorePickerItemBackground(.ultraThinMaterial)
        // Drop StoreKit's default per-plan marketing icon (the star beside "your plan").
        .subscriptionStoreControlIcon { _, _ in EmptyView() }
        .storeButton(.visible, for: .restorePurchases)
        // Apple renders its policy buttons centered; we hide them and show our own left-aligned
        // Terms + Privacy links in the header instead.
        .storeButton(.hidden, for: .policies)
        .storeButton(showsDismiss ? .visible : .hidden, for: .cancellation)
        .tint(Theme.filProAmber)
        // Standalone gets its own opaque backdrop; embedded stays clear so the Settings sheet's
        // ambient background shows through and it blends in.
        .background(showsDismiss ? Theme.background : Color.clear)
        .onInAppPurchaseCompletion { _, result in
            // Refresh entitlement deterministically here rather than racing the Transaction.updates
            // listener, so isPro is true before the paywall dismisses and the next query routes to
            // the cloud.
            // Refresh entitlement deterministically here rather than racing the
            // Transaction.updates listener, so isPro is true before the paywall dismisses and the
            // next query routes to the cloud.
            if case .success(.success(let verification)) = result {
                if case .verified(let transaction) = verification {
                    // StoreKit requires every transaction to be finished. SubscriptionStoreView
                    // runs the purchase but does not finish it, and an unfinished transaction is
                    // re-delivered indefinitely.
                    await transaction.finish()
                }
                await StoreManager.shared.refresh()
                dismiss()
            }
        }
        // Force the whole paywall (our copy + Apple's plan controls + the standalone Theme.background
        // backdrop) to render light-on-dark regardless of the app's light/dark setting. Scoped to this
        // subtree via the environment (not .preferredColorScheme, which would leak to the Settings sheet).
        .environment(\.colorScheme, .dark)
    }

    /// Fil's own marketing content above Apple's plan controls. Calm and anti-optimization: it
    /// invites, it never pressures.
    private var marketingHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The headline names all four things Extra includes: beautiful covers the app icons
            // and screensavers, smart covers search and filing. Two earlier headlines each sold a
            // subset — "A smarter search" withheld filing, and "Find it, and put it away." named
            // both of those while leaving the icons and screensavers invisible on the one screen
            // where someone decides whether to pay for them. The body below delivers one half each.
            AnimatedGradientRevealText(text: "Beautiful and smart.")
                .font(Theme.fredoka(26, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            blobRow
            // One line per half of the headline, in the same order.
            VStack(alignment: .leading, spacing: 10) {
                Text("App icons in glass, ice and paint, and ambient screensavers made out of your own thoughts.")
                // Filing's own objection answered in the same breath that raises it: nothing moves
                // until you say so.
                Text("Ask in your own words and Fil finds what you meant, or hand it a pile and let it file, every choice yours before anything moves.")
            }
            .font(Theme.fredoka(15, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Keeps the paywall lean; the full free-vs-Extra capability list lives on the web.
            Link(destination: Self.smartSearchURL) {
                HStack(spacing: 4) {
                    Text("See everything Extra can do")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(Theme.fredoka(14, weight: .medium))
            }
            .tint(Theme.filProAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Plain-language data disclosure, shown at the moment of opting in.
            // Must name every Extra path that leaves the device, not just search. Filing sends
            // text too, and a disclosure that says "to answer your search" while a second feature
            // also sends is inaccurate rather than merely incomplete. The provider is deliberately
            // unnamed here — the privacy policy names it, and this line has to stay readable at
            // the moment of opting in.
            Text("To search or file for you, Fil sends the relevant text to our AI provider. It's never used to train models and is deleted within 30 days. Free keyword search stays on your device.")
                .font(Theme.fredoka(15, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link("Terms", destination: Self.termsURL)
                Link("Privacy policy", destination: Self.privacyURL)
            }
            .font(Theme.fredoka(12, weight: .regular))
            .tint(.white.opacity(0.7))
        }
        .padding(.horizontal, 24)
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
    }
}
