import Foundation

/// Input for the claim message draft.
public struct ClaimContext: Sendable {
    public var productName: String
    public var brand: String?
    public var model: String?
    public var serialNumber: String?
    public var merchant: String?
    public var purchaseDate: Date
    public var price: String?
    public var orderNumber: String?
    public var defectDescription: String
    public var defectNoticedOn: Date
    public var requestedRemedy: ClaimRemedy
    public var coverage: CoverageKind?
    public var coverageEnd: Date?
    public var customerName: String?
    public var attachments: [String]

    public init(productName: String, brand: String?, model: String?, serialNumber: String?, merchant: String?, purchaseDate: Date, price: String?, orderNumber: String?, defectDescription: String, defectNoticedOn: Date, requestedRemedy: ClaimRemedy, coverage: CoverageKind?, coverageEnd: Date?, customerName: String?, attachments: [String]) {
        self.productName = productName
        self.brand = brand
        self.model = model
        self.serialNumber = serialNumber
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.price = price
        self.orderNumber = orderNumber
        self.defectDescription = defectDescription
        self.defectNoticedOn = defectNoticedOn
        self.requestedRemedy = requestedRemedy
        self.coverage = coverage
        self.coverageEnd = coverageEnd
        self.customerName = customerName
        self.attachments = attachments
    }
}

public enum ClaimRemedy: String, Codable, CaseIterable, Sendable, Identifiable {
    case repair
    case replacement
    case refund
    case priceReduction
    case undecided

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .repair: "Reparatur"
        case .replacement: "Ersatz"
        case .refund: "Rückerstattung"
        case .priceReduction: "Preisminderung"
        case .undecided: "Lösung offen lassen"
        }
    }

    var sentence: String {
        switch self {
        case .repair: "Ich bitte Sie, das Gerät kostenlos zu reparieren."
        case .replacement: "Ich bitte Sie, mir ein mangelfreies Ersatzgerät zu liefern."
        case .refund: "Ich bitte Sie, den Kaufpreis zurückzuerstatten."
        case .priceReduction: "Ich bitte Sie um eine angemessene Minderung des Kaufpreises."
        case .undecided: "Bitte teilen Sie mir mit, wie wir weiter vorgehen."
        }
    }
}

public enum ClaimTemplate {
    public static func subject(_ c: ClaimContext) -> String {
        var s = "Reklamation: \(c.productName)"
        if let serial = c.serialNumber, !serial.isEmpty { s += " (S/N \(serial))" }
        if let order = c.orderNumber, !order.isEmpty { s += " – Bestellung \(order)" }
        return s
    }

    public static func body(_ c: ClaimContext, locale: Locale = Locale(identifier: "de_CH")) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.dateStyle = .long
        df.timeStyle = .none

        var lines: [String] = []
        lines.append("Guten Tag")
        lines.append("")
        var purchase = "Am \(df.string(from: c.purchaseDate)) habe ich"
        if let merchant = c.merchant, !merchant.isEmpty { purchase += " bei \(merchant)" }
        purchase += " folgendes Produkt gekauft:"
        lines.append(purchase)
        lines.append("")
        lines.append("• Produkt: \(c.productName)")
        if let brand = c.brand, !brand.isEmpty { lines.append("• Marke: \(brand)") }
        if let model = c.model, !model.isEmpty { lines.append("• Modell: \(model)") }
        if let serial = c.serialNumber, !serial.isEmpty { lines.append("• Seriennummer: \(serial)") }
        if let price = c.price, !price.isEmpty { lines.append("• Kaufpreis: \(price)") }
        if let order = c.orderNumber, !order.isEmpty { lines.append("• Bestell-/Belegnummer: \(order)") }
        lines.append("")
        lines.append("Seit dem \(df.string(from: c.defectNoticedOn)) tritt folgender Mangel auf:")
        lines.append(c.defectDescription.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        if let coverage = c.coverage {
            var basis = "Ich mache hiermit meine Ansprüche aus der \(coverage.title)"
            if let end = c.coverageEnd { basis += " (gültig bis \(df.string(from: end)))" }
            basis += " geltend."
            lines.append(basis)
        }
        lines.append(c.requestedRemedy.sentence)
        lines.append("")
        if !c.attachments.isEmpty {
            lines.append("Im Anhang finden Sie:")
            for a in c.attachments { lines.append("• \(a)") }
            lines.append("")
        }
        lines.append("Vielen Dank für Ihre Rückmeldung.")
        lines.append("")
        lines.append("Freundliche Grüsse")
        if let name = c.customerName, !name.isEmpty { lines.append(name) }
        return lines.joined(separator: "\n")
    }
}
