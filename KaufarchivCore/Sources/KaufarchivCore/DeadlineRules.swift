import Foundation

public enum CoverageKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Rückgabe- bzw. Widerrufsfrist
    case returnWindow
    /// Gesetzliche Mängelrechte (Gewährleistung)
    case legal
    /// Freiwillige Herstellergarantie
    case manufacturer
    /// Kostenpflichtige Zusatzgarantie / Garantieverlängerung
    case extended

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .returnWindow: return "Rückgabe"
        case .legal: return "Gesetzliche Mängelrechte"
        case .manufacturer: return "Herstellergarantie"
        case .extended: return "Zusatzgarantie"
        }
    }

    public var shortLabel: String {
        switch self {
        case .returnWindow: return "Rückgabe"
        case .legal: return "Mängelrechte"
        case .manufacturer: return "Hersteller"
        case .extended: return "Zusatz"
        }
    }
}

public enum PurchaseChannel: String, Codable, CaseIterable, Sendable, Identifiable {
    case store
    case online

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .store: return "Im Geschäft"
        case .online: return "Online / Fernabsatz"
        }
    }
}

public struct CountryRule: Equatable, Sendable, Identifiable {
    public var code: String
    public var name: String
    /// Dauer der gesetzlichen Mängelrechte für neue bewegliche Sachen, in Monaten.
    public var legalMonths: Int
    /// Gesetzliche Widerrufsfrist bei Fernabsatz in Tagen; `nil`, wenn es kein allgemeines Recht gibt.
    public var withdrawalDays: Int?
    public var legalNote: String
    public var withdrawalNote: String

    public var id: String { code }
}

public struct CoverageSuggestion: Equatable, Sendable {
    public var kind: CoverageKind
    public var endDate: Date
    public var months: Int?
    public var days: Int?
    /// Nachvollziehbare Begründung, die dem Vorschlag in der App beigestellt wird.
    public var basis: String
}

/// Länderspezifische Ausgangswerte. Alle Ergebnisse sind Vorschläge, die bestätigt werden müssen –
/// massgebend sind Vertrag, AGB und die Rechtslage im Einzelfall.
public enum DeadlineRules {
    public static let countries: [CountryRule] = [
        CountryRule(
            code: "CH", name: "Schweiz", legalMonths: 24, withdrawalDays: nil,
            legalNote: "Gesetzlich zwei Jahre für neue Sachen (OR Art. 210). Händler dürfen die Gewährleistung in ihren AGB einschränken oder durch eine Garantie ersetzen – bitte AGB prüfen.",
            withdrawalNote: "In der Schweiz gibt es kein allgemeines gesetzliches Widerrufsrecht für Onlinekäufe. Eine Rückgabe ist nur möglich, wenn der Händler sie freiwillig anbietet."
        ),
        CountryRule(
            code: "LI", name: "Liechtenstein", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre Gewährleistung für bewegliche Sachen.",
            withdrawalNote: "14 Tage Rücktrittsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "DE", name: "Deutschland", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre Gewährleistung ab Übergabe (BGB § 438). Bei gebrauchten Sachen kann sie auf ein Jahr verkürzt sein.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "AT", name: "Österreich", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre Gewährleistung für bewegliche Sachen.",
            withdrawalNote: "14 Tage Rücktrittsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "FR", name: "Frankreich", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre «garantie légale de conformité».",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "IT", name: "Italien", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre gesetzliche Gewährleistung.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "ES", name: "Spanien", legalMonths: 36, withdrawalDays: 14,
            legalNote: "Drei Jahre gesetzliche Gewährleistung für seit 2022 gekaufte neue Waren.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "PT", name: "Portugal", legalMonths: 36, withdrawalDays: 14,
            legalNote: "Grundsätzlich drei Jahre gesetzliche Gewährleistung für bewegliche Güter.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "NL", name: "Niederlande", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Mindestens zwei Jahre; darüber hinaus richtet sich der Anspruch nach der zu erwartenden Lebensdauer.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "BE", name: "Belgien", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre gesetzliche Gewährleistung.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "LU", name: "Luxemburg", legalMonths: 24, withdrawalDays: 14,
            legalNote: "Zwei Jahre gesetzliche Gewährleistung.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "SE", name: "Schweden", legalMonths: 36, withdrawalDays: 14,
            legalNote: "Drei Jahre Reklamationsrecht.",
            withdrawalNote: "14 Tage Widerrufsrecht bei Fernabsatz, gerechnet ab Erhalt der Ware."
        ),
        CountryRule(
            code: "XX", name: "Anderes Land", legalMonths: 24, withdrawalDays: nil,
            legalNote: "Für dieses Land ist keine Regel hinterlegt. Zwei Jahre sind nur ein Platzhalter – bitte die tatsächliche Frist eintragen.",
            withdrawalNote: "Für dieses Land ist keine Widerrufsregel hinterlegt."
        )
    ]

    public static func rule(for code: String) -> CountryRule {
        countries.first { $0.code == code } ?? countries[countries.count - 1]
    }

    /// Vorschläge für ein Kaufdatum. Rückgabe im Geschäft wird nie automatisch vorgeschlagen,
    /// weil sie freiwillig ist und vom Händler abhängt.
    public static func suggestions(
        countryCode: String,
        channel: PurchaseChannel,
        purchaseDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [CoverageSuggestion] {
        let country = DeadlineRules.rule(for: countryCode)
        var result: [CoverageSuggestion] = []

        if channel == .online, let days = country.withdrawalDays {
            result.append(CoverageSuggestion(
                kind: .returnWindow,
                endDate: endDate(from: purchaseDate, days: days, calendar: calendar),
                months: nil,
                days: days,
                basis: country.withdrawalNote + " Hier ab Kaufdatum gerechnet – bei späterer Lieferung verlängert sich die Frist entsprechend."
            ))
        }
        result.append(CoverageSuggestion(
            kind: .legal,
            endDate: endDate(from: purchaseDate, months: country.legalMonths, calendar: calendar),
            months: country.legalMonths,
            days: nil,
            basis: country.legalNote
        ))
        return result
    }

    public static func endDate(from start: Date, months: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.date(byAdding: .month, value: months, to: start) ?? start
    }

    public static func endDate(from start: Date, days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.date(byAdding: .day, value: days, to: start) ?? start
    }
}
