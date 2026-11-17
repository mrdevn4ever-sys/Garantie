import Foundation
import SwiftData
import Observation
import PDFKit
import KaufarchivCore

/// One product the user may take over from a receipt.
struct DraftItem: Identifiable, Hashable {
    var id = UUID()
    var selected: Bool
    var name: String
    var brand: String = ""
    var modelName: String = ""
    var serialNumber: String = ""
    var articleNumber: String = ""
    var category: String = ""
    var price: Decimal?
    var quantity: Int = 1
    var source: SourceLocation?
    var looksLikeService: Bool = false
}

/// Everything collected during the five-step capture flow. Nothing is written to the
/// database before the user taps "Speichern".
@Observable
@MainActor
final class ImportDraft {
    enum Phase: Equatable {
        case idle
        case recognizing(progress: Double)
        case ready
        case failed(String)
    }

    var phase: Phase = .idle
    var files: [IncomingFile] = []
    var linesPerFile: [[TextLine]] = []
    var parsed: ParsedReceipt = .empty

    var merchant: String = ""
    var purchaseDate: Date = Date()
    var hasDeliveryDate = false
    var deliveryDate: Date = Date()
    var total: Decimal?
    var currency: String = "CHF"
    var countryCode: String
    var channel: SalesChannel = .store
    var orderNumber: String = ""
    var notes: String = ""

    var items: [DraftItem] = []

    // Coverage choices (apply to every selected product, editable per product later).
    var includeReturn = false
    var returnDays = 30
    var includeWithdrawal = true
    var includeStatutory = true
    var statutoryMonths = 24
    var includeManufacturer = false
    var manufacturerMonths = 24
    var includeExtended = false
    var extendedMonths = 36
    var extendedProvider = ""

    /// Fields the parser was unsure about; the review screen marks them as suggestions.
    var suggestedFields: Set<Field> = []

    enum Field: Hashable {
        case merchant, date, total, currency, country, channel, orderNumber, returnDays, manufacturerMonths
    }

    init(defaultCountry: String) {
        self.countryCode = defaultCountry
        self.statutoryMonths = LegalRules.suggestedStatutoryMonths(for: defaultCountry) ?? 24
    }

    var selectedItems: [DraftItem] { items.filter(\.selected) }

    var allLines: [TextLine] { linesPerFile.flatMap { $0 } }

    var countryRules: CountryRules { LegalRules.rules(for: countryCode) }

    var withdrawalAvailable: Bool { channel == .online && countryRules.onlineWithdrawalDays != nil }

    // MARK: Recognition

    func add(files newFiles: [IncomingFile]) async {
        files += newFiles
        await recognize()
    }

    /// Number of pages per file, so global page numbers can be mapped back.
    var pageCounts: [Int] = []

    func recognize() async {
        guard !files.isEmpty else { return }
        phase = .recognizing(progress: 0)
        var all: [[TextLine]] = []
        var counts: [Int] = []
        var pageOffset = 0
        for (index, file) in files.enumerated() {
            let pages = file.isPDF ? max(PDFDocument(data: file.data)?.pageCount ?? 1, 1) : 1
            var lines = await TextRecognizer.recognize(data: file.data, isPDF: file.isPDF)
            // Pages are numbered across all files so a source location is unambiguous.
            lines = lines.map { line in
                var copy = line
                copy.page += pageOffset
                return copy
            }
            pageOffset += pages
            counts.append(pages)
            all.append(lines)
            phase = .recognizing(progress: Double(index + 1) / Double(files.count))
        }
        linesPerFile = all
        pageCounts = counts
        apply(ReceiptParser().parse(lines: all.flatMap { $0 }))
        phase = .ready
    }

    /// Maps a global page number back to the file and its local page.
    func location(ofPage page: Int) -> (fileIndex: Int, localPage: Int)? {
        var offset = 0
        for (index, count) in pageCounts.enumerated() {
            if page < offset + count { return (index, page - offset) }
            offset += count
        }
        return nil
    }

    func apply(_ result: ParsedReceipt) {
        parsed = result
        suggestedFields = []

        func mark<T: Codable & Hashable & Sendable>(_ value: Extracted<T>?, _ field: Field) {
            if value == nil || value!.certainty.isSuggestion { suggestedFields.insert(field) }
        }

        if let m = result.merchant { merchant = m.value }
        mark(result.merchant, .merchant)
        if let d = result.purchaseDate { purchaseDate = d.value; deliveryDate = d.value }
        mark(result.purchaseDate, .date)
        total = result.total?.value
        mark(result.total, .total)
        if let c = result.currency { currency = c.value }
        mark(result.currency, .currency)
        if let country = result.countryCode {
            countryCode = country.value
            statutoryMonths = LegalRules.suggestedStatutoryMonths(for: country.value) ?? statutoryMonths
        }
        mark(result.countryCode, .country)
        if let ch = result.channel, ch.value != .unknown { channel = ch.value }
        mark(result.channel, .channel)
        if let o = result.orderNumber { orderNumber = o.value }
        if let r = result.returnDays {
            includeReturn = true
            returnDays = r.value
            suggestedFields.insert(.returnDays)
        }
        if let w = result.manufacturerWarrantyMonths {
            includeManufacturer = true
            manufacturerMonths = w.value
            suggestedFields.insert(.manufacturerMonths)
        }

        let serials = result.serialNumbers
        items = result.items.map { item in
            var draft = DraftItem(selected: !item.looksLikeService, name: item.name, price: item.totalPrice,
                                  quantity: item.quantity, source: item.source, looksLikeService: item.looksLikeService)
            draft.articleNumber = item.articleNumber ?? ""
            // Serial number on the same line belongs to this item.
            if let serial = serials.first(where: { $0.source?.lineIndex == item.source.lineIndex }) {
                draft.serialNumber = serial.value
                draft.name = draft.name.replacingOccurrences(of: serial.value, with: "")
                    .replacingOccurrences(of: #"(?i)\b(s/n|sn|serial|seriennr\.?|seriennummer)\s*:?\s*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")))
            }
            return draft
        }
        // A lone serial number on its own line belongs to the only selected item.
        if items.filter(\.selected).count == 1, let idx = items.firstIndex(where: \.selected), items[idx].serialNumber.isEmpty, let serial = serials.first {
            items[idx].serialNumber = serial.value
        }
        if items.isEmpty {
            items = [DraftItem(selected: true, name: "")]
        }
    }

    func addManualItem() {
        items.append(DraftItem(selected: true, name: ""))
    }

    /// Recomputes defaults that depend on the country (statutory period).
    func countryChanged() {
        statutoryMonths = LegalRules.suggestedStatutoryMonths(for: countryCode) ?? statutoryMonths
        includeStatutory = LegalRules.suggestedStatutoryMonths(for: countryCode) != nil
        suggestedFields.remove(.country)
    }

    // MARK: Saving

    var coverageSpecs: [CoverageSpec] {
        let handover = hasDeliveryDate ? deliveryDate : purchaseDate
        var specs: [CoverageSpec] = []
        if includeReturn { specs.append(CoverageSpec(kind: .returnPolicy, start: purchaseDate, days: returnDays)) }
        if withdrawalAvailable, includeWithdrawal, let days = countryRules.onlineWithdrawalDays {
            specs.append(CoverageSpec(kind: .withdrawal, start: handover, days: days))
        }
        if includeStatutory { specs.append(CoverageSpec(kind: .statutory, start: handover, months: statutoryMonths)) }
        if includeManufacturer { specs.append(CoverageSpec(kind: .manufacturer, start: purchaseDate, months: manufacturerMonths)) }
        if includeExtended { specs.append(CoverageSpec(kind: .extended, start: purchaseDate, months: extendedMonths)) }
        return specs
    }

    @discardableResult
    func save(in context: ModelContext) throws -> Purchase {
        let purchase = Purchase(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), purchaseDate: purchaseDate)
        purchase.deliveryDate = hasDeliveryDate ? deliveryDate : nil
        purchase.totalAmount = total
        purchase.currency = currency
        purchase.countryCode = countryCode
        purchase.channel = channel
        purchase.orderNumber = orderNumber
        purchase.notes = notes
        purchase.extraction = parsed
        context.insert(purchase)

        for (index, file) in files.enumerated() {
            let offset = pageCounts.prefix(index).reduce(0, +)
            let lines = (index < linesPerFile.count ? linesPerFile[index] : []).map { line in
                var copy = line
                copy.page -= offset
                return copy
            }
            let title = files.count > 1 ? "Beleg \(index + 1)" : "Beleg"
            let doc = try DocumentStore.makeDocument(from: file, kind: .receipt, title: title, lines: lines, in: context)
            doc.purchase = purchase
        }

        let specs = coverageSpecs
        for item in selectedItems {
            let product = Product(name: item.name.isEmpty ? "Produkt" : item.name)
            product.brand = item.brand
            product.modelName = item.modelName
            product.serialNumber = item.serialNumber
            product.articleNumber = item.articleNumber
            product.category = item.category
            product.price = item.price
            product.quantity = item.quantity
            product.source = item.source
            context.insert(product)
            product.purchase = purchase

            for spec in specs {
                let coverage = Coverage(kind: spec.kind, start: spec.start, months: spec.months, days: spec.days)
                if spec.kind == .extended { coverage.provider = extendedProvider }
                context.insert(coverage)
                coverage.product = product
            }
            let event = ProductEvent(kind: .purchase, title: purchase.merchant.isEmpty ? "Gekauft" : "Gekauft bei \(purchase.merchant)", date: purchaseDate)
            context.insert(event)
            event.product = product
        }
        try context.save()
        return purchase
    }
}
