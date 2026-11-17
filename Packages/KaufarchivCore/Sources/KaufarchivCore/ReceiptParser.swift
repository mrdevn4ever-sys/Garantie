import Foundation

/// A purchasable position found on a receipt.
public struct ParsedLineItem: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { source.lineIndex }
    public var name: String
    public var quantity: Int
    public var unitPrice: Decimal?
    public var totalPrice: Decimal
    public var articleNumber: String?
    public var source: SourceLocation
    /// True for items that look like services, fees or deposits rather than products.
    public var looksLikeService: Bool

    public init(name: String, quantity: Int, unitPrice: Decimal?, totalPrice: Decimal, articleNumber: String?, source: SourceLocation, looksLikeService: Bool) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
        self.articleNumber = articleNumber
        self.source = source
        self.looksLikeService = looksLikeService
    }
}

public enum SalesChannel: String, Codable, CaseIterable, Sendable {
    case store
    case online
    case unknown
}

/// Classification of a receipt line that carries an amount.
public enum AmountRole: String, Codable, Sendable {
    case total
    case subtotal
    case cashGiven
    case change
    case discount
    case tax
    case deposit
    case cardPayment
    case item
    case other
}

public struct ClassifiedAmount: Codable, Hashable, Sendable {
    public var role: AmountRole
    public var amount: Decimal
    public var source: SourceLocation
}

public struct ParsedReceipt: Codable, Hashable, Sendable {
    public var merchant: Extracted<String>?
    public var purchaseDate: Extracted<Date>?
    public var total: Extracted<Decimal>?
    public var currency: Extracted<String>?
    public var items: [ParsedLineItem]
    public var serialNumbers: [Extracted<String>]
    public var orderNumber: Extracted<String>?
    public var channel: Extracted<SalesChannel>?
    public var countryCode: Extracted<String>?
    public var manufacturerWarrantyMonths: Extracted<Int>?
    public var returnWindowDays: Extracted<Int>?
    /// Every amount the parser classified, so the UI can explain its choice.
    public var classifiedAmounts: [ClassifiedAmount]
    public var fullText: String

    public static let empty = ParsedReceipt(merchant: nil, purchaseDate: nil, total: nil, currency: nil, items: [], serialNumbers: [], orderNumber: nil, channel: nil, countryCode: nil, manufacturerWarrantyMonths: nil, returnWindowDays: nil, classifiedAmounts: [], fullText: "")
}

/// Heuristic, fully on-device receipt parser. It never picks "the biggest number":
/// every amount is classified (total, cash given, change, discount, tax, deposit …) first.
public struct ReceiptParser: Sendable {
    public var now: Date

    public init(now: Date = Date()) {
        self.now = now
    }

    // MARK: Keyword tables (lower-case, diacritics folded)

    static let totalKeywords = ["total", "gesamt", "gesamtbetrag", "summe", "zu bezahlen", "zu zahlen", "zahlbetrag",
                                "endbetrag", "rechnungsbetrag", "betrag chf", "betrag eur", "amount due", "grand total",
                                "montant", "montant du", "a payer", "totale", "importo", "da pagare", "total chf", "total eur"]
    static let strongTotalKeywords = ["zu bezahlen", "zu zahlen", "zahlbetrag", "endbetrag", "rechnungsbetrag",
                                      "amount due", "grand total", "a payer", "da pagare", "gesamtbetrag"]
    static let subtotalKeywords = ["zwischensumme", "zwischentotal", "subtotal", "sub-total", "sous-total", "sous total", "subtotale", "netto", "total exkl", "total excl", "total ohne"]
    static let cashKeywords = ["bar ", "bargeld", "gegeben", "erhalten", "cash", "especes", "contanti", "bar:", "bar chf", "bar eur"]
    static let changeKeywords = ["ruckgeld", "retour", "zuruck", "change", "rendu", "resto", "wechselgeld"]
    static let discountKeywords = ["rabatt", "aktion", "discount", "remise", "sconto", "gutschein", "coupon", "nachlass", "reduktion", "reduction", "cumulus", "supercard", "bonus"]
    static let taxKeywords = ["mwst", "mw st", "ust", "tva", "iva", "vat", "steuer", "inkl.", "incl.", "tax", "mehrwertsteuer"]
    static let depositKeywords = ["anzahlung", "teilzahlung", "acompte", "restbetrag", "offen", "saldo", "acconto", "depot", "pfand"]
    static let cardKeywords = ["visa", "mastercard", "maestro", "twint", "postfinance", "ec-karte", "ec karte", "girocard", "amex", "american express", "kartenzahlung", "karte", "debit", "kreditkarte", "apple pay", "google pay", "v pay", "carte"]
    static let ignoreItemKeywords = ["datum", "date", "uhrzeit", "kasse", "beleg", "quittung", "filiale", "tel", "telefon", "fax", "uid", "che-", "mwst-nr", "ust-id", "iban", "terminal", "trx", "transaktion", "autorisierung", "bon", "danke", "merci", "grazie", "thank", "kunde", "kundennummer", "seite", "page"]
    static let serviceKeywords = ["versand", "lieferung", "porto", "shipping", "service", "gebuhr", "installation", "montage", "entsorgung", "vrg", "vorgezogene recycling", "recycling", "garantieverlangerung", "versicherung", "pfand", "tasche", "bag"]

    // MARK: Entry point

    public func parse(lines rawLines: [TextLine]) -> ParsedReceipt {
        let lines = rawLines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let folded = lines.map { Self.fold($0.text) }
        let fullText = lines.map(\.text).joined(separator: "\n")

        var result = ParsedReceipt.empty
        result.fullText = fullText

        result.currency = detectCurrency(lines: lines)
        result.purchaseDate = detectDate(lines: lines, folded: folded)
        result.merchant = detectMerchant(lines: lines, folded: folded)

        let classified = classifyAmounts(lines: lines, folded: folded)
        result.classifiedAmounts = classified
        result.items = detectItems(lines: lines, folded: folded, classified: classified)
        result.total = detectTotal(classified: classified, items: result.items)
        result.serialNumbers = detectSerials(lines: lines)
        result.orderNumber = detectOrderNumber(lines: lines, folded: folded)
        result.channel = detectChannel(lines: lines, folded: folded)
        result.countryCode = detectCountry(lines: lines, folded: folded, currency: result.currency?.value)
        result.manufacturerWarrantyMonths = detectWarrantyMonths(lines: lines, folded: folded)
        result.returnWindowDays = detectReturnDays(lines: lines, folded: folded)
        return result
    }

    /// Convenience for plain text (one line per `\n`).
    public func parse(text: String) -> ParsedReceipt {
        let lines = text.components(separatedBy: .newlines).enumerated().map { index, text in
            TextLine(text: text, page: 0, rect: NormalizedRect(x: 0, y: Double(index) / 100, width: 1, height: 0.01))
        }
        return parse(lines: lines)
    }

    // MARK: Helpers

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_CH"))
            .replacingOccurrences(of: "  ", with: " ")
    }

    static func contains(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { keyword in
            if keyword.count <= 4, !keyword.contains(" "), !keyword.hasSuffix(".") , !keyword.hasSuffix("-"), !keyword.hasSuffix(":") {
                // Short keywords must be whole words (avoid "bar" in "Barcode").
                return text.range(of: "(^|[^a-z])\(NSRegularExpression.escapedPattern(for: keyword))([^a-z]|$)", options: .regularExpression) != nil
            }
            return text.contains(keyword)
        }
    }

    // MARK: Currency

    func detectCurrency(lines: [TextLine]) -> Extracted<String>? {
        var counts: [String: (Int, Int)] = [:] // currency -> (count, first line index)
        for (index, line) in lines.enumerated() {
            if let c = MoneyParser.detectCurrency(in: line.text) {
                let entry = counts[c] ?? (0, index)
                counts[c] = (entry.0 + 1, entry.1)
            }
        }
        guard let best = counts.max(by: { $0.value.0 < $1.value.0 }) else { return nil }
        let index = best.value.1
        return Extracted(value: best.key, certainty: best.value.0 >= 2 ? .certain : .likely, source: SourceLocation(line: lines[index], index: index))
    }

    // MARK: Date

    func detectDate(lines: [TextLine], folded: [String]) -> Extracted<Date>? {
        let dateKeywords = ["datum", "date", "rechnungsdatum", "kaufdatum", "belegdatum", "bestelldatum", "data", "invoice date"]
        let avoidKeywords = ["liefer", "versand", "fallig", "zahlbar bis", "gultig bis", "valid until", "ablauf", "expiry", "mhd", "best before"]
        var best: (Extracted<Date>, Int)?
        for (index, line) in lines.enumerated() {
            let matches = DateParser.dates(in: line.text, now: now)
            guard let first = matches.first else { continue }
            var score = 1
            if Self.contains(folded[index], any: dateKeywords) { score += 3 }
            if Self.contains(folded[index], any: avoidKeywords) { score -= 3 }
            if index < lines.count / 2 { score += 1 }
            let extracted = Extracted(value: first.date, certainty: score >= 4 ? .certain : (score >= 1 ? .likely : .guess), source: SourceLocation(line: line, index: index))
            if best == nil || score > best!.1 {
                best = (extracted, score)
            }
        }
        if let (value, _) = best, value.certainty == .likely {
            // Single date on the whole receipt is reliable enough.
            let allDates = Set(lines.flatMap { DateParser.dates(in: $0.text, now: now).map(\.date) })
            if allDates.count == 1 {
                return Extracted(value: value.value, certainty: .certain, source: value.source)
            }
        }
        return best?.0
    }

    // MARK: Merchant

    func detectMerchant(lines: [TextLine], folded: [String]) -> Extracted<String>? {
        let skip = ["quittung", "rechnung", "beleg", "kassenbon", "invoice", "receipt", "facture", "ricevuta", "kopie", "copy", "duplikat", "willkommen", "welcome", "bienvenue", "lieferschein", "bestellbestatigung"]
        for (index, line) in lines.prefix(8).enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            guard letters >= 3, digits <= letters / 2 else { continue }
            if Self.contains(folded[index], any: skip) { continue }
            if !DateParser.dates(in: text, now: now).isEmpty { continue }
            if text.contains("@") || folded[index].hasPrefix("www") || folded[index].hasPrefix("tel") { continue }
            let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "*-=_#. "))
            guard !cleaned.isEmpty else { continue }
            return Extracted(value: cleaned, certainty: index == 0 ? .likely : .guess, source: SourceLocation(line: line, index: index))
        }
        return nil
    }

    // MARK: Amounts

    func classifyAmounts(lines: [TextLine], folded: [String]) -> [ClassifiedAmount] {
        var result: [ClassifiedAmount] = []
        for (index, line) in lines.enumerated() {
            // Dates such as 14.11.2026 would otherwise be read as the price 14.11.
            let amounts = MoneyParser.priceAmounts(in: DateParser.removingDates(from: line.text))
            guard let last = amounts.last else { continue }
            let f = folded[index]
            let role: AmountRole
            if Self.contains(f, any: Self.changeKeywords) {
                role = .change
            } else if Self.contains(f, any: Self.subtotalKeywords) {
                role = .subtotal
            } else if Self.contains(f, any: Self.depositKeywords) {
                role = .deposit
            } else if Self.contains(f, any: Self.taxKeywords) && !Self.contains(f, any: Self.strongTotalKeywords) && !f.hasPrefix("total") {
                role = .tax
            } else if Self.contains(f, any: Self.totalKeywords) {
                role = .total
            } else if Self.contains(f, any: Self.cashKeywords) {
                role = .cashGiven
            } else if Self.contains(f, any: Self.discountKeywords) || last < 0 {
                role = .discount
            } else if Self.contains(f, any: Self.cardKeywords) {
                role = .cardPayment
            } else if Self.contains(f, any: Self.ignoreItemKeywords) {
                role = .other
            } else {
                role = .item
            }
            result.append(ClassifiedAmount(role: role, amount: last, source: SourceLocation(line: line, index: index)))
        }
        return result
    }

    func detectTotal(classified: [ClassifiedAmount], items: [ParsedLineItem]) -> Extracted<Decimal>? {
        let totals = classified.filter { $0.role == .total && $0.amount > 0 }
        let payments = classified.filter { $0.role == .cardPayment && $0.amount > 0 }.map(\.amount)
        let cash = classified.first { $0.role == .cashGiven }?.amount
        let change = classified.first { $0.role == .change }?.amount
        let itemSum = items.reduce(Decimal(0)) { $0 + $1.totalPrice }
        let discounts = classified.filter { $0.role == .discount }.reduce(Decimal(0)) { $0 + ($1.amount < 0 ? $1.amount : -$1.amount) }
        let cashPaid: Decimal? = {
            guard let cash, let change else { return nil }
            return cash - change
        }()

        func confirmations(_ value: Decimal) -> Int {
            var n = 0
            if payments.contains(value) { n += 1 }
            if cashPaid == value { n += 1 }
            if !items.isEmpty, abs(NSDecimalNumber(decimal: (itemSum + discounts) - value).doubleValue) < 0.011 { n += 1 }
            if !items.isEmpty, abs(NSDecimalNumber(decimal: itemSum - value).doubleValue) < 0.011 { n += 1 }
            return n
        }

        if !totals.isEmpty {
            // Score: explicit confirmation > position (later "total" lines usually are the final amount).
            let scored = totals.enumerated().map { offset, candidate -> (ClassifiedAmount, Int) in
                var score = confirmations(candidate.amount) * 10
                score += offset // later is better
                if cash != nil, candidate.amount == cash, cash != cashPaid { score -= 20 }
                return (candidate, score)
            }
            let best = scored.max { $0.1 < $1.1 }!
            let distinctValues = Set(totals.map(\.amount))
            let certainty: Certainty = confirmations(best.0.amount) > 0 || distinctValues.count == 1 ? .certain : .likely
            return Extracted(value: best.0.amount, certainty: certainty, source: best.0.source)
        }
        if let payment = classified.last(where: { $0.role == .cardPayment && $0.amount > 0 }) {
            return Extracted(value: payment.amount, certainty: .likely, source: payment.source)
        }
        if let cashPaid, cashPaid > 0, let changeLine = classified.first(where: { $0.role == .change }) {
            return Extracted(value: cashPaid, certainty: .likely, source: changeLine.source)
        }
        if !items.isEmpty {
            return Extracted(value: itemSum + discounts, certainty: .guess, source: items.last?.source)
        }
        return nil
    }

    // MARK: Items

    private static let quantityPrefix = try! NSRegularExpression(pattern: #"^\s*(\d{1,3})\s*(?:x|X|×|stk\.?|Stk\.?|pcs|pce|St\.?)\s+"#)
    private static let quantityInline = try! NSRegularExpression(pattern: #"(\d{1,3})\s*(?:x|×|@)\s*\d"#)
    private static let articleNumber = try! NSRegularExpression(pattern: #"\b(?:art(?:ikel)?[\s.\-]*(?:nr|no)\.?|sku|ean|ref\.?)\s*:?\s*([A-Z0-9\-]*\d[A-Z0-9\-]*)|\b(\d{8,14})\b"#, options: [.caseInsensitive])

    func detectItems(lines: [TextLine], folded: [String], classified: [ClassifiedAmount]) -> [ParsedLineItem] {
        let firstTotalIndex = classified.first { [.total, .subtotal, .cashGiven, .change, .cardPayment].contains($0.role) }?.source.lineIndex ?? lines.count
        var items: [ParsedLineItem] = []
        for entry in classified where entry.role == .item && entry.source.lineIndex < firstTotalIndex && entry.amount > 0 {
            let index = entry.source.lineIndex
            var text = lines[index].text
            let ns = text as NSString

            var quantity = 1
            if let m = Self.quantityPrefix.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               let q = Int(ns.substring(with: m.range(at: 1))), q > 0 {
                quantity = q
                text = ns.replacingCharacters(in: m.range, with: "")
            } else if let m = Self.quantityInline.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                      let q = Int(ns.substring(with: m.range(at: 1))), q > 0 {
                quantity = q
            }

            var article: String?
            let ns2 = text as NSString
            if let m = Self.articleNumber.firstMatch(in: text, range: NSRange(location: 0, length: ns2.length)) {
                let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                if r.location != NSNotFound { article = ns2.substring(with: r) }
            }

            let name = Self.cleanItemName(text)
            guard name.filter(\.isLetter).count >= 2 else {
                // Name may be on the previous line (common on two-line receipts).
                if index > 0, classified.first(where: { $0.source.lineIndex == index - 1 }) == nil {
                    let previous = Self.cleanItemName(lines[index - 1].text)
                    if previous.filter(\.isLetter).count >= 2 {
                        let src = SourceLocation(page: lines[index].page, rect: lines[index - 1].rect.union(lines[index].rect), lineIndex: index, excerpt: lines[index - 1].text + " " + lines[index].text)
                        items.append(makeItem(name: previous, quantity: quantity, total: entry.amount, article: article, source: src, folded: Self.fold(previous)))
                    }
                }
                continue
            }
            items.append(makeItem(name: name, quantity: quantity, total: entry.amount, article: article, source: entry.source, folded: folded[index]))
        }
        return items
    }

    private func makeItem(name: String, quantity: Int, total: Decimal, article: String?, source: SourceLocation, folded: String) -> ParsedLineItem {
        let unit: Decimal? = quantity > 1 ? total / Decimal(quantity) : total
        return ParsedLineItem(name: name, quantity: quantity, unitPrice: unit, totalPrice: total, articleNumber: article, source: source,
                              looksLikeService: Self.contains(folded, any: Self.serviceKeywords))
    }

    static func cleanItemName(_ raw: String) -> String {
        var s = raw
        // Remove amounts, currency codes, VAT markers and stray symbols.
        s = s.replacingOccurrences(of: #"-?\d{1,3}(?:['’.,]\d{3})*(?:[.,](?:\d{2}|-{1,2}|–))"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(CHF|EUR|USD|GBP|Fr\.)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s[A-D0-9]\s*$"#, with: " ", options: .regularExpression) // trailing VAT code
        s = s.replacingOccurrences(of: #"\s\d{1,3}\s*(x|×|@)\s*"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[€$£*#=_|]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:.,")))
    }

    // MARK: Serial / order numbers

    private static let serialRegex = try! NSRegularExpression(pattern: #"\b(?:s/n|sn|serial(?:\s*(?:no|nr|number))?|serien[- ]?(?:nr|nummer)|imei|seriennr)\.?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-/]{4,30})"#, options: [.caseInsensitive])
    private static let orderRegex = try! NSRegularExpression(pattern: #"(?:bestell(?:ung|nummer|-?nr)|auftrag(?:snummer|s-?nr)?|order(?:\s*(?:no|nr|number|id))?|rechnungs?[\s\-]*(?:nummer|nr)|invoice\s*(?:no|nr|number)?|beleg[\s\-]*(?:nummer|nr)|facture\s*n[o°]?)\.?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-/]{3,30})"#, options: [.caseInsensitive])

    func detectSerials(lines: [TextLine]) -> [Extracted<String>] {
        var found: [Extracted<String>] = []
        for (index, line) in lines.enumerated() {
            let ns = line.text as NSString
            for m in Self.serialRegex.matches(in: line.text, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: m.range(at: 1))
                guard value.contains(where: \.isNumber) else { continue }
                found.append(Extracted(value: value, certainty: .likely, source: SourceLocation(line: line, index: index)))
            }
        }
        return found
    }

    func detectOrderNumber(lines: [TextLine], folded: [String]) -> Extracted<String>? {
        for (index, line) in lines.enumerated() {
            let ns = line.text as NSString
            if let m = Self.orderRegex.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: m.range(at: 1))
                guard value.contains(where: \.isNumber) else { continue }
                return Extracted(value: value, certainty: .likely, source: SourceLocation(line: line, index: index))
            }
        }
        return nil
    }

    // MARK: Channel, country, policies

    func detectChannel(lines: [TextLine], folded: [String]) -> Extracted<SalesChannel>? {
        let online = ["bestellbestatigung", "bestellung", "versand", "lieferadresse", "lieferung an", "online", "order confirmation", "shipping", "tracking", "paket", "www.", "commande", "livraison"]
        let store = ["kasse", "filiale", "kassierer", "verkaufer", "bon-nr", "terminal", "caisse", "cassa", "rückgeld", "ruckgeld", "bar "]
        var onlineHit: (Int, TextLine)?
        var storeHit: (Int, TextLine)?
        for (index, f) in folded.enumerated() {
            if onlineHit == nil, Self.contains(f, any: online) { onlineHit = (index, lines[index]) }
            if storeHit == nil, Self.contains(f, any: store) { storeHit = (index, lines[index]) }
        }
        switch (onlineHit, storeHit) {
        case let (o?, nil): return Extracted(value: .online, certainty: .likely, source: SourceLocation(line: o.1, index: o.0))
        case let (nil, s?): return Extracted(value: .store, certainty: .likely, source: SourceLocation(line: s.1, index: s.0))
        case let (o?, _?): return Extracted(value: .online, certainty: .guess, source: SourceLocation(line: o.1, index: o.0))
        default: return nil
        }
    }

    func detectCountry(lines: [TextLine], folded: [String], currency: String?) -> Extracted<String>? {
        let hints: [(String, [String])] = [
            ("CH", ["schweiz", "suisse", "svizzera", "switzerland", "che-", " ag", "gmbh ch", "mwst-nr", "chf"]),
            ("DE", ["deutschland", "germany", "ust-idnr", "ust-id", "de1", "steuernummer", " gmbh"]),
            ("AT", ["osterreich", "austria", "atu"]),
            ("FR", ["france", "siret", "tva intracom"]),
            ("IT", ["italia", "partita iva", "p.iva"]),
            ("ES", ["espana", "spain", "nif", "cif"]),
            ("PT", ["portugal", "nif:"]),
            ("NL", ["nederland", "netherlands", "btw"])
        ]
        for (code, keywords) in hints {
            for (index, f) in folded.enumerated() where Self.contains(f, any: keywords) {
                // A German "GmbH" alone is weak evidence when the currency is CHF.
                if code == "DE", currency == "CHF" { continue }
                return Extracted(value: code, certainty: .guess, source: SourceLocation(line: lines[index], index: index))
            }
        }
        if currency == "CHF" { return Extracted(value: "CH", certainty: .guess, source: nil) }
        return nil
    }

    private static let warrantyRegex = try! NSRegularExpression(pattern: #"(\d{1,2})\s*(jahre?|jahren|monate?|monaten|years?|months?|ans?|mois|anni|mesi)\s*(?:\w+\s*){0,2}(garantie|warranty|garanzia)|(garantie|warranty|garanzia)\s*:?\s*(\d{1,2})\s*(jahre?|monate?|years?|months?|ans?|mois|anni|mesi)"#, options: [.caseInsensitive])
    private static let returnRegex = try! NSRegularExpression(pattern: #"(\d{1,3})\s*(?:tage?n?|days?|jours?|giorni)\s*(?:\w+\s*){0,3}(?:ruckgabe|umtausch|return|retour|reso|ruckgaberecht)|(?:ruckgabe|umtausch|return|retour|reso)\w*\s*(?:\w+\s*){0,3}(\d{1,3})\s*(?:tage?n?|days?|jours?|giorni)"#, options: [.caseInsensitive])

    func detectWarrantyMonths(lines: [TextLine], folded: [String]) -> Extracted<Int>? {
        for (index, f) in folded.enumerated() {
            let ns = f as NSString
            guard let m = Self.warrantyRegex.firstMatch(in: f, range: NSRange(location: 0, length: ns.length)) else { continue }
            let numberRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 5)
            let unitRange = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 6)
            guard let n = Int(ns.substring(with: numberRange)) else { continue }
            let unit = ns.substring(with: unitRange)
            let isYears = unit.hasPrefix("j") || unit.hasPrefix("y") || unit.hasPrefix("an")
            let months = isYears ? n * 12 : n
            guard (1...240).contains(months) else { continue }
            return Extracted(value: months, certainty: .likely, source: SourceLocation(line: lines[index], index: index))
        }
        return nil
    }

    func detectReturnDays(lines: [TextLine], folded: [String]) -> Extracted<Int>? {
        for (index, f) in folded.enumerated() {
            let ns = f as NSString
            guard let m = Self.returnRegex.firstMatch(in: f, range: NSRange(location: 0, length: ns.length)) else { continue }
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard let days = Int(ns.substring(with: r)), (1...365).contains(days) else { continue }
            return Extracted(value: days, certainty: .likely, source: SourceLocation(line: lines[index], index: index))
        }
        return nil
    }
}
