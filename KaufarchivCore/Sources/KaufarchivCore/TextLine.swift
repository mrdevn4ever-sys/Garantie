import Foundation

/// Rechteck in normalisierten Koordinaten (0...1), Ursprung oben links.
public struct NormRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func union(_ other: NormRect) -> NormRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(self.maxX, other.maxX)
        let maxY = max(self.maxY, other.maxY)
        return NormRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Eine erkannte Textzeile samt Fundstelle im Beleg.
public struct TextLine: Codable, Hashable, Sendable {
    public var text: String
    public var box: NormRect
    public var page: Int
    public var confidence: Double

    public init(text: String, box: NormRect, page: Int = 0, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.page = page
        self.confidence = confidence
    }
}

/// Fügt einzelne Textfragmente der Texterkennung zu Belegzeilen zusammen.
/// Auf Kassenbons stehen Bezeichnung und Preis oft als getrennte Fragmente auf gleicher Höhe.
public enum LayoutReconstructor {
    public static func rows(from fragments: [TextLine]) -> [TextLine] {
        var result: [TextLine] = []
        let pages = Dictionary(grouping: fragments, by: { $0.page })
        for page in pages.keys.sorted() {
            let sorted = (pages[page] ?? []).sorted { $0.box.midY < $1.box.midY }
            var rows: [[TextLine]] = []
            for fragment in sorted {
                if let last = rows.last, let reference = last.first {
                    let rowMid = last.map { $0.box.midY }.reduce(0, +) / Double(last.count)
                    let height = max(min(reference.box.height, fragment.box.height), 0.004)
                    if abs(fragment.box.midY - rowMid) < height * 0.6 {
                        rows[rows.count - 1].append(fragment)
                        continue
                    }
                }
                rows.append([fragment])
            }
            for row in rows {
                let ordered = row.sorted { $0.box.x < $1.box.x }
                guard var box = ordered.first?.box else { continue }
                for fragment in ordered.dropFirst() { box = box.union(fragment.box) }
                let text = ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "  ")
                let confidence = ordered.map { $0.confidence }.min() ?? 1
                result.append(TextLine(text: text, box: box, page: page, confidence: confidence))
            }
        }
        return result
    }
}

enum TextTools {
    /// Kleinschreibung ohne Umlaute/Akzente, damit Schlüsselwörter robust verglichen werden können.
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    static func tokens(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    static func letterCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isLetter ? 1 : 0) }
    }

    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Die Muster sind fest im Code hinterlegt und durch Tests abgedeckt.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
