import Foundation

public enum ClaimRemedy: String, Codable, CaseIterable, Sendable, Identifiable {
    case repair
    case replacement
    case refund
    case open

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .repair: return "Reparatur"
        case .replacement: return "Ersatz"
        case .refund: return "Rückerstattung"
        case .open: return "Offen – Vorschlag des Händlers"
        }
    }
}

public struct ClaimContext: Equatable, Sendable {
    public var productName: String
    public var brand: String
    public var model: String
    public var serialNumber: String
    public var merchant: String
    public var purchaseDate: Date?
    public var orderNumber: String
    public var issue: String
    public var remedy: ClaimRemedy
    /// Die Grundlage, auf die sich die Reklamation stützt (falls noch eine läuft).
    public var coverage: CoverageKind?
    public var senderName: String
    public var attachmentCount: Int

    public init(
        productName: String, brand: String = "", model: String = "", serialNumber: String = "",
        merchant: String = "", purchaseDate: Date? = nil, orderNumber: String = "", issue: String,
        remedy: ClaimRemedy = .open, coverage: CoverageKind? = nil, senderName: String = "", attachmentCount: Int = 0
    ) {
        self.productName = productName
        self.brand = brand
        self.model = model
        self.serialNumber = serialNumber
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.orderNumber = orderNumber
        self.issue = issue
        self.remedy = remedy
        self.coverage = coverage
        self.senderName = senderName
        self.attachmentCount = attachmentCount
    }
}

/// Erstellt einen sachlichen Nachrichtenentwurf für eine Reklamation.
public enum ClaimComposer {
    public static func subject(_ context: ClaimContext) -> String {
        var subject = "Reklamation: \(context.productName)"
        if !context.orderNumber.isEmpty { subject += " (Bestellung \(context.orderNumber))" }
        return subject
    }

    public static func body(_ context: ClaimContext, dateFormatter: DateFormatter = defaultDateFormatter) -> String {
        var lines: [String] = []
        lines.append("Guten Tag")
        lines.append("")

        var intro = "ich melde einen Mangel an folgendem Produkt"
        if let date = context.purchaseDate {
            intro += ", das ich am \(dateFormatter.string(from: date))"
            intro += context.merchant.isEmpty ? " gekauft habe" : " bei \(context.merchant) gekauft habe"
        } else if !context.merchant.isEmpty {
            intro += ", das ich bei \(context.merchant) gekauft habe"
        }
        lines.append(intro + ":")
        lines.append("")

        lines.append("Produkt: \(context.productName)")
        let brandModel = [context.brand, context.model].filter { !$0.isEmpty }.joined(separator: " ")
        if !brandModel.isEmpty { lines.append("Marke/Modell: \(brandModel)") }
        if !context.serialNumber.isEmpty { lines.append("Seriennummer: \(context.serialNumber)") }
        if !context.orderNumber.isEmpty { lines.append("Bestell-/Rechnungsnummer: \(context.orderNumber)") }
        lines.append("")

        lines.append("Beschreibung des Mangels:")
        let issue = context.issue.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(issue.isEmpty ? "[Bitte Mangel beschreiben]" : issue)
        lines.append("")

        switch context.coverage {
        case .legal?:
            lines.append("Ich mache meine gesetzlichen Mängelrechte geltend.")
        case .manufacturer?:
            lines.append("Ich beziehe mich auf die Herstellergarantie.")
        case .extended?:
            lines.append("Ich beziehe mich auf die abgeschlossene Zusatzgarantie.")
        case .returnWindow?:
            lines.append("Der Kauf liegt innerhalb der Rückgabefrist.")
        case nil:
            break
        }

        switch context.remedy {
        case .repair: lines.append("Ich bitte um eine kostenlose Reparatur.")
        case .replacement: lines.append("Ich bitte um ein Ersatzgerät.")
        case .refund: lines.append("Ich bitte um die Rückerstattung des Kaufpreises.")
        case .open: lines.append("Bitte teilen Sie mir mit, wie Sie den Mangel beheben.")
        }
        lines.append("Bitte informieren Sie mich über das weitere Vorgehen und darüber, wohin ich das Produkt senden oder bringen soll.")
        lines.append("")

        if context.attachmentCount > 0 {
            lines.append("Im Anhang finden Sie das Dossier mit Kaufbeleg und Fotos.")
            lines.append("")
        }
        lines.append("Freundliche Grüsse")
        if !context.senderName.isEmpty { lines.append(context.senderName) }
        return lines.joined(separator: "\n")
    }

    public static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
}

/// Kleine CSV-Hilfe für den Datenexport (Semikolon-getrennt, wie von Excel im deutschsprachigen Raum erwartet).
public enum CSVBuilder {
    public static func field(_ value: String) -> String {
        let needsQuotes = value.contains(";") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ values: [String]) -> String {
        values.map(field).joined(separator: ";")
    }

    public static func document(header: [String], rows: [[String]]) -> String {
        // BOM, damit Excel Umlaute korrekt als UTF-8 erkennt.
        "\u{FEFF}" + ([row(header)] + rows.map(row)).joined(separator: "\r\n") + "\r\n"
    }
}
