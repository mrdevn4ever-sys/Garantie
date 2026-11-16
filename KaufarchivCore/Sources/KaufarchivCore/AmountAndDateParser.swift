import Foundation

public struct AmountMatch: Equatable, Sendable {
    public var value: Decimal
    public var location: Int
    public var length: Int
}

/// Erkennt Geldbeträge in europäischen Schreibweisen: 49.90, 49,90, 1'299.00, 1.299,00, 399.–
public enum AmountParser {
    private static let decimalPattern = TextTools.regex(
        #"(?<![\d.,])(?:\d{1,3}(?:['’ .,]\d{3})+|\d+)[.,]\d{2}(?![.,]?\d)"#
    )
    private static let roundPattern = TextTools.regex(
        #"(?<![\d.,])(\d{1,3}(?:['’]\d{3})+|\d+)\.[-–—]{1,2}"#
    )

    public static func amounts(in text: String) -> [AmountMatch] {
        let ns = text as NSString
        var result: [AmountMatch] = []

        for match in TextTools.matches(decimalPattern, in: text) {
            let raw = ns.substring(with: match.range)
            guard var value = decimal(from: raw) else { continue }
            let end = match.range.location + match.range.length
            // Prozentwerte (z. B. «8.10 %») sind keine Beträge.
            if nextNonSpace(in: ns, from: end) == "%" { continue }
            if isNegative(ns: ns, start: match.range.location, end: end) { value = -value }
            result.append(AmountMatch(value: value, location: match.range.location, length: match.range.length))
        }

        for match in TextTools.matches(roundPattern, in: text) {
            let overlaps = result.contains { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), match.range).length > 0 }
            if overlaps { continue }
            let digits = ns.substring(with: match.range(at: 1)).filter { $0.isNumber }
            guard var value = Decimal(string: digits) else { continue }
            if isNegative(ns: ns, start: match.range.location, end: match.range.location) { value = -value }
            result.append(AmountMatch(value: value, location: match.range.location, length: match.range.length))
        }

        return result.sorted { $0.location < $1.location }
    }

    /// Wandelt eine Benutzereingabe oder einen erkannten Betrag in eine Dezimalzahl um.
    public static func decimal(from raw: String) -> Decimal? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }
        guard let separatorIndex = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return Decimal(string: cleaned)
        }
        let fraction = cleaned[cleaned.index(after: separatorIndex)...].filter { $0.isNumber }
        let integer = cleaned[..<separatorIndex].filter { $0.isNumber }
        // Drei Nachkommastellen deuten auf ein Tausendertrennzeichen hin (1.299 = 1299).
        if fraction.count == 3 {
            return Decimal(string: integer + fraction)
        }
        return Decimal(string: "\(integer.isEmpty ? "0" : integer).\(fraction.isEmpty ? "0" : fraction)")
    }

    private static func nextNonSpace(in ns: NSString, from index: Int) -> String? {
        var i = index
        while i < ns.length {
            let character = ns.substring(with: NSRange(location: i, length: 1))
            if character != " " && character != "\u{00A0}" { return character }
            i += 1
        }
        return nil
    }

    private static func isNegative(ns: NSString, start: Int, end: Int) -> Bool {
        let minusSigns: Set<String> = ["-", "−", "–"]
        // Nachgestelltes Minus: «5.00-»
        if end < ns.length, end > start {
            let trailing = ns.substring(with: NSRange(location: end, length: 1))
            if trailing == "-" || trailing == "−" { return true }
        }
        // Vorangestelltes Minus, optional mit einem Leerzeichen: «-5.00», «- 5.00»
        var i = start - 1
        if i >= 0, ns.substring(with: NSRange(location: i, length: 1)) == " " { i -= 1 }
        guard i >= 0, minusSigns.contains(ns.substring(with: NSRange(location: i, length: 1))) else { return false }
        if i == 0 { return true }
        let before = ns.substring(with: NSRange(location: i - 1, length: 1))
        guard let scalar = before.unicodeScalars.first else { return true }
        return !CharacterSet.alphanumerics.contains(scalar)
    }
}

public struct DateMatch: Equatable, Sendable {
    public var date: Date
    public var location: Int
}

/// Erkennt Datumsangaben in den auf Belegen üblichen Schreibweisen.
public enum DateParser {
    private static let isoPattern = TextTools.regex(#"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#)
    private static let numericPattern = TextTools.regex(#"(?<![\d.])(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?![\d.,])"#)
    private static let dayMonthNamePattern = TextTools.regex(#"(?<!\d)(\d{1,2})\.?\s+(\p{L}{3,10})\.?\s+(\d{4})(?!\d)"#)
    private static let monthNameDayPattern = TextTools.regex(#"(\p{L}{3,10})\.?\s+(\d{1,2}),\s*(\d{4})(?!\d)"#)

    public static func dates(in text: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> [DateMatch] {
        var result: [DateMatch] = []
        var used: [NSRange] = []

        func add(_ match: NSTextCheckingResult, year: Int?, month: Int?, day: Int?) {
            guard let year, let month, let day else { return }
            if used.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { return }
            guard let date = makeDate(year: year, month: month, day: day, calendar: calendar) else { return }
            used.append(match.range)
            result.append(DateMatch(date: date, location: match.range.location))
        }

        for match in TextTools.matches(isoPattern, in: text) {
            add(match,
                year: TextTools.group(1, of: match, in: text).flatMap { Int($0) },
                month: TextTools.group(2, of: match, in: text).flatMap { Int($0) },
                day: TextTools.group(3, of: match, in: text).flatMap { Int($0) })
        }
        for match in TextTools.matches(numericPattern, in: text) {
            var year = TextTools.group(3, of: match, in: text).flatMap { Int($0) }
            if let short = year, short < 100 { year = 2000 + short }
            add(match,
                year: year,
                month: TextTools.group(2, of: match, in: text).flatMap { Int($0) },
                day: TextTools.group(1, of: match, in: text).flatMap { Int($0) })
        }
        for match in TextTools.matches(dayMonthNamePattern, in: text) {
            add(match,
                year: TextTools.group(3, of: match, in: text).flatMap { Int($0) },
                month: TextTools.group(2, of: match, in: text).flatMap { month(named: $0) },
                day: TextTools.group(1, of: match, in: text).flatMap { Int($0) })
        }
        for match in TextTools.matches(monthNameDayPattern, in: text) {
            add(match,
                year: TextTools.group(3, of: match, in: text).flatMap { Int($0) },
                month: TextTools.group(1, of: match, in: text).flatMap { month(named: $0) },
                day: TextTools.group(2, of: match, in: text).flatMap { Int($0) })
        }
        return result.sorted { $0.location < $1.location }
    }

    static func month(named name: String) -> Int? {
        let folded = TextTools.folded(name)
        if folded.hasPrefix("juil") { return 7 }
        if folded.hasPrefix("juin") { return 6 }
        let prefixes: [(String, Int)] = [
            ("jan", 1), ("gen", 1),
            ("feb", 2), ("fev", 2),
            ("mar", 3), ("mrz", 3),
            ("apr", 4), ("avr", 4),
            ("mai", 5), ("may", 5), ("mag", 5),
            ("jun", 6), ("giu", 6),
            ("jul", 7), ("lug", 7),
            ("aug", 8), ("aou", 8), ("ago", 8),
            ("sep", 9), ("set", 9),
            ("okt", 10), ("oct", 10), ("ott", 10),
            ("nov", 11),
            ("dez", 12), ("dec", 12), ("dic", 12)
        ]
        return prefixes.first { folded.hasPrefix($0.0) }?.1
    }

    static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        // Ungültige Tage (31.02.) würden sonst stillschweigend in den Folgemonat rutschen.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
