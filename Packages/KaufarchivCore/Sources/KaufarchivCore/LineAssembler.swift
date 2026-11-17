import Foundation

/// Text recognisers often split one receipt line into several fragments
/// ("Kaffeemaschine" on the left, "349.00" on the right). The assembler joins fragments
/// whose vertical centres are close and orders everything top-to-bottom, left-to-right.
public enum LineAssembler {
    public static func assemble(_ fragments: [TextLine]) -> [TextLine] {
        let byPage = Dictionary(grouping: fragments, by: \.page)
        var result: [TextLine] = []
        for page in byPage.keys.sorted() {
            let items = byPage[page]!.sorted { $0.rect.midY < $1.rect.midY }
            let heights = items.map(\.rect.height).filter { $0 > 0 }.sorted()
            let median = heights.isEmpty ? 0.01 : heights[heights.count / 2]
            let tolerance = max(median * 0.5, 0.002)

            var rows: [[TextLine]] = []
            for fragment in items {
                if let lastIndex = rows.indices.last,
                   let anchor = rows[lastIndex].first,
                   abs(anchor.rect.midY - fragment.rect.midY) <= tolerance {
                    rows[lastIndex].append(fragment)
                } else {
                    rows.append([fragment])
                }
            }
            for row in rows {
                let ordered = row.sorted { $0.rect.x < $1.rect.x }
                let text = ordered.map(\.text).joined(separator: "   ")
                let rect = ordered.dropFirst().reduce(ordered[0].rect) { $0.union($1.rect) }
                let confidence = ordered.map(\.confidence).min() ?? 1
                result.append(TextLine(text: text, page: page, rect: rect, confidence: confidence))
            }
        }
        return result
    }
}
