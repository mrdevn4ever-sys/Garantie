import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import KaufarchivCore

extension UTType {
    static let kaufarchivBackup = UTType(exportedAs: "ch.kaufarchiv.backup", conformingTo: .package)
}

// MARK: - Transfer objects (stable, versioned format)

struct BackupManifest: Codable {
    var formatVersion: Int
    var createdAt: Date
    var appVersion: String
    var purchaseCount: Int
    var productCount: Int
    var documentCount: Int
}

struct BackupData: Codable {
    var purchases: [PurchaseDTO]
}

struct PurchaseDTO: Codable {
    var id: UUID
    var merchant: String
    var purchaseDate: Date
    var deliveryDate: Date?
    var totalAmount: Decimal?
    var currency: String
    var countryCode: String
    var channel: String
    var orderNumber: String
    var notes: String
    var createdAt: Date
    var extraction: ParsedReceipt?
    var documents: [DocumentDTO]
    var products: [ProductDTO]
}

struct ProductDTO: Codable {
    var id: UUID
    var name: String
    var brand: String
    var modelName: String
    var serialNumber: String
    var articleNumber: String
    var category: String
    var room: String
    var price: Decimal?
    var quantity: Int
    var notes: String
    var status: String
    var createdAt: Date
    var source: SourceLocation?
    var coverages: [CoverageDTO]
    var documents: [DocumentDTO]
    var events: [EventDTO]
    var claims: [ClaimDTO]
}

struct CoverageDTO: Codable {
    var id: UUID
    var kind: String
    var startDate: Date
    var endDate: Date?
    var months: Int?
    var days: Int?
    var provider: String
    var notes: String
    var reminderOffsets: String
    var remindersEnabled: Bool
}

struct DocumentDTO: Codable {
    var id: UUID
    var kind: String
    var title: String
    var originalFilename: String
    var contentType: String
    var byteCount: Int
    var sha256: String
    var pageCount: Int
    var ocrText: String
    var lines: [TextLine]
    var createdAt: Date
    /// Path of the original file inside the backup package.
    var file: String
}

struct EventDTO: Codable {
    var id: UUID
    var date: Date
    var kind: String
    var title: String
    var details: String
    var cost: Decimal?
}

struct ClaimDTO: Codable {
    var id: UUID
    var createdAt: Date
    var defectNoticedOn: Date
    var defectDescription: String
    var remedy: String
    var coverageKind: String?
    var status: String
    var recipient: String
    var messageSubject: String
    var messageBody: String
    var resolution: String
    var documents: [DocumentDTO]
    var updates: [EventDTO]
}

// MARK: - File document used by `.fileExporter` / `.fileImporter`

struct BackupPackage: FileDocument {
    static var readableContentTypes: [UTType] { [.kaufarchivBackup, .folder] }
    static var writableContentTypes: [UTType] { [.kaufarchivBackup] }

    var wrapper: FileWrapper

    init(wrapper: FileWrapper) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}

struct RestoreReport {
    var purchasesAdded = 0
    var productsAdded = 0
    var documentsAdded = 0
    var skippedExisting = 0
    var corruptedDocuments: [String] = []
}

enum BackupError: LocalizedError {
    case invalidPackage
    case newerFormat

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "Diese Datei ist keine gültige Kaufarchiv-Sicherung."
        case .newerFormat: "Diese Sicherung wurde mit einer neueren App-Version erstellt. Bitte aktualisiere Kaufarchiv."
        }
    }
}

/// Complete export of all data including the untouched original files.
/// Always available, also without Pro and after a subscription ends.
enum BackupService {
    static let formatVersion = 1

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Export

    @MainActor
    static func makePackage(context: ModelContext) throws -> BackupPackage {
        let purchases = try context.fetch(FetchDescriptor<Purchase>(sortBy: [SortDescriptor(\.purchaseDate)]))
        var files: [String: FileWrapper] = [:]
        var documentCount = 0

        func export(_ doc: StoredDocument) -> DocumentDTO {
            let ext = (doc.originalFilename as NSString).pathExtension.isEmpty
                ? (UTType(doc.contentType)?.preferredFilenameExtension ?? "dat")
                : (doc.originalFilename as NSString).pathExtension
            let name = "\(doc.id.uuidString).\(ext)"
            if let data = doc.originalData {
                files[name] = FileWrapper(regularFileWithContents: data)
                documentCount += 1
            }
            return DocumentDTO(id: doc.id, kind: doc.kindRaw, title: doc.title, originalFilename: doc.originalFilename,
                               contentType: doc.contentType, byteCount: doc.byteCount, sha256: doc.sha256,
                               pageCount: doc.pageCount, ocrText: doc.ocrText, lines: doc.lines,
                               createdAt: doc.createdAt, file: "Dokumente/\(name)")
        }

        let dtos: [PurchaseDTO] = purchases.map { p in
            PurchaseDTO(
                id: p.id, merchant: p.merchant, purchaseDate: p.purchaseDate, deliveryDate: p.deliveryDate,
                totalAmount: p.totalAmount, currency: p.currency, countryCode: p.countryCode, channel: p.channelRaw,
                orderNumber: p.orderNumber, notes: p.notes, createdAt: p.createdAt, extraction: p.extraction,
                documents: p.documentList.map { export($0) },
                products: p.productList.map { product in
                    ProductDTO(
                        id: product.id, name: product.name, brand: product.brand, modelName: product.modelName,
                        serialNumber: product.serialNumber, articleNumber: product.articleNumber, category: product.category,
                        room: product.room, price: product.price, quantity: product.quantity, notes: product.notes,
                        status: product.statusRaw, createdAt: product.createdAt, source: product.source,
                        coverages: product.coverageList.map {
                            CoverageDTO(id: $0.id, kind: $0.kindRaw, startDate: $0.startDate, endDate: $0.endDate, months: $0.months,
                                        days: $0.days, provider: $0.provider, notes: $0.notes,
                                        reminderOffsets: $0.reminderOffsetsRaw, remindersEnabled: $0.remindersEnabled)
                        },
                        documents: product.documentList.map { export($0) },
                        events: product.eventList.map {
                            EventDTO(id: $0.id, date: $0.date, kind: $0.kindRaw, title: $0.title, details: $0.details, cost: $0.cost)
                        },
                        claims: product.claimList.map { claim in
                            ClaimDTO(id: claim.id, createdAt: claim.createdAt, defectNoticedOn: claim.defectNoticedOn,
                                     defectDescription: claim.defectDescription, remedy: claim.remedyRaw,
                                     coverageKind: claim.coverageKindRaw, status: claim.statusRaw, recipient: claim.recipient,
                                     messageSubject: claim.messageSubject, messageBody: claim.messageBody, resolution: claim.resolution,
                                     documents: (claim.documents ?? []).map { export($0) },
                                     updates: claim.updateList.map { EventDTO(id: $0.id, date: $0.date, kind: "update", title: $0.text, details: "", cost: nil) })
                        }
                    )
                }
            )
        }

        let productCount = dtos.reduce(0) { $0 + $1.products.count }
        let manifest = BackupManifest(formatVersion: formatVersion, createdAt: Date(),
                                      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                                      purchaseCount: dtos.count, productCount: productCount, documentCount: documentCount)

        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.addRegularFile(withContents: try encoder.encode(manifest), preferredFilename: "manifest.json")
        root.addRegularFile(withContents: try encoder.encode(BackupData(purchases: dtos)), preferredFilename: "daten.json")
        root.addRegularFile(withContents: Data(csv(dtos).utf8), preferredFilename: "Uebersicht.csv")
        root.addRegularFile(withContents: Data(readme.utf8), preferredFilename: "LIESMICH.txt")
        let docs = FileWrapper(directoryWithFileWrappers: files)
        docs.preferredFilename = "Dokumente"
        root.addFileWrapper(docs)
        return BackupPackage(wrapper: root)
    }

    static var defaultFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Kaufarchiv-Sicherung-\(f.string(from: Date()))"
    }

    static let readme = """
    Kaufarchiv – Sicherung

    Diese Sicherung enthält alle Käufe, Produkte, Fristen, Reklamationen und die unveränderten Originaldateien.

    • daten.json – vollständige Daten (maschinenlesbar)
    • Uebersicht.csv – Tabelle für Excel oder Numbers
    • Dokumente/ – Originalbelege, Fotos und Unterlagen

    Zum Wiederherstellen: Kaufarchiv › Einstellungen › Sicherung wiederherstellen.
    Jede Datei wird beim Wiederherstellen mit ihrer Prüfsumme (SHA-256) verglichen.
    """

    static func csv(_ purchases: [PurchaseDTO]) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["Produkt;Marke;Modell;Seriennummer;Händler;Kaufdatum;Preis;Währung;Gewährleistung bis;Garantie bis;Rückgabe bis;Status"]
        for p in purchases {
            for product in p.products {
                func end(_ kind: CoverageKind) -> String {
                    product.coverages.first { $0.kind == kind.rawValue }?.endDate.map { df.string(from: $0) } ?? ""
                }
                let price = product.price.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                rows.append([esc(product.name), esc(product.brand), esc(product.modelName), esc(product.serialNumber), esc(p.merchant),
                             df.string(from: p.purchaseDate), price, p.currency, end(.statutory), end(.manufacturer), end(.returnPolicy),
                             esc(ProductStatus(rawValue: product.status)?.title ?? product.status)].joined(separator: ";"))
            }
        }
        return rows.joined(separator: "\n")
    }

    // MARK: Restore

    /// Imports a backup. Existing records (same ID) are kept; each file is verified by checksum.
    @MainActor
    static func restore(from wrapper: FileWrapper, into context: ModelContext) throws -> RestoreReport {
        guard let children = wrapper.fileWrappers,
              let manifestData = children["manifest.json"]?.regularFileContents,
              let dataFile = children["daten.json"]?.regularFileContents else {
            throw BackupError.invalidPackage
        }
        let manifest = try decoder.decode(BackupManifest.self, from: manifestData)
        guard manifest.formatVersion <= formatVersion else { throw BackupError.newerFormat }
        let backup = try decoder.decode(BackupData.self, from: dataFile)
        let documentFiles = children["Dokumente"]?.fileWrappers ?? [:]

        let existingPurchases = Set(try context.fetch(FetchDescriptor<Purchase>()).map(\.id))
        var report = RestoreReport()

        func restoreDocument(_ dto: DocumentDTO) -> StoredDocument? {
            let name = (dto.file as NSString).lastPathComponent
            guard let data = documentFiles[name]?.regularFileContents else {
                report.corruptedDocuments.append(dto.originalFilename.isEmpty ? dto.title : dto.originalFilename)
                return nil
            }
            if !dto.sha256.isEmpty, DocumentStore.sha256(data) != dto.sha256 {
                report.corruptedDocuments.append(dto.originalFilename.isEmpty ? dto.title : dto.originalFilename)
            }
            let doc = StoredDocument(kind: DocumentKind(rawValue: dto.kind) ?? .other, title: dto.title,
                                     originalFilename: dto.originalFilename, contentType: dto.contentType)
            doc.id = dto.id
            doc.byteCount = data.count
            doc.sha256 = DocumentStore.sha256(data)
            doc.pageCount = dto.pageCount
            doc.ocrText = dto.ocrText
            doc.lines = dto.lines
            doc.createdAt = dto.createdAt
            doc.thumbnail = DocumentStore.thumbnail(for: data, isPDF: dto.contentType == UTType.pdf.identifier)
            context.insert(doc)
            let blob = DocumentBlob(data: data)
            context.insert(blob)
            doc.blob = blob
            report.documentsAdded += 1
            return doc
        }

        for p in backup.purchases {
            if existingPurchases.contains(p.id) {
                report.skippedExisting += 1
                continue
            }
            let purchase = Purchase(merchant: p.merchant, purchaseDate: p.purchaseDate)
            purchase.id = p.id
            purchase.deliveryDate = p.deliveryDate
            purchase.totalAmount = p.totalAmount
            purchase.currency = p.currency
            purchase.countryCode = p.countryCode
            purchase.channelRaw = p.channel
            purchase.orderNumber = p.orderNumber
            purchase.notes = p.notes
            purchase.createdAt = p.createdAt
            purchase.extraction = p.extraction
            context.insert(purchase)
            report.purchasesAdded += 1
            for d in p.documents { restoreDocument(d)?.purchase = purchase }

            for pr in p.products {
                let product = Product(name: pr.name)
                product.id = pr.id
                product.brand = pr.brand
                product.modelName = pr.modelName
                product.serialNumber = pr.serialNumber
                product.articleNumber = pr.articleNumber
                product.category = pr.category
                product.room = pr.room
                product.price = pr.price
                product.quantity = pr.quantity
                product.notes = pr.notes
                product.statusRaw = pr.status
                product.createdAt = pr.createdAt
                product.source = pr.source
                context.insert(product)
                product.purchase = purchase
                report.productsAdded += 1

                for c in pr.coverages {
                    let coverage = Coverage(kind: CoverageKind(rawValue: c.kind) ?? .statutory, start: c.startDate, months: c.months, days: c.days, end: c.endDate)
                    coverage.id = c.id
                    coverage.provider = c.provider
                    coverage.notes = c.notes
                    coverage.reminderOffsetsRaw = c.reminderOffsets
                    coverage.remindersEnabled = c.remindersEnabled
                    context.insert(coverage)
                    coverage.product = product
                }
                for d in pr.documents { restoreDocument(d)?.product = product }
                for e in pr.events {
                    let event = ProductEvent(kind: EventKind(rawValue: e.kind) ?? .note, title: e.title, details: e.details, date: e.date)
                    event.id = e.id
                    event.cost = e.cost
                    context.insert(event)
                    event.product = product
                }
                for c in pr.claims {
                    let claim = Claim(product: product)
                    claim.id = c.id
                    claim.createdAt = c.createdAt
                    claim.defectNoticedOn = c.defectNoticedOn
                    claim.defectDescription = c.defectDescription
                    claim.remedyRaw = c.remedy
                    claim.coverageKindRaw = c.coverageKind
                    claim.statusRaw = c.status
                    claim.recipient = c.recipient
                    claim.messageSubject = c.messageSubject
                    claim.messageBody = c.messageBody
                    claim.resolution = c.resolution
                    context.insert(claim)
                    claim.product = product
                    for d in c.documents { restoreDocument(d)?.claim = claim }
                    for u in c.updates {
                        let update = ClaimUpdate(text: u.title, date: u.date)
                        update.id = u.id
                        context.insert(update)
                        update.claim = claim
                    }
                }
            }
        }
        try context.save()
        return report
    }

    /// Exports and re-reads the package in memory to prove a restore would succeed.
    @MainActor
    static func verifyRoundTrip(context: ModelContext) throws -> (documents: Int, valid: Int) {
        let package = try makePackage(context: context)
        guard let children = package.wrapper.fileWrappers,
              let dataFile = children["daten.json"]?.regularFileContents else { throw BackupError.invalidPackage }
        let backup = try decoder.decode(BackupData.self, from: dataFile)
        let files = children["Dokumente"]?.fileWrappers ?? [:]
        var all: [DocumentDTO] = []
        for p in backup.purchases {
            all += p.documents
            for pr in p.products {
                all += pr.documents
                all += pr.claims.flatMap(\.documents)
            }
        }
        let valid = all.filter { dto in
            guard let data = files[(dto.file as NSString).lastPathComponent]?.regularFileContents else { return false }
            return DocumentStore.sha256(data) == dto.sha256
        }.count
        return (all.count, valid)
    }
}
