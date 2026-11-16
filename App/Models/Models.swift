import Foundation
import SwiftData
import KaufarchivCore

// Alle Modelle sind CloudKit-tauglich aufgebaut: Standardwerte für jedes Feld,
// optionale Beziehungen, keine eindeutigen Schlüssel.

enum ProductStatus: String, CaseIterable, Identifiable {
    case active, returned, sold, disposed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "Im Besitz"
        case .returned: return "Zurückgegeben"
        case .sold: return "Verkauft"
        case .disposed: return "Entsorgt"
        }
    }
}

enum DocumentKind: String, CaseIterable, Identifiable {
    case receipt, warrantyTerms, manual, photo, correspondence, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .receipt: return "Rechnung / Beleg"
        case .warrantyTerms: return "Garantiebedingungen"
        case .manual: return "Anleitung"
        case .photo: return "Foto"
        case .correspondence: return "Korrespondenz"
        case .other: return "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .receipt: return "doc.text"
        case .warrantyTerms: return "checkmark.shield"
        case .manual: return "book"
        case .photo: return "photo"
        case .correspondence: return "envelope"
        case .other: return "doc"
        }
    }
}

enum ClaimStatus: String, CaseIterable, Identifiable {
    case draft, sent, inProgress, resolved, rejected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Entwurf"
        case .sent: return "Gemeldet"
        case .inProgress: return "In Bearbeitung"
        case .resolved: return "Erledigt"
        case .rejected: return "Abgelehnt"
        }
    }

    var isOpen: Bool { self == .draft || self == .sent || self == .inProgress }
}

@Model
final class Receipt {
    var uid: UUID = UUID()
    var merchant: String = ""
    var purchaseDate: Date = Date()
    var totalCents: Int?
    var currency: String = "CHF"
    var channelRaw: String = PurchaseChannel.store.rawValue
    var countryCode: String = "CH"
    var orderNumber: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Fundstellen der erkannten Werte im Beleg (-1 = keine).
    var merchantLine: Int = -1
    var dateLine: Int = -1
    var totalLine: Int = -1

    @Relationship(deleteRule: .cascade, inverse: \OwnedProduct.receipt)
    var products: [OwnedProduct]? = []
    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.receipt)
    var documents: [StoredDocument]? = []

    init(merchant: String = "", purchaseDate: Date = Date()) {
        self.merchant = merchant
        self.purchaseDate = purchaseDate
    }

    var channel: PurchaseChannel {
        get { PurchaseChannel(rawValue: channelRaw) ?? .store }
        set { channelRaw = newValue.rawValue }
    }

    var productList: [OwnedProduct] { (products ?? []).sorted { $0.createdAt < $1.createdAt } }
    var documentList: [StoredDocument] { (documents ?? []).sorted { $0.createdAt < $1.createdAt } }
    var displayMerchant: String { merchant.isEmpty ? "Unbekannter Händler" : merchant }
}

@Model
final class OwnedProduct {
    var uid: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var modelName: String = ""
    var serialNumber: String = ""
    var priceCents: Int?
    var quantity: Int = 1
    var category: String = ""
    var room: String = ""
    var notes: String = ""
    var statusRaw: String = ProductStatus.active.rawValue
    var createdAt: Date = Date()
    /// Fundstelle der Position im Beleg (-1 = keine).
    var sourceLine: Int = -1

    var receipt: Receipt?

    @Relationship(deleteRule: .cascade, inverse: \Coverage.product)
    var coverages: [Coverage]? = []
    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.product)
    var documents: [StoredDocument]? = []
    @Relationship(deleteRule: .cascade, inverse: \Claim.product)
    var claims: [Claim]? = []
    @Relationship(deleteRule: .cascade, inverse: \Repair.product)
    var repairs: [Repair]? = []

    init(name: String = "") {
        self.name = name
    }

    var status: ProductStatus {
        get { ProductStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var displayName: String { name.isEmpty ? "Unbenanntes Produkt" : name }
    var coverageList: [Coverage] { (coverages ?? []).sorted { $0.endDate < $1.endDate } }
    var documentList: [StoredDocument] { (documents ?? []).sorted { $0.createdAt < $1.createdAt } }
    var claimList: [Claim] { (claims ?? []).sorted { $0.createdAt > $1.createdAt } }
    var repairList: [Repair] { (repairs ?? []).sorted { $0.date > $1.date } }
    var purchaseDate: Date { receipt?.purchaseDate ?? createdAt }
    var currency: String { receipt?.currency ?? "CHF" }

    /// Alle Unterlagen: eigene Dokumente plus die Originalrechnung.
    var allDocuments: [StoredDocument] { (receipt?.documentList ?? []) + documentList }

    /// Die Absicherung mit der längsten Restlaufzeit (ohne Rückgabe).
    func bestActiveCoverage(now: Date = Date()) -> Coverage? {
        coverageList.filter { $0.kind != .returnWindow && $0.endDate >= now }.max { $0.endDate < $1.endDate }
    }

    func nextDeadline(now: Date = Date()) -> Coverage? {
        coverageList.first { $0.endDate >= now }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        let fields = [name, brand, modelName, serialNumber, category, room, notes,
                      receipt?.merchant ?? "", receipt?.orderNumber ?? ""]
        if fields.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) { return true }
        return allDocuments.contains { $0.ocrText.localizedCaseInsensitiveContains(needle) }
    }
}

@Model
final class Coverage {
    var uid: UUID = UUID()
    var kindRaw: String = CoverageKind.legal.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()
    var provider: String = ""
    var notes: String = ""
    /// Erläuterung, woher die Frist stammt (z. B. gesetzliche Regel des Kauflandes).
    var basis: String = ""
    /// `false` = automatisch vorgeschlagen und noch nicht bestätigt.
    var isConfirmed: Bool = true
    var remindersEnabled: Bool = true

    var product: OwnedProduct?

    init(kind: CoverageKind, startDate: Date, endDate: Date, basis: String = "", isConfirmed: Bool = true) {
        self.kindRaw = kind.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.basis = basis
        self.isConfirmed = isConfirmed
    }

    var kind: CoverageKind {
        get { CoverageKind(rawValue: kindRaw) ?? .legal }
        set { kindRaw = newValue.rawValue }
    }

    func daysRemaining(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: endDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    func isActive(now: Date = Date()) -> Bool { daysRemaining(now: now) >= 0 }

    /// Verstrichener Anteil der Laufzeit (0...1).
    func progress(now: Date = Date()) -> Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startDate) / total, 0), 1)
    }
}

@Model
final class StoredDocument {
    var uid: UUID = UUID()
    var kindRaw: String = DocumentKind.receipt.rawValue
    var title: String = ""
    var filename: String = ""
    var typeIdentifier: String = "public.jpeg"
    /// Unverändertes Original. Wird nie neu komprimiert.
    @Attribute(.externalStorage) var originalData: Data?
    /// Kleine Vorschau, getrennt vom Original gespeichert.
    @Attribute(.externalStorage) var previewData: Data?
    var sha256: String = ""
    var ocrText: String = ""
    /// JSON-kodierte Belegzeilen samt Fundstellen (`[TextLine]`).
    @Attribute(.externalStorage) var linesData: Data?
    var pageCount: Int = 1
    var createdAt: Date = Date()

    var receipt: Receipt?
    var product: OwnedProduct?
    var claim: Claim?

    init(kind: DocumentKind, title: String, filename: String, typeIdentifier: String) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.filename = filename
        self.typeIdentifier = typeIdentifier
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String { title.isEmpty ? kind.label : title }

    var lines: [TextLine] {
        guard let linesData else { return [] }
        return (try? JSONDecoder().decode([TextLine].self, from: linesData)) ?? []
    }
}

@Model
final class Claim {
    var uid: UUID = UUID()
    var createdAt: Date = Date()
    var issue: String = ""
    var remedyRaw: String = ClaimRemedy.open.rawValue
    var statusRaw: String = ClaimStatus.draft.rawValue
    var contact: String = ""
    var reference: String = ""

    var product: OwnedProduct?

    @Relationship(deleteRule: .cascade, inverse: \ClaimEvent.claim)
    var events: [ClaimEvent]? = []
    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.claim)
    var documents: [StoredDocument]? = []

    init(issue: String = "") {
        self.issue = issue
    }

    var remedy: ClaimRemedy {
        get { ClaimRemedy(rawValue: remedyRaw) ?? .open }
        set { remedyRaw = newValue.rawValue }
    }

    var status: ClaimStatus {
        get { ClaimStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var eventList: [ClaimEvent] { (events ?? []).sorted { $0.date < $1.date } }
    var documentList: [StoredDocument] { (documents ?? []).sorted { $0.createdAt < $1.createdAt } }
}

@Model
final class ClaimEvent {
    var uid: UUID = UUID()
    var date: Date = Date()
    var text: String = ""

    var claim: Claim?

    init(date: Date = Date(), text: String) {
        self.date = date
        self.text = text
    }
}

@Model
final class Repair {
    var uid: UUID = UUID()
    var date: Date = Date()
    var summary: String = ""
    var provider: String = ""
    var costCents: Int?

    var product: OwnedProduct?

    init(date: Date = Date(), summary: String = "") {
        self.date = date
        self.summary = summary
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Receipt.self, OwnedProduct.self, Coverage.self, StoredDocument.self,
        Claim.self, ClaimEvent.self, Repair.self
    ]
}
