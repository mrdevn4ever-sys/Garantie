import Foundation

/// Normalised rectangle in the coordinate space of a page (0...1, origin top-left).
public struct NormalizedRect: Codable, Hashable, Sendable {
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

    public static let zero = NormalizedRect(x: 0, y: 0, width: 0, height: 0)

    public var midY: Double { y + height / 2 }

    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width)
        let maxY = max(y + height, other.y + other.height)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// One recognised line of text, with the location it came from.
public struct TextLine: Codable, Hashable, Sendable {
    public var text: String
    public var page: Int
    public var rect: NormalizedRect
    /// Recogniser confidence 0...1.
    public var confidence: Double

    public init(text: String, page: Int = 0, rect: NormalizedRect = .zero, confidence: Double = 1) {
        self.text = text
        self.page = page
        self.rect = rect
        self.confidence = confidence
    }
}

/// Where a recognised value was found in the original document.
public struct SourceLocation: Codable, Hashable, Sendable {
    public var page: Int
    public var rect: NormalizedRect
    public var lineIndex: Int
    public var excerpt: String

    public init(page: Int, rect: NormalizedRect, lineIndex: Int, excerpt: String) {
        self.page = page
        self.rect = rect
        self.lineIndex = lineIndex
        self.excerpt = excerpt
    }

    init(line: TextLine, index: Int) {
        self.init(page: line.page, rect: line.rect, lineIndex: index, excerpt: line.text)
    }
}

/// How sure the parser is about a value. Anything below `.certain` must be shown as a suggestion.
public enum Certainty: Int, Codable, Comparable, Sendable {
    case guess = 0
    case likely = 1
    case certain = 2

    public static func < (lhs: Certainty, rhs: Certainty) -> Bool { lhs.rawValue < rhs.rawValue }

    public var isSuggestion: Bool { self != .certain }
}

/// A value extracted from a document, always traceable to its source.
public struct Extracted<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var certainty: Certainty
    public var source: SourceLocation?

    public init(value: Value, certainty: Certainty, source: SourceLocation?) {
        self.value = value
        self.certainty = certainty
        self.source = source
    }
}
