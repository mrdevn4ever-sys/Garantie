import Foundation

public enum Confidence: Int, Codable, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Ein erkannter Wert mit Sicherheit und Fundstelle (Index in den Belegzeilen).
public struct Detected<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var confidence: Confidence
    public var lineIndex: Int?

    public init(value: Value, confidence: Confidence, lineIndex: Int?) {
        self.value = value
        self.confidence = confidence
        self.lineIndex = lineIndex
    }
}

public struct DraftItem: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var quantity: Int
    public var unitPrice: Decimal?
    public var totalPrice: Decimal?
    public var lineIndex: Int?
    public var confidence: Confidence
}

public struct ReceiptDraft: Equatable, Sendable {
    public var merchant: Detected<String>?
    public var purchaseDate: Detected<Date>?
    public var total: Detected<Decimal>?
    public var currency: String
    public var orderNumber: Detected<String>?
    public var items: [DraftItem] = []
    public var serialNumbers: [Detected<String>] = []
    /// Bar gegebener Betrag – ausdrücklich kein Kaufpreis.
    public var cashGiven: Decimal?
    /// Rückgeld – ausdrücklich kein Kaufpreis.
    public var change: Decimal?
    public var isOnlineOrder = false
}

public enum ReceiptParser {

    // MARK: Schlüsselwörter (bereits ohne Umlaute/Akzente, kleingeschrieben)

    private static let strongTotalTokens: Set<String> = [
        "gesamtbetrag", "gesamtsumme", "rechnungsbetrag", "endbetrag", "zahlbetrag", "totalbetrag",
        "gesamttotal", "rechnungstotal", "endsumme", "bruttobetrag"
    ]
    private static let strongTotalPhrases = [
        "zu zahlen", "zu bezahlen", "grand total", "amount due", "total ttc", "montant total", "totale da pagare", "total a payer"
    ]
    private static let mediumTotalTokens: Set<String> = ["total", "summe", "gesamt", "totale", "sum"]
    private static let weakTotalTokens: Set<String> = ["betrag", "montant", "importo", "amount"]

    private static let subtotalTokens: Set<String> = [
        "zwischensumme", "zwischentotal", "subtotal", "netto", "nettobetrag", "warenwert", "exkl", "excl", "zzgl", "ht", "nettosumme"
    ]
    private static let subtotalPhrases = ["sous-total", "sous total", "sub total", "sub-total", "total ht"]

    private static let taxTokens: Set<String> = [
        "mwst", "mehrwertsteuer", "ust", "umsatzsteuer", "vat", "tva", "iva", "steuer", "tax", "inkl", "incl", "mwsta", "mwstb"
    ]
    private static let taxInclusiveTokens: Set<String> = ["inkl", "incl", "ttc", "inklusive", "brutto"]

    private static let cashTokens: Set<String> = ["bar", "gegeben", "bargeld", "cash", "erhalten", "especes", "contanti"]
    private static let paymentTokens: Set<String> = [
        "bar", "gegeben", "bargeld", "cash", "erhalten", "especes", "contanti",
        "kartenzahlung", "debitkarte", "maestro", "visa", "mastercard", "twint", "debit", "kredit", "kreditkarte",
        "girocard", "paypal", "bezahlt", "zahlung", "anzahlung", "gutschein", "geschenkkarte", "postfinance",
        "amex", "lastschrift", "vorauskasse", "paid", "payment", "ec"
    ]
    private static let changeTokens: Set<String> = [
        "ruckgeld", "rueckgeld", "zuruck", "zurueck", "wechselgeld", "change", "rendu", "resto"
    ]
    private static let discountTokens: Set<String> = [
        "rabatt", "nachlass", "discount", "gutschrift", "coupon", "remise", "sconto", "ersparnis", "preisvorteil", "skonto"
    ]
    private static let shippingTokens: Set<String> = [
        "versand", "versandkosten", "lieferung", "lieferkosten", "porto", "shipping", "livraison", "spedizione", "fracht"
    ]
    private static let noiseTokens: Set<String> = [
        "tel", "telefon", "fax", "www", "http", "https", "uid", "che", "iban", "bic", "steuernummer", "kasse",
        "filiale", "kundennummer", "terminal", "trx", "uhrzeit", "danke", "offnungszeiten", "rundung",
        "punkte", "cumulus", "supercard", "bediener", "kassierer", "mitarbeiter", "seite", "page", "konto"
    ]
    private static let noisePhrases = ["vielen dank", "mwst-nr", "ust-id", "@", "www.", "http"]

    private static let dateKeywordTokens: Set<String> = [
        "datum", "date", "rechnungsdatum", "kaufdatum", "bestelldatum", "belegdatum", "verkaufsdatum", "bestellt", "data"
    ]
    private static let dateExcludeTokens: Set<String> = [
        "fallig", "faellig", "falligkeit", "zahlbar", "lieferdatum", "liefertermin", "gultig", "gueltig", "due",
        "geburtsdatum", "lieferung", "zustellung", "ruckgabe", "umtausch"
    ]
    private static let documentTitleTokens: Set<String> = [
        "rechnung", "quittung", "beleg", "kassenbon", "invoice", "receipt", "facture", "bestellbestatigung",
        "lieferschein", "kaufbeleg", "kassenzettel", "ricevuta", "fattura", "bon"
    ]
    private static let onlineTokens: Set<String> = [
        "bestellung", "bestellnummer", "lieferadresse", "versand", "versandkosten", "lieferschein", "shipping",
        "onlineshop", "bestellbestatigung", "sendungsnummer", "tracking", "versandart"
    ]

    private static let knownMerchants: [(key: String, name: String)] = [
        ("digitec", "Digitec"), ("galaxus", "Galaxus"), ("media markt", "MediaMarkt"), ("mediamarkt", "MediaMarkt"),
        ("interdiscount", "Interdiscount"), ("melectronics", "melectronics"), ("microspot", "microspot"),
        ("brack", "BRACK.CH"), ("fust", "Fust"), ("migros", "Migros"), ("coop", "Coop"), ("manor", "Manor"),
        ("ikea", "IKEA"), ("amazon", "Amazon"), ("apple", "Apple"), ("saturn", "Saturn"), ("conrad", "Conrad"),
        ("zalando", "Zalando"), ("decathlon", "Decathlon"), ("hornbach", "Hornbach"), ("bauhaus", "Bauhaus"),
        ("jumbo", "Jumbo"), ("landi", "Landi"), ("lidl", "Lidl"), ("aldi", "Aldi"), ("rossmann", "Rossmann"),
        ("fnac", "Fnac"), ("darty", "Darty"), ("euronics", "Euronics"), ("otto", "OTTO"), ("obi", "OBI"),
        ("cyberport", "Cyberport"), ("alternate", "Alternate"), ("notebooksbilliger", "notebooksbilliger.de"),
        ("ochsner", "Ochsner Sport"), ("globus", "Globus"), ("pfister", "Pfister"), ("xxxlutz", "XXXLutz")
    ]

    private static let orderPattern = TextTools.regex(
        #"(?:bestell(?:ung|nummer)?|auftrags?(?:nummer)?|rechnungs?(?:nummer)?|order|invoice|beleg|commande|facture)[\s\-]*(?:nr|no|number|id|num[eé]ro)?[\s.:#°]*([A-Z0-9][A-Z0-9\-/]{3,})"#,
        options: [.caseInsensitive]
    )
    private static let serialPattern = TextTools.regex(
        #"(?:\bs/?n\b|serien[\s\-]?(?:nummer|nr)|serial(?:\s?(?:no|number))?|imei)[\s.:#]*([A-Z0-9][A-Z0-9\-]{5,})"#,
        options: [.caseInsensitive]
    )
    private static let quantityInlinePattern = TextTools.regex(#"(?:^|\s)(\d{1,3})\s*[xX×](?=\s|$)"#)
    private static let quantityLeadingPattern = TextTools.regex(#"^\s*(\d{1,3})\s+(?:Stk|St|Stück|Stueck|pcs|pc)\.?\s"#, options: [.caseInsensitive])
    private static let positionNumberPattern = TextTools.regex(#"^\s*(\d{1,2})\s+(?=\p{L})"#)
    private static let articleNumberPattern = TextTools.regex(#"\b\d{5,}\b"#)
    private static let currencyWordPattern = TextTools.regex(#"\b(?:CHF|EUR|USD|GBP|SFr|Fr)\b\.?|[€$£]"#, options: [.caseInsensitive])
    private static let trailingTaxCodePattern = TextTools.regex(#"\s[AB]$"#)

    // MARK: Zeilenanalyse

    enum Role { case total, subtotal, tax, payment, change, discount, shipping, noise, other }

    struct LineInfo {
        let index: Int
        let line: TextLine
        let folded: String
        let tokens: Set<String>
        let amounts: [AmountMatch]
        let dates: [DateMatch]
        var role: Role = .other
        var totalScore = 0

        var letters: Int { TextTools.letterCount(line.text) }
    }

    static func classify(_ info: inout LineInfo) {
        let tokens = info.tokens
        let folded = info.folded
        func hasPhrase(_ phrases: [String]) -> Bool { phrases.contains { folded.contains($0) } }

        if !tokens.isDisjoint(with: subtotalTokens) || hasPhrase(subtotalPhrases) {
            info.role = .subtotal
            return
        }
        let strong = !tokens.isDisjoint(with: strongTotalTokens) || hasPhrase(strongTotalPhrases)
        let medium = !tokens.isDisjoint(with: mediumTotalTokens)
        let hasTax = !tokens.isDisjoint(with: taxTokens)
        if strong {
            info.role = .total
            info.totalScore = 3
            return
        }
        if medium {
            if !tokens.isDisjoint(with: discountTokens) {
                info.role = .discount
                return
            }
            if hasTax && tokens.isDisjoint(with: taxInclusiveTokens) {
                info.role = .tax
                return
            }
            info.role = .total
            info.totalScore = 2
            return
        }
        if !tokens.isDisjoint(with: changeTokens) { info.role = .change; return }
        if !tokens.isDisjoint(with: paymentTokens) { info.role = .payment; return }
        if hasTax { info.role = .tax; return }
        if !tokens.isDisjoint(with: weakTotalTokens) {
            info.role = .total
            info.totalScore = 1
            return
        }
        if !tokens.isDisjoint(with: discountTokens) { info.role = .discount; return }
        if !tokens.isDisjoint(with: shippingTokens) { info.role = .shipping; return }
        if !tokens.isDisjoint(with: noiseTokens) || hasPhrase(noisePhrases) { info.role = .noise; return }
    }

    // MARK: Hauptfunktion

    public static func parse(
        lines: [TextLine],
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        defaultCurrency: String = "CHF"
    ) -> ReceiptDraft {
        var infos: [LineInfo] = lines.enumerated().map { index, line in
            let folded = TextTools.folded(line.text)
            var info = LineInfo(
                index: index,
                line: line,
                folded: folded,
                tokens: Set(TextTools.tokens(folded)),
                amounts: AmountParser.amounts(in: line.text),
                dates: DateParser.dates(in: line.text, calendar: calendar)
            )
            classify(&info)
            return info
        }
        // Zeilen mit Datum sind keine Preiszeilen.
        for index in infos.indices where infos[index].role == .other && !infos[index].dates.isEmpty {
            infos[index].role = .noise
        }

        var draft = ReceiptDraft(currency: detectCurrency(infos) ?? defaultCurrency)
        let merchant = detectMerchant(infos)
        draft.merchant = merchant
        draft.purchaseDate = detectDate(infos, now: now, calendar: calendar)
        draft.orderNumber = detectLabeledNumber(infos, pattern: orderPattern).first
        draft.serialNumbers = detectLabeledNumber(infos, pattern: serialPattern)
        draft.isOnlineOrder = infos.contains { !$0.tokens.isDisjoint(with: onlineTokens) }

        // Zahlungsangaben getrennt erfassen, damit sie nie als Preis übernommen werden.
        for info in infos {
            if info.role == .payment, !info.tokens.isDisjoint(with: cashTokens), draft.cashGiven == nil,
               let amount = info.amounts.last?.value, amount > 0 {
                draft.cashGiven = amount
            }
            if info.role == .change, draft.change == nil, let amount = info.amounts.last?.value {
                draft.change = abs(amount)
            }
        }

        // Gesamtbetrag: beste Zeile mit Total-Schlüsselwort.
        var totalCandidate: (score: Int, amount: Decimal, lineIndex: Int)?
        for info in infos where info.role == .total {
            var amount = info.amounts.last?.value
            var lineIndex = info.index
            if amount == nil, info.index + 1 < infos.count {
                let next = infos[info.index + 1]
                if next.letters <= 4, let nextAmount = next.amounts.last?.value {
                    amount = nextAmount
                    lineIndex = next.index
                }
            }
            guard let value = amount, value > 0 else { continue }
            if let current = totalCandidate {
                if info.totalScore > current.score || (info.totalScore == current.score && value > current.amount) {
                    totalCandidate = (info.totalScore, value, lineIndex)
                }
            } else {
                totalCandidate = (info.totalScore, value, lineIndex)
            }
        }

        // Positionen stehen vor der ersten Summen- oder Zahlungszeile.
        let summaryRoles: [Role] = [.total, .subtotal]
        var itemsEnd = infos.first { summaryRoles.contains($0.role) && !$0.amounts.isEmpty }?.index
        if itemsEnd == nil {
            itemsEnd = infos.first { ($0.role == .payment || $0.role == .change) && !$0.amounts.isEmpty }?.index
        }
        draft.items = detectItems(infos, end: itemsEnd ?? infos.count, merchantLine: merchant?.lineIndex)

        let itemsSum = draft.items.reduce(Decimal(0)) { $0 + ($1.totalPrice ?? 0) }
        let tolerance = Decimal(string: "0.06") ?? 0

        if let candidate = totalCandidate {
            var confidence: Confidence = candidate.score >= 2 ? .medium : .low
            if candidate.score >= 2 {
                let matchesItems = draft.items.isEmpty || abs(itemsSum - candidate.amount) <= tolerance
                var matchesCash = false
                if let given = draft.cashGiven, let change = draft.change {
                    matchesCash = abs(given - change - candidate.amount) <= tolerance
                }
                if candidate.score == 3 || matchesItems || matchesCash { confidence = .high }
            }
            draft.total = Detected(value: candidate.amount, confidence: confidence, lineIndex: candidate.lineIndex)
        } else if !draft.items.isEmpty {
            // Kein Total gefunden: Summe der Positionen als ausdrücklicher Vorschlag.
            draft.total = Detected(value: itemsSum, confidence: .low, lineIndex: nil)
        } else {
            // Letzter Ausweg: grösster Betrag, der nachweislich keine Zahlungs-, Rückgeld- oder Steuerzeile ist.
            let excluded: [Role] = [.payment, .change, .tax, .discount]
            var best: (Decimal, Int)?
            for info in infos where !excluded.contains(info.role) {
                for amount in info.amounts where amount.value > (best?.0 ?? 0) {
                    best = (amount.value, info.index)
                }
            }
            if let best {
                draft.total = Detected(value: best.0, confidence: .low, lineIndex: best.1)
            }
        }
        return draft
    }

    // MARK: Einzelne Erkennungen

    static func detectCurrency(_ infos: [LineInfo]) -> String? {
        var counts: [String: Int] = [:]
        for info in infos {
            let text = info.line.text
            if info.tokens.contains("chf") || info.tokens.contains("sfr") || info.folded.contains("fr.") { counts["CHF", default: 0] += 1 }
            if info.tokens.contains("eur") || info.tokens.contains("euro") || text.contains("€") { counts["EUR", default: 0] += 1 }
            if info.tokens.contains("usd") || text.contains("$") { counts["USD", default: 0] += 1 }
            if info.tokens.contains("gbp") || text.contains("£") { counts["GBP", default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func detectMerchant(_ infos: [LineInfo]) -> Detected<String>? {
        // 1. Bekannte Händler – zuerst im Kopf des Belegs, danach überall.
        // Nur Zeilen ohne Betrag: «Apple iPad 499.00» ist ein Produkt, kein Händler.
        let head = Array(infos.prefix(8)).filter { $0.amounts.isEmpty }
        let footer = infos.filter { $0.amounts.isEmpty && $0.role == .noise }
        for (scope, confidence) in [(head, Confidence.high), (footer, Confidence.medium)] {
            for info in scope {
                for merchant in knownMerchants {
                    let hit = merchant.key.contains(" ") || merchant.key.count > 5
                        ? info.folded.contains(merchant.key)
                        : info.tokens.contains(merchant.key)
                    if hit { return Detected(value: merchant.name, confidence: confidence, lineIndex: info.index) }
                }
            }
        }
        // 2. Auffälligste Textzeile im Belegkopf.
        let candidates = infos.prefix(6).filter { info in
            info.line.page == 0
                && info.amounts.isEmpty
                && info.dates.isEmpty
                && info.letters >= 3
                && Double(info.letters) / Double(max(info.line.text.count, 1)) > 0.5
                && info.tokens.isDisjoint(with: documentTitleTokens)
                && (info.role == .other)
        }
        guard let best = candidates.max(by: { $0.line.box.height < $1.line.box.height }) else { return nil }
        let heights = infos.map { $0.line.box.height }.sorted()
        let median = heights.isEmpty ? 0 : heights[heights.count / 2]
        let prominent = median > 0 && best.line.box.height >= median * 1.25
        let name = best.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Detected(value: name, confidence: prominent ? .medium : .low, lineIndex: best.index)
    }

    static func detectDate(_ infos: [LineInfo], now: Date, calendar: Calendar) -> Detected<Date>? {
        let latest = now.addingTimeInterval(86_400 * 2)
        let earliest = calendar.date(byAdding: .year, value: -15, to: now) ?? .distantPast
        var plain: [(Date, Int)] = []
        for info in infos {
            let valid = info.dates.filter { $0.date <= latest && $0.date >= earliest }
            guard let first = valid.first else { continue }
            if !info.tokens.isDisjoint(with: dateExcludeTokens) { continue }
            if !info.tokens.isDisjoint(with: dateKeywordTokens) {
                return Detected(value: first.date, confidence: .high, lineIndex: info.index)
            }
            plain.append((first.date, info.index))
        }
        guard let first = plain.first else { return nil }
        let distinct = Set(plain.map { $0.0 })
        return Detected(value: first.0, confidence: distinct.count == 1 ? .medium : .low, lineIndex: first.1)
    }

    static func detectLabeledNumber(_ infos: [LineInfo], pattern: NSRegularExpression) -> [Detected<String>] {
        var result: [Detected<String>] = []
        for info in infos {
            let text = info.line.text
            for match in TextTools.matches(pattern, in: text) {
                guard let value = TextTools.group(1, of: match, in: text) else { continue }
                // Eine Nummer muss mindestens eine Ziffer enthalten («Bestellung vom» ist keine Nummer).
                guard value.contains(where: { $0.isNumber }) else { continue }
                if result.contains(where: { $0.value == value }) { continue }
                result.append(Detected(value: value, confidence: .medium, lineIndex: info.index))
            }
        }
        return result
    }

    static func detectItems(_ infos: [LineInfo], end: Int, merchantLine: Int?) -> [DraftItem] {
        var items: [DraftItem] = []
        var usedNameLines: Set<Int> = []
        var lastItemLine: Int?

        for index in 0..<min(end, infos.count) {
            let info = infos[index]

            // Rabatt direkt nach einer Position verringert deren Preis.
            if info.role == .discount, let amount = info.amounts.last?.value, let last = lastItemLine, last == index - 1,
               !items.isEmpty {
                let reduction = abs(amount)
                if let current = items[items.count - 1].totalPrice, current > reduction {
                    items[items.count - 1].totalPrice = current - reduction
                    let quantity = Decimal(max(items[items.count - 1].quantity, 1))
                    items[items.count - 1].unitPrice = (current - reduction) / quantity
                }
                lastItemLine = index
                continue
            }

            guard info.role == .other, !info.amounts.isEmpty, index != merchantLine else { continue }
            let positive = info.amounts.filter { $0.value > 0 }
            guard let totalPrice = positive.last?.value, info.amounts.last.map({ $0.value > 0 }) == true else { continue }

            var (name, quantity) = cleanName(info.line.text, amounts: info.amounts)
            var confidence: Confidence = .high
            var nameLine = index

            if TextTools.letterCount(name) < 3 {
                // Zweizeilige Position: Bezeichnung steht in der Zeile darüber.
                let previous = index - 1
                guard previous >= 0, previous != merchantLine, !usedNameLines.contains(previous),
                      infos[previous].role == .other, infos[previous].amounts.isEmpty,
                      infos[previous].letters >= 3 else { continue }
                let cleaned = cleanName(infos[previous].line.text, amounts: [])
                name = cleaned.name
                if quantity == 1 { quantity = cleaned.quantity }
                nameLine = previous
                confidence = .medium
            }
            guard TextTools.letterCount(name) >= 3 else { continue }
            usedNameLines.insert(nameLine)

            var unitPrice = totalPrice
            if quantity > 1 {
                if positive.count >= 2, let first = positive.first?.value, first < totalPrice {
                    unitPrice = first
                } else {
                    unitPrice = totalPrice / Decimal(quantity)
                }
            }
            if info.line.confidence < 0.5 { confidence = .low }

            items.append(DraftItem(
                name: name,
                quantity: quantity,
                unitPrice: unitPrice,
                totalPrice: totalPrice,
                lineIndex: nameLine,
                confidence: confidence
            ))
            lastItemLine = index
        }
        return items
    }

    /// Entfernt Beträge, Währungen, Mengenangaben und Artikelnummern aus einer Positionszeile.
    static func cleanName(_ text: String, amounts: [AmountMatch]) -> (name: String, quantity: Int) {
        let mutable = NSMutableString(string: text)
        for amount in amounts.sorted(by: { $0.location > $1.location }) {
            var range = NSRange(location: amount.location, length: amount.length)
            // Vor- oder nachgestelltes Minuszeichen mit entfernen.
            if range.location + range.length < mutable.length,
               mutable.substring(with: NSRange(location: range.location + range.length, length: 1)) == "-" {
                range.length += 1
            }
            mutable.replaceCharacters(in: range, with: " ")
        }
        var name = mutable as String
        var quantity = 1

        func strip(_ regex: NSRegularExpression, captureQuantity: Bool) {
            let matches = TextTools.matches(regex, in: name)
            if captureQuantity, let first = matches.first,
               let value = TextTools.group(1, of: first, in: name).flatMap({ Int($0) }), value > 0 {
                quantity = value
            }
            name = regex.stringByReplacingMatches(
                in: name, options: [], range: NSRange(name.startIndex..<name.endIndex, in: name), withTemplate: " "
            )
        }

        strip(quantityLeadingPattern, captureQuantity: true)
        if quantity == 1 { strip(quantityInlinePattern, captureQuantity: true) }
        if quantity == 1 {
            // «2 Kabel 9.95 19.90»: führende Zahl ist nur dann eine Menge, wenn Einzel- und Gesamtpreis dazu passen.
            let positive = amounts.filter { $0.value > 0 }.sorted { $0.location < $1.location }
            if let match = TextTools.matches(positionNumberPattern, in: name).first,
               let value = TextTools.group(1, of: match, in: name).flatMap({ Int($0) }), value > 1,
               positive.count >= 2, let first = positive.first?.value, let last = positive.last?.value,
               first * Decimal(value) == last {
                quantity = value
            }
            strip(positionNumberPattern, captureQuantity: false)
        }
        strip(currencyWordPattern, captureQuantity: false)
        strip(articleNumberPattern, captureQuantity: false)

        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " *:;-–—.,|#/\\"))
        strip(trailingTaxCodePattern, captureQuantity: false)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " *:;-–—.,|#/\\"))
        return (name, quantity)
    }
}
