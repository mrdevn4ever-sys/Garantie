import Foundation
import StoreKit
import Observation

/// Kaufarchiv Pro über StoreKit 2. Preise werden ausschliesslich aus dem App Store geladen
/// und nirgends in der App fest hinterlegt.
@MainActor
@Observable
final class PurchaseManager {
    static let yearlyID = "ch.kaufarchiv.pro.yearly"
    static let lifetimeID = "ch.kaufarchiv.pro.lifetime"
    static let productIDs: Set<String> = [yearlyID, lifetimeID]

    var products: [StoreKit.Product] = []
    var isPro: Bool = Prefs.defaults.bool(forKey: Prefs.proCache) || Prefs.defaults.bool(forKey: Prefs.debugPro)
    var ownsLifetime = false
    var isLoading = false
    var message: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    var yearly: StoreKit.Product? { products.first { $0.id == Self.yearlyID } }
    var lifetime: StoreKit.Product? { products.first { $0.id == Self.lifetimeID } }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await StoreKit.Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            if loaded.isEmpty { message = "Die Angebote sind im Moment nicht verfügbar." }
        } catch {
            message = "Preise konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var active = false
        var lifetime = false
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = true
            if transaction.productID == Self.lifetimeID { lifetime = true }
        }
        ownsLifetime = lifetime
        Prefs.defaults.set(active, forKey: Prefs.proCache)
        isPro = active || Prefs.defaults.bool(forKey: Prefs.debugPro)
    }

    /// Liefert `true`, wenn der Kauf abgeschlossen und bestätigt wurde.
    func purchase(_ product: StoreKit.Product) async -> Bool {
        message = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "Der Kauf konnte nicht bestätigt werden."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .pending:
                message = "Der Kauf wartet auf eine Freigabe. Pro wird automatisch aktiviert, sobald er bestätigt ist."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            message = "Kauf fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        message = nil
        do {
            try await AppStore.sync()
        } catch {
            message = "Wiederherstellen fehlgeschlagen: \(error.localizedDescription)"
        }
        await refreshEntitlements()
        if !isPro, message == nil { message = "Es wurde kein aktiver Kauf gefunden." }
    }

    #if DEBUG
    func setDebugOverride(_ enabled: Bool) {
        Prefs.defaults.set(enabled, forKey: Prefs.debugPro)
        Task { await refreshEntitlements() }
    }
    #endif
}
