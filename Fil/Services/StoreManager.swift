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

    enum ProductID {
        static let monthly = "com.masongarcera.Fil.pro.monthly"
        static let annual = "com.masongarcera.Fil.pro.annual"
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
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "store")

    private init() {}

    /// Begin listening for transaction updates and refresh state. Call once at app launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refresh() }
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
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProductID.all.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
                txID = String(transaction.id)
            }
        }
        isPro = active
        proTransactionID = txID
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
