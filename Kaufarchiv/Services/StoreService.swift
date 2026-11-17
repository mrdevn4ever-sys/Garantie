import Foundation
import StoreKit
import Observation
import os

/// StoreKit 2: prices are always loaded from the App Store, never hard-coded.
@Observable
@MainActor
final class StoreService {
    static let shared = StoreService()

    enum ProductID {
        static let yearly = "ch.kaufarchiv.pro.yearly"
        static let lifetime = "ch.kaufarchiv.pro.lifetime"
        static let all = [yearly, lifetime]
    }

    enum PurchaseOutcome {
        case success
        case pending
        case cancelled
    }

    @ObservationIgnored private let logger = Logger(subsystem: "ch.kaufarchiv.app", category: "store")
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var products: [StoreKit.Product] = []
    /// Cached so the app knows the state offline and at launch (iCloud configuration).
    var isPro: Bool = UserDefaults.standard.bool(forKey: SettingsKey.cachedIsPro)
    var activeProductID: String?
    var renewalDate: Date?
    var loadError: String?
    var isLoading = false

    var yearly: StoreKit.Product? { products.first { $0.id == ProductID.yearly } }
    var lifetime: StoreKit.Product? { products.first { $0.id == ProductID.lifetime } }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await StoreKit.Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
            loadError = products.isEmpty ? "Die Angebote sind gerade nicht verfügbar." : nil
        } catch {
            loadError = "Die Angebote konnten nicht geladen werden. Prüfe die Internetverbindung."
            logger.error("Products failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshEntitlements() async {
        var pro = false
        var active: String?
        var renewal: Date?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result, transaction.revocationDate == nil else { continue }
            if ProductID.all.contains(transaction.productID) {
                if let expiration = transaction.expirationDate, expiration < Date() { continue }
                pro = true
                // Lifetime wins over the subscription for display.
                if active != ProductID.lifetime { active = transaction.productID }
                if transaction.productID == ProductID.yearly { renewal = transaction.expirationDate }
            }
        }
        isPro = pro
        UserDefaults.standard.set(pro, forKey: SettingsKey.cachedIsPro)
        activeProductID = active
        renewalDate = renewal
    }

    func purchase(_ product: StoreKit.Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw StoreKitError.notEntitled
            }
            await transaction.finish()
            await refreshEntitlements()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
}
