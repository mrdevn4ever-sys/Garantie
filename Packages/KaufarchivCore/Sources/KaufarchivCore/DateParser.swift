import Foundation

/// Finds purchase dates in receipt text (numeric and written-out month formats in DE/FR/IT/EN).
public enum DateParser {
    static let monthNames: [String: Int] = [
        // German
        "januar": 1, "jänner": 1, "jan": 1, "februar": 2, "feb": 2, "märz": 3, "maerz": 3, "mär": 3, "mrz": 3,
        "april": 4, "apr": 4, "mai": 5, "juni": 6, "jun": 6, "juli": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "oktober": 10, "okt": 10, "november": 11, "nov": 11,
        "dezember": 12, "dez": 12,
        // English
        "january": 1, "february": 2, "march": 3, "mar": 3, "may": 5, "june": 6, "july": 7,
        "october": 10, "oct": 10, "december": 12, "dec": 12,
        // French
        "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "juin": 6, "juillet": 7,
        "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
        // Italian
        "gennaio": 1, "febbraio": 2, "marzo": 3, "aprile": 4, "maggio": 5, "giugno": 6, "luglio": 7,
        "agosto": 8, "settembre": 9, "ottobre": 10, "dicembre": 12
    ]

    public struct Match: Hashable, Sendable {
        public var date: Date
        public var range: Range<String.Index>
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let numericRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})[./\-](\d{1,2})[./\-](\d{4}|\d{2})(?!\d)"#)
    private static let isoRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#)
    private static let writtenRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\.?\s*([A-Za-zÄÖÜäöüéèûôà]{3,10})\.?\s+(\d{4})"#)

    /// All plausible dates in a string. Dates in the future (relative to `now`) or before 1990 are dropped.
    public static func dates(in text: String, now: Date = Date()) -> [Match] {
        var results: [Match] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        for m in isoRegex.matches(in: text, range: full) {
            if let y = Int(ns.substring(with: m.range(at: 1))),
               let mo = Int(ns.substring(with: m.range(at: 2))),
               let d = Int(ns.substring(with: m.range(at: 3))),
               let date = make(year: y, month: mo, day: d),
               let r = Range(m.range, in: text) {
                results.append(Match(date: date, range: r))
            }
        }
        for m in numericRegex.matches(in: text, range: full) {
            guard let d = Int(ns.substring(with: m.range(at: 1))),
                  let mo = Int(ns.substring(with: m.range(at: 2))),
                  var y = Int(ns.substring(with: m.range(at: 3))),
                  let r = Range(m.range, in: text) else { continue }
            if y < 100 { y += 2000 }
            // European order first; fall back to US order if day/month would be invalid.
            if let date = make(year: y, month: mo, day: d) {
                results.append(Match(date: date, range: r))
            } else if let date = make(year: y, month: d, day: mo) {
                results.append(Match(date: date, range: r))
            }
        }
        for m in writtenRegex.matches(in: text, range: full) {
            let monthToken = ns.substring(with: m.range(at: 2)).lowercased()
            guard let d = Int(ns.substring(with: m.range(at: 1))),
                  let mo = monthNames[monthToken],
                  let y = Int(ns.substring(with: m.range(at: 3))),
                  let date = make(year: y, month: mo, day: d),
                  let r = Range(m.range, in: text) else { continue }
            results.append(Match(date: date, range: r))
        }
        let latest = now.addingTimeInterval(2 * 86_400)
        let earliest = make(year: 1990, month: 1, day: 1)!
        return results
            .filter { $0.date <= latest && $0.date >= earliest }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Replaces anything that looks like a date with spaces (used before amount detection).
    public static func removingDates(from text: String) -> String {
        var result = text
        for regex in [isoRegex, numericRegex, writtenRegex] {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        return result
    }

    static func make(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        guard let date = calendar.date(from: comps) else { return nil }
        // Reject overflow like 31.02.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
