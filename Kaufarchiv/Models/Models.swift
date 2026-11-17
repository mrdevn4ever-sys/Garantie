import Foundation
import SwiftData
import KaufarchivCore

// All models follow the CloudKit rules for SwiftData: every attribute has a default
// value or is optional, relationships are optional and have inverses, no unique constraints.

// MARK: - Purchase (one receipt / invoice)

@Model
final class Purchase {
    var id: UUID = UUID()
    var merchant: String = ""
    var purchaseDate: Date = Date()
    var deliveryDate: Date?
    var totalAmount: Decimal?
    var currency: String = "CHF"
    var countryCode: String = "CH"
    var channelRaw: String = SalesChannel.store.rawValue
    var orderNumber: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Serialized `ParsedReceipt` so every recognised value stays traceable to its source.
    var extractionData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Product.purchase)
    var products: [Product]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.purchase)
    var documents: [StoredDocument]? = []

    init(merchant: String = "", purchaseDate: Date = Date()) {
        self.merchant = merchant
        self.purchaseDate = purchaseDate
    }

    var channel: SalesChannel {
        get { SalesChannel(rawValue: channelRaw) ?? .unknown }
        set { channelRaw = newValue.rawValue }
    }

    var extraction: ParsedReceipt? {
        get { extractionData.flatMap { try? JSONDecoder().decode(ParsedReceipt.self, from: $0) } }
        set { extractionData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var productList: [Product] { (products ?? []).sorted { $0.createdAt < $1.createdAt } }
    var documentList: [StoredDocument] { (documents ?? []).sorted { $0.createdAt < $1.createdAt } }
    var receiptDocuments: [StoredDocument] { documentList.filter { $0.kind == .receipt } }

    var displayMerchant: String { merchant.isEmpty ? "Unbekannter Händler" : merchant }
}

// MARK: - Product

enum ProductStatus: String, CaseIterable, Codable, Identifiable {
    case inUse
    case inRepair
    case returned
    case sold
    case disposed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inUse: "In Gebrauch"
        case .inRepair: "In Reparatur"
        case .returned: "Zurückgegeben"
        case .sold: "Verkauft"
        case .disposed: "Entsorgt"
        }
    }

    var symbolName: String {
        switch self {
        case .inUse: "checkmark.circle"
        case .inRepair: "wrench.and.screwdriver"
        case .returned: "arrow.uturn.backward"
        case .sold: "tag"
        case .disposed: "trash"
        }
    }

    /// Products in these states no longer get reminders.
    var isClosed: Bool { self == .returned || self == .sold || self == .disposed }
}

@Model
final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var modelName: String = ""
    var serialNumber: String = ""
    var articleNumber: String = ""
    var category: String = ""
    var room: String = ""
    var price: Decimal?
    var quantity: Int = 1
    var notes: String = ""
    var statusRaw: String = ProductStatus.inUse.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Location of the line item on the receipt (serialized `SourceLocation`).
    var sourceData: Data?

    var purchase: Purchase?

    @Relationship(deleteRule: .cascade, inverse: \Coverage.product)
    var coverages: [Coverage]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.product)
    var documents: [StoredDocument]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProductEvent.product)
    var events: [ProductEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \Claim.product)
    var claims: [Claim]? = []

    init(name: String) {
        self.name = name
    }

    var status: ProductStatus {
        get { ProductStatus(rawValue: statusRaw) ?? .inUse }
        set { statusRaw = newValue.rawValue }
    }

    var source: SourceLocation? {
        get { sourceData.flatMap { try? JSONDecoder().decode(SourceLocation.self, from: $0) } }
        set { sourceData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var coverageList: [Coverage] {
        (coverages ?? []).sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    var documentList: [StoredDocument] { (documents ?? []).sorted { $0.createdAt < $1.createdAt } }
    var eventList: [ProductEvent] { (events ?? []).sorted { $0.date > $1.date } }
    var claimList: [Claim] { (claims ?? []).sorted { $0.createdAt > $1.createdAt } }

    /// Receipts of the purchase plus the product's own documents.
    var allDocuments: [StoredDocument] { (purchase?.documentList ?? []) + documentList }

    var purchaseDate: Date { purchase?.purchaseDate ?? createdAt }

    /// The coverage that protects the product longest and is still active.
    var bestActiveCoverage: Coverage? {
        coverageList.filter { $0.status.isActive }.max { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) }
    }

    /// The next deadline that has not passed yet.
    var nextDeadline: Coverage? {
        coverageList.first { $0.status.isActive }
    }

    var subtitle: String {
        [brand, modelName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Everything the search should look at.
    var searchText: String {
        var parts = [name, brand, modelName, serialNumber, articleNumber, category, room, notes]
        if let purchase {
            parts += [purchase.merchant, purchase.orderNumber, purchase.notes]
            parts += purchase.documentList.map(\.ocrText)
        }
        parts += documentList.map { $0.title + " " + $0.ocrText }
        return parts.joined(separator: " ")
    }
}

// MARK: - Coverage

@Model
final class Coverage {
    var id: UUID = UUID()
    var kindRaw: String = CoverageKind.statutory.rawValue
    var startDate: Date = Date()
    var endDate: Date?
    var months: Int?
    var days: Int?
    var provider: String = ""
    var notes: String = ""
    var reminderOffsetsRaw: String = "30,7"
    var remindersEnabled: Bool = true
    /// False while the value is only a suggestion the user has not confirmed yet.
    var confirmed: Bool = true

    var product: Product?

    init(kind: CoverageKind, start: Date, months: Int? = nil, days: Int? = nil, end: Date? = nil) {
        self.kindRaw = kind.rawValue
        self.startDate = start
        self.months = months
        self.days = days
        self.reminderOffsetsRaw = kind.defaultReminderOffsets.map(String.init).joined(separator: ",")
        self.endDate = end ?? CoverageSpec(kind: kind, start: start, months: months, days: days).endDate()
    }

    var kind: CoverageKind {
        get { CoverageKind(rawValue: kindRaw) ?? .statutory }
        set { kindRaw = newValue.rawValue }
    }

    var reminderOffsets: [Int] {
        get { reminderOffsetsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
        set { reminderOffsetsRaw = newValue.map(String.init).joined(separator: ",") }
    }

    var status: DeadlineStatus { DeadlineCalculator.status(end: endDate, kind: kind) }

    var progress: Double { DeadlineCalculator.progress(start: startDate, end: endDate) }

    /// Recomputes `endDate` from start and duration.
    func recalculateEnd() {
        if let end = CoverageSpec(kind: kind, start: startDate, months: months, days: days).endDate() {
            endDate = end
        }
    }

    var durationLabel: String {
        if let months {
            if months % 12 == 0 { return months == 12 ? "1 Jahr" : "\(months / 12) Jahre" }
            return months == 1 ? "1 Monat" : "\(months) Monate"
        }
        if let days { return days == 1 ? "1 Tag" : "\(days) Tage" }
        return "bis Datum"
    }
}

// MARK: - Documents

enum DocumentKind: String, CaseIterable, Codable, Identifiable {
    case receipt
    case warrantyTerms
    case manual
    case photo
    case repairInvoice
    case claimDossier
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receipt: "Beleg"
        case .warrantyTerms: "Garantiebedingungen"
        case .manual: "Anleitung"
        case .photo: "Foto"
        case .repairInvoice: "Reparaturrechnung"
        case .claimDossier: "Reklamationsdossier"
        case .other: "Dokument"
        }
    }

    var symbolName: String {
        switch self {
        case .receipt: "doc.text"
        case .warrantyTerms: "checkmark.seal"
        case .manual: "book"
        case .photo: "photo"
        case .repairInvoice: "wrench.and.screwdriver"
        case .claimDossier: "folder"
        case .other: "doc"
        }
    }
}

@Model
final class StoredDocument {
    var id: UUID = UUID()
    var kindRaw: String = DocumentKind.receipt.rawValue
    var title: String = ""
    var originalFilename: String = ""
    /// Uniform type identifier of the original file (e.g. com.adobe.pdf, public.jpeg).
    var contentType: String = "public.jpeg"
    var byteCount: Int = 0
    /// SHA-256 of the original bytes, used to verify backups and restores.
    var sha256: String = ""
    var pageCount: Int = 1
    var ocrText: String = ""
    /// Serialized `[TextLine]` with positions, used to highlight values on the document.
    var linesData: Data?
    var createdAt: Date = Date()

    @Attribute(.externalStorage) var thumbnail: Data?

    @Relationship(deleteRule: .cascade, inverse: \DocumentBlob.document)
    var blob: DocumentBlob?

    var purchase: Purchase?
    var product: Product?
    var claim: Claim?

    init(kind: DocumentKind, title: String, originalFilename: String, contentType: String) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.originalFilename = originalFilename
        self.contentType = contentType
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var lines: [TextLine] {
        get { linesData.flatMap { try? JSONDecoder().decode([TextLine].self, from: $0) } ?? [] }
        set { linesData = try? JSONEncoder().encode(newValue) }
    }

    var isPDF: Bool { contentType == "com.adobe.pdf" }

    var originalData: Data? { blob?.data }
}

/// The untouched original file. Kept in its own model so lists never load the bytes.
@Model
final class DocumentBlob {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data?
    var document: StoredDocument?

    init(data: Data) {
        self.data = data
    }
}

// MARK: - History

enum EventKind: String, CaseIterable, Codable, Identifiable {
    case note
    case repair
    case service
    case claim
    case returned
    case purchase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: "Notiz"
        case .repair: "Reparatur"
        case .service: "Wartung"
        case .claim: "Reklamation"
        case .returned: "Rückgabe"
        case .purchase: "Kauf"
        }
    }

    var symbolName: String {
        switch self {
        case .note: "note.text"
        case .repair: "wrench.and.screwdriver"
        case .service: "gearshape"
        case .claim: "exclamationmark.bubble"
        case .returned: "arrow.uturn.backward"
        case .purchase: "cart"
        }
    }
}

@Model
final class ProductEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = EventKind.note.rawValue
    var title: String = ""
    var details: String = ""
    var cost: Decimal?
    var product: Product?

    init(kind: EventKind, title: String, details: String = "", date: Date = Date()) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.details = details
        self.date = date
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Claims

enum ClaimStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case sent
    case inProgress
    case resolved
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Entwurf"
        case .sent: "Gesendet"
        case .inProgress: "In Bearbeitung"
        case .resolved: "Erledigt"
        case .rejected: "Abgelehnt"
        }
    }

    var symbolName: String {
        switch self {
        case .draft: "pencil"
        case .sent: "paperplane"
        case .inProgress: "hourglass"
        case .resolved: "checkmark.circle"
        case .rejected: "xmark.octagon"
        }
    }

    var isOpen: Bool { self == .draft || self == .sent || self == .inProgress }
}

@Model
final class Claim {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var defectNoticedOn: Date = Date()
    var defectDescription: String = ""
    var remedyRaw: String = ClaimRemedy.repair.rawValue
    var coverageKindRaw: String?
    var statusRaw: String = ClaimStatus.draft.rawValue
    var recipient: String = ""
    var messageSubject: String = ""
    var messageBody: String = ""
    var resolution: String = ""
    var product: Product?

    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.claim)
    var documents: [StoredDocument]? = []

    @Relationship(deleteRule: .cascade, inverse: \ClaimUpdate.claim)
    var updates: [ClaimUpdate]? = []

    /// The relationship is set by the caller after inserting the claim into a context.
    init(product: Product) {
        self.createdAt = Date()
    }

    var status: ClaimStatus {
        get { ClaimStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var remedy: ClaimRemedy {
        get { ClaimRemedy(rawValue: remedyRaw) ?? .undecided }
        set { remedyRaw = newValue.rawValue }
    }

    var coverageKind: CoverageKind? {
        get { coverageKindRaw.flatMap(CoverageKind.init(rawValue:)) }
        set { coverageKindRaw = newValue?.rawValue }
    }

    var photos: [StoredDocument] { (documents ?? []).filter { $0.kind == .photo }.sorted { $0.createdAt < $1.createdAt } }
    var dossier: StoredDocument? { (documents ?? []).filter { $0.kind == .claimDossier }.max { $0.createdAt < $1.createdAt } }
    var updateList: [ClaimUpdate] { (updates ?? []).sorted { $0.date > $1.date } }
}

@Model
final class ClaimUpdate {
    var id: UUID = UUID()
    var date: Date = Date()
    var text: String = ""
    var claim: Claim?

    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Purchase.self, Product.self, Coverage.self, StoredDocument.self, DocumentBlob.self,
        ProductEvent.self, Claim.self, ClaimUpdate.self
    ]
}
