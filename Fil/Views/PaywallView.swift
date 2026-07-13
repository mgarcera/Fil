import SwiftUI
import StoreKit

/// Fil Pro paywall, built on Apple's native `SubscriptionStoreView`: Apple renders the plan picker,
/// localized prices, trial eligibility, buy button, and restore; we supply a bespoke Fil marketing
/// header. Purchases flow through `Transaction.updates`, which `StoreManager` observes to flip
/// `isPro`, so app-wide gating updates automatically. See docs/monetization/blank-canvas-pivot-plan.md.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    // TEMP (verdict): compare the calm blob header vs the orbiting-blobs header. Remove once chosen.
    @State private var headerStyle: HeaderStyle = .blob
    private enum HeaderStyle { case blob, orbit }

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
            // TEMP (verdict) switcher.
            Picker("header", selection: $headerStyle) {
                Text("Blob").tag(HeaderStyle.blob)
                Text("Orbit").tag(HeaderStyle.orbit)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)

            switch headerStyle {
            case .blob:
                NoteBlobShape(seed: 0.62)
                    .fill(Theme.accentGradient)
                    .frame(width: 120, height: 120)
            case .orbit:
                OrbitingBlobsHeader()
                    .frame(height: 200)
            }

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
}

/// A slow constellation of gradient fil-blobs orbiting on a tilted ellipse — an on-brand, calmer
/// reinterpretation of the "paywall 3D effect" for the header. Blobs scale in one by one, then the
/// ring drifts continuously.
private struct OrbitingBlobsHeader: View {
    /// Distinct gradient pairs (start, end) drawn from Theme's palettes, one per orbiting blob.
    private static let pairs: [(String, String)] = [
        ("#F24D59", "#E67333"),
        ("#33BF99", "#408CD9"),
        ("#6659CC", "#E8196A"),
        ("#4DB366", "#D9A626"),
        ("#8A4FD9", "#33B5D9"),
    ]

    @State private var trim: CGFloat = 0        // drives the one-by-one scale-in
    @State private var rotation: CGFloat = 0    // drives the continuous orbit

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = diameter / 2 - 24
            let tilt = cos(62 * CGFloat.pi / 180) // vertical foreshortening → a tilted (3D) ellipse
            let count = Self.pairs.count

            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let angle = (CGFloat(index) / CGFloat(count)) * 360 + rotation
                    let radians = angle * CGFloat.pi / 180
                    let x = cos(radians) * radius
                    let y = sin(radians) * radius * tilt

                    // Each blob scales in over its slice of the trim sweep.
                    let start = CGFloat(index) / CGFloat(count)
                    let end = CGFloat(index + 1) / CGFloat(count)
                    let appear = max(min((trim - start) / (end - start), 1), 0)

                    NoteBlobShape(seed: Double(index) / Double(count))
                        .fill(Theme.gradient(startHex: Self.pairs[index].0, endHex: Self.pairs[index].1, seed: Double(index)))
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 2, y: 4)
                        .scaleEffect(appear)
                        .offset(x: x, y: y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(-16))       // tilt the ellipse's major axis
        }
        .task {
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation(.easeOut(duration: 1.2)) { trim = 1 }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.linear(duration: 44).repeatForever(autoreverses: false)) { rotation = 360 }
        }
    }
}
