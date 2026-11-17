import Foundation

public struct Money: Codable, Hashable, Sendable, Comparable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.amount < rhs.amount }
}

/// Parses monetary amounts in Swiss, German, French and English notations.
public enum MoneyParser {
    public static let knownCurrencies: [String: String] = [
        "CHF": "CHF", "FR.": "CHF", "SFR": "CHF", "SFR.": "CHF",
        "EUR": "EUR", "€": "EUR",
        "USD": "USD", "US$": "USD", "$": "USD",
        "GBP": "GBP", "£": "GBP"
    ]

    /// Detects the currency mentioned in a text, if any.
    public static func detectCurrency(in text: String) -> String? {
        let upper = text.uppercased()
        // Longest tokens first so "US$" wins over "$".
        for token in knownCurrencies.keys.sorted(by: { $0.count > $1.count }) {
            if token.count <= 1 || token.hasSuffix(".") || token.contains("$") {
                if upper.contains(token) { return knownCurrencies[token] }
            } else if upper.range(of: "(^|[^A-Z])\(NSRegularExpression.escapedPattern(for: token))([^A-Z]|$)", options: .regularExpression) != nil {
                return knownCurrencies[token]
            }
        }
        return nil
    }

    private static let amountRegex: NSRegularExpression = {
        // Matches 1'234.50  1’234.50  1.234,50  1,234.50  1234.50  12,90  12.–  12.-  -5.00
        // Spaces are deliberately not accepted as thousands separators: "2 199.00" is usually quantity + price.
        let pattern = #"(?<![\d'’.,])-?\d{1,3}(?:['’.,]\d{3})*(?:[.,](?:\d{2}|-{1,2}|–))?(?![\d])|(?<![\d'’.,])-?\d+(?:[.,](?:\d{2}|-{1,2}|–))(?![\d])"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// All amounts found in a string, in order of appearance.
    public static func amounts(in text: String) -> [Decimal] {
        let ns = text as NSString
        let matches = amountRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { parseAmount(ns.substring(with: $0.range)) }
    }

    /// Amounts that look like prices (with decimals or a currency-style dash).
    public static func priceAmounts(in text: String) -> [Decimal] {
        let ns = text as NSString
        let matches = amountRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> Decimal? in
            let raw = ns.substring(with: match.range)
            guard raw.range(of: #"[.,](\d{2}|-{1,2}|–)$"#, options: .regularExpression) != nil else { return nil }
            return parseAmount(raw)
        }
    }

    /// Parses a single amount token such as "1'234.50", "1.234,50" or "29.–".
    public static func parseAmount(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }
        // Swiss "29.–" / "29.-" means 29.00
        s = s.replacingOccurrences(of: "–", with: "00")
        s = s.replacingOccurrences(of: "--", with: "00")
        if s.hasSuffix(".-") || s.hasSuffix(",-") {
            s = String(s.dropLast()) + "00"
        }
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingOccurrences(of: "’", with: "")
        s = s.replacingOccurrences(of: " ", with: "")

        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")
        var normalized: String
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            if dot > comma {
                normalized = s.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        case let (dot?, nil):
            let decimals = s.distance(from: dot, to: s.endIndex) - 1
            let dotCount = s.filter { $0 == "." }.count
            normalized = (decimals == 3 && dotCount >= 1 && !s.hasPrefix("0")) || dotCount > 1
                ? s.replacingOccurrences(of: ".", with: "")
                : s
        case let (nil, comma?):
            let decimals = s.distance(from: comma, to: s.endIndex) - 1
            let commaCount = s.filter { $0 == "," }.count
            normalized = (decimals == 3 && commaCount >= 1) || commaCount > 1
                ? s.replacingOccurrences(of: ",", with: "")
                : s.replacingOccurrences(of: ",", with: ".")
        case (nil, nil):
            normalized = s
        }
        guard !normalized.isEmpty, let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return negative ? -value : value
    }
}
