import Foundation
import SwiftData
import KaufarchivCore

// MARK: Sicherungsformat

struct BackupFile: Codable {
    var format: String = "kaufarchiv-backup"
    var version: Int = 1
    var createdAt: Date
    var receipts: [ReceiptDTO]
    /// Produkte ohne Rechnung.
    var looseProducts: [ProductDTO]
}

struct DocumentDTO: Codable {
    var uid: UUID
    var kindRaw: String
    var title: String
    var filename: String
    var typeIdentifier: String
    var originalData: Data?
    var previewData: Data?
    var sha256: String
    var ocrText: String
    var linesData: Data?
    var pageCount: Int
    var createdAt: Date
}

struct CoverageDTO: Codable {
    var uid: UUID
    var kindRaw: String
    var startDate: Date
    var endDate: Date
    var provider: String
    var notes: String
    var basis: String
    var isConfirmed: Bool
    var remindersEnabled: Bool
    var isDecided: Bool?
}

struct ClaimEventDTO: Codable {
    var uid: UUID
    var date: Date
    var text: String
}

struct ClaimDTO: Codable {
    var uid: UUID
    var createdAt: Date
    var issue: String
    var remedyRaw: String
    var statusRaw: String
    var contact: String
    var reference: String
    var kindRaw: String?
    var trackingNumber: String?
    var events: [ClaimEventDTO]
    var documents: [DocumentDTO]
}

struct RepairDTO: Codable {
    var uid: UUID
    var date: Date
    var summary: String
    var provider: String
    var costCents: Int?
}

struct ProductDTO: Codable {
    var uid: UUID
    var name: String
    var brand: String
    var modelName: String
    var serialNumber: String
    var priceCents: Int?
    var quantity: Int
    var category: String
    var room: String
    var notes: String
    var statusRaw: String
    var createdAt: Date
    var sourceLine: Int
    var coverages: [CoverageDTO]
    var documents: [DocumentDTO]
    var claims: [ClaimDTO]
    var repairs: [RepairDTO]
}

struct ReceiptDTO: Codable {
    var uid: UUID
    var merchant: String
    var purchaseDate: Date
    var deliveryDate: Date?
    var totalCents: Int?
    var currency: String
    var channelRaw: String
    var countryCode: String
    var orderNumber: String
    var notes: String
    var createdAt: Date
    var merchantLine: Int
    var dateLine: Int
    var totalLine: Int
    var documents: [DocumentDTO]
    var products: [ProductDTO]
}

struct BackupReport {
    var receipts = 0
    var products = 0
    var documents = 0
    /// Dokumente, deren Original fehlt oder nicht mehr zur gespeicherten Prüfsumme passt.
    var damagedDocuments: [String] = []
    var skippedExisting = 0

    var isHealthy: Bool { damagedDocuments.isEmpty }
}

enum BackupError: LocalizedError {
    case wrongFormat
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .wrongFormat: return "Die Datei ist keine Kaufarchiv-Sicherung."
        case .newerVersion: return "Die Sicherung stammt aus einer neueren App-Version. Bitte Kaufarchiv aktualisieren."
        }
    }
}

/// Vollständige Sicherung als eine einzige Datei – inklusive aller Originalbelege.
/// Bleibt in jeder Preisstufe verfügbar, damit niemand seine Unterlagen verliert.
@MainActor
enum BackupService {

    // MARK: Erstellen

    static func createBackup(context: ModelContext) throws -> URL {
        let receipts = try context.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.purchaseDate)]))
        let products = try context.fetch(FetchDescriptor<OwnedProduct>(sortBy: [SortDescriptor(\.createdAt)]))
        let file = BackupFile(
            createdAt: Date(),
            receipts: receipts.map(dto),
            looseProducts: products.filter { $0.receipt == nil }.map(dto)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        return try TempFiles.write(data, name: "Kaufarchiv-Sicherung \(Fmt.fileStamp()).json")
    }

    // MARK: Prüfen

    static func read(url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data), file.format == "kaufarchiv-backup" else {
            throw BackupError.wrongFormat
        }
        guard file.version <= 1 else { throw BackupError.newerVersion }
        return file
    }

    /// Liest eine Sicherung vollständig ein und prüft jedes Original gegen seine Prüfsumme.
    static func verify(url: URL) throws -> BackupReport {
        verify(file: try read(url: url))
    }

    static func verify(file: BackupFile) -> BackupReport {
        var report = BackupReport()
        func checkDocuments(_ documents: [DocumentDTO]) {
            for document in documents {
                report.documents += 1
                guard let data = document.originalData, !data.isEmpty else {
                    report.damagedDocuments.append(document.filename)
                    continue
                }
                if !document.sha256.isEmpty, Hashing.sha256(data) != document.sha256 {
                    report.damagedDocuments.append(document.filename)
                }
            }
        }
        func checkProducts(_ products: [ProductDTO]) {
            for product in products {
                report.products += 1
                checkDocuments(product.documents)
                for claim in product.claims { checkDocuments(claim.documents) }
            }
        }
        for receipt in file.receipts {
            report.receipts += 1
            checkDocuments(receipt.documents)
            checkProducts(receipt.products)
        }
        checkProducts(file.looseProducts)
        return report
    }

    // MARK: Wiederherstellen

    /// Ergänzt fehlende Einträge. Bereits vorhandene Käufe (gleiche Kennung) bleiben unverändert.
    static func restore(url: URL, context: ModelContext) throws -> BackupReport {
        let file = try read(url: url)
        var report = verify(file: file)

        let existingReceipts = Set(try context.fetch(FetchDescriptor<Receipt>()).map { $0.uid })
        let existingProducts = Set(try context.fetch(FetchDescriptor<OwnedProduct>()).map { $0.uid })

        for dto in file.receipts {
            if existingReceipts.contains(dto.uid) {
                report.skippedExisting += 1
                continue
            }
            let receipt = Receipt(merchant: dto.merchant, purchaseDate: dto.purchaseDate)
            receipt.uid = dto.uid
            receipt.deliveryDate = dto.deliveryDate
            receipt.totalCents = dto.totalCents
            receipt.currency = dto.currency
            receipt.channelRaw = dto.channelRaw
            receipt.countryCode = dto.countryCode
            receipt.orderNumber = dto.orderNumber
            receipt.notes = dto.notes
            receipt.createdAt = dto.createdAt
            receipt.merchantLine = dto.merchantLine
            receipt.dateLine = dto.dateLine
            receipt.totalLine = dto.totalLine
            context.insert(receipt)
            for documentDTO in dto.documents {
                let document = model(documentDTO)
                context.insert(document)
                document.receipt = receipt
            }
            for productDTO in dto.products where !existingProducts.contains(productDTO.uid) {
                let product = insertProduct(productDTO, context: context)
                product.receipt = receipt
            }
        }
        for productDTO in file.looseProducts {
            if existingProducts.contains(productDTO.uid) {
                report.skippedExisting += 1
                continue
            }
            _ = insertProduct(productDTO, context: context)
        }
        try context.save()
        return report
    }

    // MARK: Abbildung Modell -> Sicherung

    private static func dto(_ receipt: Receipt) -> ReceiptDTO {
        ReceiptDTO(
            uid: receipt.uid, merchant: receipt.merchant, purchaseDate: receipt.purchaseDate,
            deliveryDate: receipt.deliveryDate, totalCents: receipt.totalCents, currency: receipt.currency, channelRaw: receipt.channelRaw,
            countryCode: receipt.countryCode, orderNumber: receipt.orderNumber, notes: receipt.notes,
            createdAt: receipt.createdAt, merchantLine: receipt.merchantLine, dateLine: receipt.dateLine,
            totalLine: receipt.totalLine,
            documents: receipt.documentList.map(dto),
            products: receipt.productList.map(dto)
        )
    }

    private static func dto(_ product: OwnedProduct) -> ProductDTO {
        ProductDTO(
            uid: product.uid, name: product.name, brand: product.brand, modelName: product.modelName,
            serialNumber: product.serialNumber, priceCents: product.priceCents, quantity: product.quantity,
            category: product.category, room: product.room, notes: product.notes, statusRaw: product.statusRaw,
            createdAt: product.createdAt, sourceLine: product.sourceLine,
            coverages: product.coverageList.map { coverage in
                CoverageDTO(
                    uid: coverage.uid, kindRaw: coverage.kindRaw, startDate: coverage.startDate,
                    endDate: coverage.endDate, provider: coverage.provider, notes: coverage.notes,
                    basis: coverage.basis, isConfirmed: coverage.isConfirmed, remindersEnabled: coverage.remindersEnabled,
                    isDecided: coverage.isDecided
                )
            },
            documents: product.documentList.map(dto),
            claims: product.claimList.map { claim in
                ClaimDTO(
                    uid: claim.uid, createdAt: claim.createdAt, issue: claim.issue, remedyRaw: claim.remedyRaw,
                    statusRaw: claim.statusRaw, contact: claim.contact, reference: claim.reference,
                    kindRaw: claim.kindRaw, trackingNumber: claim.trackingNumber,
                    events: claim.eventList.map { ClaimEventDTO(uid: $0.uid, date: $0.date, text: $0.text) },
                    documents: claim.documentList.map(dto)
                )
            },
            repairs: product.repairList.map {
                RepairDTO(uid: $0.uid, date: $0.date, summary: $0.summary, provider: $0.provider, costCents: $0.costCents)
            }
        )
    }

    private static func dto(_ document: StoredDocument) -> DocumentDTO {
        DocumentDTO(
            uid: document.uid, kindRaw: document.kindRaw, title: document.title, filename: document.filename,
            typeIdentifier: document.typeIdentifier, originalData: document.originalData,
            previewData: document.previewData, sha256: document.sha256, ocrText: document.ocrText,
            linesData: document.linesData, pageCount: document.pageCount, createdAt: document.createdAt
        )
    }

    // MARK: Abbildung Sicherung -> Modell

    private static func model(_ dto: DocumentDTO) -> StoredDocument {
        let document = StoredDocument(
            kind: DocumentKind(rawValue: dto.kindRaw) ?? .other,
            title: dto.title, filename: dto.filename, typeIdentifier: dto.typeIdentifier
        )
        document.uid = dto.uid
        document.originalData = dto.originalData
        document.previewData = dto.previewData
        document.sha256 = dto.sha256
        document.ocrText = dto.ocrText
        document.linesData = dto.linesData
        document.pageCount = dto.pageCount
        document.createdAt = dto.createdAt
        return document
    }

    private static func insertProduct(_ dto: ProductDTO, context: ModelContext) -> OwnedProduct {
        let product = OwnedProduct(name: dto.name)
        product.uid = dto.uid
        product.brand = dto.brand
        product.modelName = dto.modelName
        product.serialNumber = dto.serialNumber
        product.priceCents = dto.priceCents
        product.quantity = dto.quantity
        product.category = dto.category
        product.room = dto.room
        product.notes = dto.notes
        product.statusRaw = dto.statusRaw
        product.createdAt = dto.createdAt
        product.sourceLine = dto.sourceLine
        context.insert(product)

        for coverageDTO in dto.coverages {
            let coverage = Coverage(
                kind: CoverageKind(rawValue: coverageDTO.kindRaw) ?? .legal,
                startDate: coverageDTO.startDate, endDate: coverageDTO.endDate,
                basis: coverageDTO.basis, isConfirmed: coverageDTO.isConfirmed
            )
            coverage.uid = coverageDTO.uid
            coverage.provider = coverageDTO.provider
            coverage.notes = coverageDTO.notes
            coverage.remindersEnabled = coverageDTO.remindersEnabled
            coverage.isDecided = coverageDTO.isDecided ?? false
            context.insert(coverage)
            coverage.product = product
        }
        for documentDTO in dto.documents {
            let document = model(documentDTO)
            context.insert(document)
            document.product = product
        }
        for claimDTO in dto.claims {
            let claim = Claim(issue: claimDTO.issue)
            claim.uid = claimDTO.uid
            claim.createdAt = claimDTO.createdAt
            claim.remedyRaw = claimDTO.remedyRaw
            claim.statusRaw = claimDTO.statusRaw
            claim.contact = claimDTO.contact
            claim.reference = claimDTO.reference
            claim.kindRaw = claimDTO.kindRaw ?? ClaimKind.defect.rawValue
            claim.trackingNumber = claimDTO.trackingNumber ?? ""
            context.insert(claim)
            claim.product = product
            for eventDTO in claimDTO.events {
                let event = ClaimEvent(date: eventDTO.date, text: eventDTO.text)
                event.uid = eventDTO.uid
                context.insert(event)
                event.claim = claim
            }
            for documentDTO in claimDTO.documents {
                let document = model(documentDTO)
                context.insert(document)
                document.claim = claim
            }
        }
        for repairDTO in dto.repairs {
            let repair = Repair(date: repairDTO.date, summary: repairDTO.summary)
            repair.uid = repairDTO.uid
            repair.provider = repairDTO.provider
            repair.costCents = repairDTO.costCents
            context.insert(repair)
            repair.product = product
        }
        return product
    }
}

// MARK: Einfache Exporte (immer kostenlos)

@MainActor
enum ExportService {
    /// Produktliste als CSV für Tabellenprogramme.
    static func productsCSV(context: ModelContext) throws -> URL {
        let products = try context.fetch(FetchDescriptor<OwnedProduct>(sortBy: [SortDescriptor(\.createdAt)]))
        let header = ["Produkt", "Marke", "Modell", "Seriennummer", "Kategorie", "Raum", "Status", "Händler",
                      "Kaufdatum", "Preis", "Währung", "Bestellnummer", "Rückgabe bis", "Mängelrechte bis",
                      "Herstellergarantie bis", "Zusatzgarantie bis", "Notizen"]
        let rows: [[String]] = products.map { product in
            func end(_ kind: CoverageKind) -> String {
                product.coverageList.last { $0.kind == kind }.map { Fmt.date($0.endDate) } ?? ""
            }
            return [
                product.name, product.brand, product.modelName, product.serialNumber, product.category, product.room,
                product.status.label, product.receipt?.merchant ?? "", Fmt.date(product.purchaseDate),
                Money.plainText(cents: product.priceCents), product.currency, product.receipt?.orderNumber ?? "",
                end(.returnWindow), end(.legal), end(.manufacturer), end(.extended), product.notes
            ]
        }
        let csv = CSVBuilder.document(header: header, rows: rows)
        return try TempFiles.write(Data(csv.utf8), name: "Kaufarchiv-Produkte \(Fmt.fileStamp()).csv")
    }

    /// Alle Originaldateien unverändert, nach Kauf geordnet, als ZIP-Archiv.
    static func originalsArchive(context: ModelContext) throws -> URL {
        let documents = try context.fetch(FetchDescriptor<StoredDocument>(sortBy: [SortDescriptor(\.createdAt)]))
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kaufarchiv", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("Kaufarchiv-Originale", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for (index, document) in documents.enumerated() {
            guard let data = document.originalData else { continue }
            let owner = document.receipt.map { "\(Fmt.fileStamp($0.purchaseDate).prefix(10)) \($0.displayMerchant)" }
                ?? document.product?.displayName
                ?? document.claim?.product.map { "Reklamation \($0.displayName)" }
                ?? "Weitere Dokumente"
            let folder = root.appendingPathComponent(TempFiles.safeName(owner), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = TempFiles.safeName(document.filename.isEmpty ? "Dokument \(index + 1)" : document.filename)
            var target = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(index + 1) \(name)")
            }
            try data.write(to: target)
        }

        var coordinatorError: NSError?
        var copyError: Error?
        var result: URL?
        NSFileCoordinator().coordinate(readingItemAt: root, options: [.forUploading], error: &coordinatorError) { zipURL in
            let target = base.appendingPathComponent("Kaufarchiv-Originale \(Fmt.fileStamp()).zip")
            do {
                try FileManager.default.copyItem(at: zipURL, to: target)
                result = target
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }
}
