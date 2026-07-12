import SwiftUI
import StoreKit

/// Fil Pro paywall. Three visual directions are included behind a temporary switcher so the
/// direction can be chosen by eye; once picked, drop the `Variant` picker and the unused bodies.
///
/// Voice: calm and anti-optimization. It invites, it never pressures ("unlock now", countdowns,
/// "limited time"). Capability framing mirrors docs/monetization/blank-canvas-pivot-plan.md.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    // TEMP (verdict): switch directions live on device. Remove after a direction is chosen.
    @State private var variant: Variant = .blob
    @State private var purchasing = false
    @State private var purchaseError: String?

    private var store: StoreManager { StoreManager.shared }

    enum Variant: String, CaseIterable, Identifiable {
        case blob = "Blob", split = "Split", quiet = "Quiet"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // TEMP verdict switcher.
            Picker("direction", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Group {
                switch variant {
                case .blob:  blobVariant
                case .split: splitVariant
                case .quiet: quietVariant
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            Button("close") { dismiss() }
                .font(Theme.dmSans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(20)
        }
        .task { if !store.isReady { await store.refresh() } }
        .onChange(of: store.isPro) { _, isPro in if isPro { dismiss() } }
    }

    // MARK: - Variant A — "blob" (visual / of-the-app)

    private var blobVariant: some View {
        VStack(spacing: 28) {
            Spacer()
            NoteBlobShape(seed: 0.62)
                .fill(Theme.accentGradient)
                .frame(width: 132, height: 132)
            VStack(spacing: 12) {
                AnimatedGradientRevealText(text: "surface your thoughts")
                    .font(Theme.dmSans(26, weight: .bold))
                Text("fil pro reads across your fils and reflects back what matters, when you ask. your thoughts stay yours.")
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer()
            planStack
            footer
        }
        .padding(.bottom, 28)
    }

    // MARK: - Variant B — "split" (honest capability framing)

    private var splitVariant: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("free, and pro")
                .font(Theme.dmSans(26, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            VStack(alignment: .leading, spacing: 18) {
                capabilityRow(mark: "•", title: "free, always",
                              line: "find any fil by the words you remember.")
                capabilityRow(mark: "✦", title: "with fil pro",
                              line: "ask in your own words. fil surfaces the fils that fit and reflects them back to you.")
            }
            Spacer()
            planStack
            footer
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    // MARK: - Variant C — "quiet" (spare / anti-optimization)

    private var quietVariant: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("when you want to find a thought you can't quite name, fil pro surfaces it.")
                .font(Theme.dmSans(22, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            planStack
            footer
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    // MARK: - Shared pieces

    private func capabilityRow(mark: String, title: String, line: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(mark)
                .font(Theme.dmSans(16, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.dmSans(15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(line)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planStack: some View {
        VStack(spacing: 12) {
            planButton(id: StoreManager.ProductID.annual, cadence: "/ year", footnote: "best value")
            planButton(id: StoreManager.ProductID.monthly, cadence: "/ month", footnote: nil)
            if let purchaseError {
                Text(purchaseError)
                    .font(Theme.dmSans(13))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Text("14 days free, then it renews. cancel anytime.")
                .font(Theme.dmSans(12))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 24)
    }

    private func planButton(id: String, cadence: String, footnote: String?) -> some View {
        Button { buy(id) } label: {
            HStack(spacing: 8) {
                Text(price(for: id))
                    .font(Theme.dmSans(17, weight: .semibold))
                Text(cadence)
                    .font(Theme.dmSans(14))
                    .foregroundStyle(Theme.secondaryText)
                if let footnote {
                    Spacer()
                    Text(footnote)
                        .font(Theme.dmSans(12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .foregroundStyle(Theme.primaryText)
            .glassEffect(.regular, in: .capsule)
        }
        .disabled(purchasing)
    }

    private var footer: some View {
        Button("restore purchase") { Task { try? await store.restore() } }
            .font(Theme.dmSans(13))
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 8)
    }

    // MARK: - Logic

    /// Real store price when loaded, else the configured fallback so the paywall still reads.
    private func price(for id: String) -> String {
        if let product = store.product(for: id) { return product.displayPrice }
        return id == StoreManager.ProductID.annual ? "$24.99" : "$2.99"
    }

    private func buy(_ id: String) {
        guard let product = store.product(for: id) else {
            purchaseError = "this plan isn't available yet."
            return
        }
        purchasing = true
        purchaseError = nil
        Task {
            do {
                _ = try await store.purchase(product)   // success dismisses via onChange(isPro)
            } catch {
                purchaseError = error.localizedDescription
            }
            purchasing = false
        }
    }
}
