import Foundation
import StoreKit
import OSLog

/// StoreKit 2 subscription manager for Fil Pro. Loads the products, tracks whether the user has an
/// active subscription (`isPro`, which includes an active free trial), runs purchases + restore, and
/// listens for transaction updates.
///
/// Product IDs are defined in App Store Connect and mirrored in the local `Products.storekit` config
/// so the flow can be tested without ASC. See docs/monetization/blank-canvas-pivot-plan.md.
@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    /// IDs say `extra`, matching the tier's name, and sit under the `com.smidgecraft` namespace,
    /// matching the bundle ID. Both changes landed 2026-08-17 while ASC's products still did not
    /// exist, which was the last free moment: a product ID is immutable once App Store Connect has
    /// it. **ASC must be created with these exact IDs**, and `Products.storekit` plus the proxy's
    /// `PRODUCT_IDS` must stay in step — the proxy denies entitlement to any product not in its
    /// list, which is invisible in the simulator because nothing there calls the proxy.
    enum ProductID {
        static let monthly = "com.smidgecraft.Fil.extra.monthly"
        static let annual = "com.smidgecraft.Fil.extra.annual"
        static let all: [String] = [monthly, annual]
    }

    /// Loaded subscription products, monthly first then annual.
    private(set) var products: [Product] = []
    /// True while the user has an active Fil Pro entitlement (includes an active free trial).
    private(set) var isPro = false
    /// The active subscription's transaction id, sent to the proxy to prove entitlement.
    private(set) var proTransactionID: String?
    /// True once the initial product load + entitlement check have completed.
    private(set) var isReady = false

    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.smidgecraft.Fil", category: "store")

    private init() {}

    /// Begin listening for transaction updates and refresh state. Call once at app launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.noteUpdateDelivered()
                await self?.handle(update)
            }
        }
        Task { await refresh() }
    }

    /// TEMPORARY — see updatesDelivered.
    func noteUpdateDelivered() {
        updatesDelivered += 1
    }

    /// Reload products and recompute entitlement.
    func refresh() async {
        await loadProducts()
        await updateEntitlement()
        isReady = true
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = loaded.sorted {
                (ProductID.all.firstIndex(of: $0.id) ?? 0) < (ProductID.all.firstIndex(of: $1.id) ?? 0)
            }
        } catch {
            log.error("product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Recompute `isPro` from the current entitlements.
    func updateEntitlement() async {
        var active = false
        var txID: String?
        var seen: [String] = []
        var unverified = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                unverified += 1
                continue
            }
            seen.append(transaction.productID)
            if ProductID.all.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
                txID = String(transaction.id)
            }
        }
        isPro = active
        proTransactionID = txID

        // TEMPORARY DIAGNOSTIC — remove once the Extra gate is confirmed working.
        // "Purchased and nothing unlocked" has three different causes that look identical from the
        // outside: no entitlement arrives at all, one arrives under a product ID we do not
        // recognise, or the entitlement is fine and the UI is not re-reading it. This records
        // which, so the answer is legible in Settings instead of inferred.
        diagnostic = Diagnostic(
            entitlementsSeen: seen,
            unverifiedCount: unverified,
            expectedIDs: ProductID.all,
            productsLoaded: products.map(\.id),
            isPro: active,
            checkedAt: Date()
        )
        log.notice("""
            entitlement check: seen=\(seen, privacy: .public) \
            unverified=\(unverified) expected=\(ProductID.all, privacy: .public) \
            loaded=\(self.products.map(\.id), privacy: .public) isPro=\(active)
            """)
    }

    /// TEMPORARY — see updateEntitlement().
    struct Diagnostic {
        let entitlementsSeen: [String]
        let unverifiedCount: Int
        let expectedIDs: [String]
        let productsLoaded: [String]
        let isPro: Bool
        let checkedAt: Date
    }

    /// TEMPORARY — surfaced in Settings so the failure is readable without a debugger.
    private(set) var diagnostic: Diagnostic?

    /// TEMPORARY — what the purchase flow last reported, and whether Transaction.updates has ever
    /// delivered anything. An empty currentEntitlements means no transaction exists; these two say
    /// whether one was ever created.
    private(set) var lastPurchaseOutcome: String = "no purchase attempted this launch"
    private(set) var updatesDelivered: Int = 0

    /// TEMPORARY — called from the paywall so the purchase result is recorded even though
    /// SubscriptionStoreView runs the purchase itself.
    func notePurchaseOutcome(_ text: String) {
        lastPurchaseOutcome = text
        log.notice("purchase outcome: \(text, privacy: .public)")
    }

    enum PurchaseOutcome { case success, pending, cancelled }

    @discardableResult
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        switch try await product.purchase() {
        case .success(let verification):
            await handle(verification)
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore purchases via an App Store sync, then recompute entitlement.
    func restore() async throws {
        try await AppStore.sync()
        await updateEntitlement()
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            log.notice("unverified transaction ignored")
            return
        }
        await transaction.finish()
        await updateEntitlement()
    }
}
