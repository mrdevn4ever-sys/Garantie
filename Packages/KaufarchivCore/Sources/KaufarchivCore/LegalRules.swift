import Foundation

/// Consumer-law defaults per country. These are starting values the user confirms or changes,
/// never legal advice. Statutory rights (Gewährleistung) are kept separate from manufacturer
/// guarantees, extended warranties and voluntary retailer return policies.
public struct CountryRules: Codable, Hashable, Sendable, Identifiable {
    public var id: String { code }
    public var code: String
    public var name: String
    /// Statutory liability for defects of new movable goods, in months. `nil` = no fixed period.
    public var statutoryMonths: Int?
    /// Period in which a defect is presumed to have existed at delivery (burden of proof on seller).
    public var presumptionMonths: Int?
    /// Statutory right of withdrawal for distance/online purchases, in days. `nil` = no general right.
    public var onlineWithdrawalDays: Int?
    /// Plain-language notes the UI shows next to the default values.
    public var notes: [String]

    public init(code: String, name: String, statutoryMonths: Int?, presumptionMonths: Int?, onlineWithdrawalDays: Int?, notes: [String]) {
        self.code = code
        self.name = name
        self.statutoryMonths = statutoryMonths
        self.presumptionMonths = presumptionMonths
        self.onlineWithdrawalDays = onlineWithdrawalDays
        self.notes = notes
    }
}

public enum LegalRules {
    /// Date the rule table was last reviewed. Shown in the app so users know how current it is.
    public static let reviewedAt = "2026-11"

    public static let disclaimer = "Die Angaben sind Richtwerte zur Orientierung und keine Rechtsberatung. Massgebend sind Vertrag, AGB des Händlers, Garantiebedingungen des Herstellers und das anwendbare Recht."

    public static let all: [CountryRules] = [
        CountryRules(code: "CH", name: "Schweiz", statutoryMonths: 24, presumptionMonths: nil, onlineWithdrawalDays: nil, notes: [
            "Die gesetzliche Gewährleistung beträgt für neue Konsumgüter grundsätzlich 2 Jahre (Art. 210 OR).",
            "Händler dürfen die Gewährleistung in ihren AGB einschränken oder durch eine eigene Garantie ersetzen. Prüfe die Bedingungen.",
            "Für Internetkäufe gibt es in der Schweiz kein allgemeines gesetzliches Widerrufsrecht. Ein Rückgaberecht besteht nur, wenn der Händler es anbietet.",
            "Mängel müssen nach der Entdeckung sofort gerügt werden."
        ]),
        CountryRules(code: "DE", name: "Deutschland", statutoryMonths: 24, presumptionMonths: 12, onlineWithdrawalDays: 14, notes: [
            "Gesetzliche Gewährleistung 2 Jahre ab Übergabe.",
            "Im ersten Jahr wird vermutet, dass der Mangel schon bei Übergabe bestand.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage ab Erhalt der Ware."
        ]),
        CountryRules(code: "AT", name: "Österreich", statutoryMonths: 24, presumptionMonths: 12, onlineWithdrawalDays: 14, notes: [
            "Gesetzliche Gewährleistung 2 Jahre ab Übergabe, danach 3 Monate zur gerichtlichen Geltendmachung.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage ab Erhalt der Ware."
        ]),
        CountryRules(code: "FR", name: "Frankreich", statutoryMonths: 24, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Garantie légale de conformité: 2 Jahre für neue Waren.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "IT", name: "Italien", statutoryMonths: 24, presumptionMonths: 12, onlineWithdrawalDays: 14, notes: [
            "Garanzia legale: 2 Jahre ab Lieferung.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "ES", name: "Spanien", statutoryMonths: 36, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Seit 2022 gilt für neue Waren grundsätzlich eine gesetzliche Gewährleistung von 3 Jahren.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "PT", name: "Portugal", statutoryMonths: 36, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Für bewegliche Güter gilt grundsätzlich eine gesetzliche Gewährleistung von 3 Jahren.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "NL", name: "Niederlande", statutoryMonths: nil, presumptionMonths: 12, onlineWithdrawalDays: 14, notes: [
            "Keine feste Frist: Die Ware muss so lange funktionieren, wie man es vernünftigerweise erwarten darf.",
            "Die App schlägt 2 Jahre als Mindestwert vor. Passe die Frist bei langlebigen Geräten an.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "BE", name: "Belgien", statutoryMonths: 24, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Gesetzliche Gewährleistung 2 Jahre.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "LU", name: "Luxemburg", statutoryMonths: 24, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Gesetzliche Gewährleistung 2 Jahre.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "SE", name: "Schweden", statutoryMonths: 36, presumptionMonths: 24, onlineWithdrawalDays: 14, notes: [
            "Reklamationsrecht 3 Jahre.",
            "Widerrufsrecht bei Online-Käufen: 14 Tage."
        ]),
        CountryRules(code: "EU", name: "Anderes EU-Land", statutoryMonths: 24, presumptionMonths: 12, onlineWithdrawalDays: 14, notes: [
            "Die EU schreibt mindestens 2 Jahre vor. Einzelne Länder sehen längere Fristen vor.",
            "Widerrufsrecht bei Online-Käufen: mindestens 14 Tage."
        ]),
        CountryRules(code: "XX", name: "Anderes Land", statutoryMonths: nil, presumptionMonths: nil, onlineWithdrawalDays: nil, notes: [
            "Für dieses Land sind keine Standardwerte hinterlegt. Erfasse die Fristen manuell."
        ])
    ]

    public static func rules(for code: String?) -> CountryRules {
        guard let code else { return all.first { $0.code == "XX" }! }
        return all.first { $0.code == code.uppercased() } ?? all.first { $0.code == "XX" }!
    }

    /// Statutory months to suggest. For countries without a fixed period, suggest the EU minimum.
    public static func suggestedStatutoryMonths(for code: String) -> Int? {
        let r = rules(for: code)
        if let months = r.statutoryMonths { return months }
        return code == "NL" ? 24 : nil
    }
}
