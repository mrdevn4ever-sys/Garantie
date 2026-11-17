import Foundation
import SwiftData
import CoreSpotlight
import LocalAuthentication
import UniformTypeIdentifiers
import Observation
import os

/// Spotlight: products are findable from the iOS search ("Kaffeemaschine").
enum SpotlightIndexer {
    static let domain = "ch.kaufarchiv.products"

    static func index(_ products: [Product]) {
        let items = products.map { product -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = product.name
            var description = [product.subtitle, product.purchase?.merchant ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            if let next = product.nextDeadline, let end = next.endDate {
                description += (description.isEmpty ? "" : " · ") + "\(next.kind.shortTitle) bis \(Formatters.date(end))"
            }
            attributes.contentDescription = description
            attributes.keywords = [product.brand, product.modelName, product.serialNumber, product.category, product.room].filter { !$0.isEmpty }
            attributes.thumbnailData = product.documentList.first(where: { $0.kind == .photo })?.thumbnail
                ?? product.purchase?.receiptDocuments.first?.thumbnail
            return CSSearchableItem(uniqueIdentifier: product.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}

/// Optional Face ID / code lock for the archive.
@Observable
@MainActor
final class AppLock {
    var isLocked: Bool
    var lastError: String?

    init() {
        isLocked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.appLock) }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set: the lock cannot work, do not lock the user out.
            isLocked = false
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Zugriff auf deine Belege")
            isLocked = !ok
            lastError = nil
        } catch {
            lastError = "Entsperren fehlgeschlagen."
        }
    }

    static func canUseBiometrics() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

/// Picks up files dropped by the share extension.
enum InboxImporter {
    static func pendingFiles() -> [(batch: URL, files: [IncomingFile])] {
        SharedInbox.pendingBatches().compactMap { batch in
            let files = SharedInbox.files(in: batch).compactMap { url -> IncomingFile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                guard type.conforms(to: .image) || type.conforms(to: .pdf) else { return nil }
                return IncomingFile(data: data, filename: String(url.lastPathComponent.drop { $0 != "-" }.dropFirst()), type: type)
            }
            if files.isEmpty {
                SharedInbox.remove(batch: batch)
                return nil
            }
            return (batch, files)
        }
    }
}

/// Navigation requests from notifications, Spotlight and URLs.
@Observable
@MainActor
final class AppRouter {
    enum Tab: Hashable {
        case overview, purchases, deadlines, settings
    }

    var selectedTab: Tab = .overview
    var openProductID: UUID?
    var showImport = false
    var pendingInbox: [(batch: URL, files: [IncomingFile])] = []
    var showPaywall = false
    var paywallReason: String?

    func open(productID: String) {
        guard let id = UUID(uuidString: productID) else { return }
        selectedTab = .purchases
        openProductID = id
    }

    func requestPro(reason: String) {
        paywallReason = reason
        showPaywall = true
    }

    func checkInbox() {
        let pending = InboxImporter.pendingFiles()
        if !pending.isEmpty {
            pendingInbox = pending
            showImport = true
        }
    }
}
