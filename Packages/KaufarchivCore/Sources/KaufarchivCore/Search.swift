import Foundation

public enum SearchNormalizer {
    /// Lower-cases, removes diacritics and collapses whitespace so "Kaffeemaschine" finds "KAFFEEMASCHINE" and "Café".
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_CH"))
            .replacingOccurrences(of: "ß", with: "ss")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when every token of the query occurs in the haystack.
    public static func matches(query: String, in haystack: String) -> Bool {
        let tokens = normalize(query).split(separator: " ")
        guard !tokens.isEmpty else { return true }
        let hay = normalize(haystack)
        return tokens.allSatisfy { hay.contains($0) }
    }
}

public enum Entitlements {
    /// Products that can be stored without Pro.
    public static let freeProductLimit = 10

    public static func canAddProducts(existing: Int, adding: Int, isPro: Bool) -> Bool {
        isPro || existing + adding <= freeProductLimit
    }
}
