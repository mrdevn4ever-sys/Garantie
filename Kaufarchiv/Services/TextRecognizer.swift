import Foundation
import Vision
import PDFKit
import UIKit
import KaufarchivCore

/// On-device text recognition. Works without network and without Apple Intelligence.
/// On iOS 26 the document-structure recogniser is used in addition to improve table rows.
enum TextRecognizer {
    static let languages = ["de-DE", "fr-FR", "it-IT", "en-US"]

    /// Recognises all pages of a file and returns assembled lines with positions.
    static func recognize(data: Data, isPDF: Bool) async -> [TextLine] {
        if isPDF, let embedded = embeddedPDFText(data: data), embedded.count >= 3 {
            // Digital invoices (e-mail PDFs) already contain exact text: no OCR needed.
            return embedded
        }
        let images = DocumentStore.pageImages(for: data, isPDF: isPDF)
        var lines: [TextLine] = []
        for (page, image) in images.enumerated() {
            lines += await recognize(image: image, page: page)
        }
        return lines
    }

    static func recognize(image: UIImage, page: Int) async -> [TextLine] {
        guard let cgImage = image.cgImage else { return [] }
        let fragments = await recognizeFragments(cgImage: cgImage, orientation: image.cgOrientation, page: page)
        var lines = LineAssembler.assemble(fragments)
        if #available(iOS 26.0, *) {
            lines = await DocumentStructure.improve(lines: lines, cgImage: cgImage)
        }
        return lines
    }

    private static func recognizeFragments(cgImage: CGImage, orientation: CGImagePropertyOrientation, page: Int) async -> [TextLine] {
        // Vision is synchronous and CPU heavy: run it off the main actor.
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = TextRecognizer.languages
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { observation -> TextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox // normalised, origin bottom-left
                let rect = NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                return TextLine(text: candidate.string, page: page, rect: rect, confidence: Double(candidate.confidence))
            }
        }.value
    }

    /// Extracts the text layer of a digital PDF line by line, with positions.
    static func embeddedPDFText(data: Data) -> [TextLine]? {
        guard let pdf = PDFDocument(data: data) else { return nil }
        var result: [TextLine] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index), let text = page.string, !text.isEmpty else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let full = page.selection(for: bounds)
            for lineSelection in full?.selectionsByLine() ?? [] {
                guard let lineText = lineSelection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !lineText.isEmpty else { continue }
                let r = lineSelection.bounds(for: page)
                let rect = NormalizedRect(x: (r.minX - bounds.minX) / bounds.width,
                                          y: 1 - (r.maxY - bounds.minY) / bounds.height,
                                          width: r.width / bounds.width,
                                          height: r.height / bounds.height)
                result.append(TextLine(text: lineText, page: index, rect: rect, confidence: 1))
            }
        }
        return result.isEmpty ? nil : LineAssembler.assemble(result)
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

#if compiler(>=6.2)
/// iOS 26: `RecognizeDocumentsRequest` understands tables. Rows of a table are used to
/// re-join item names and prices that the line recogniser split apart.
@available(iOS 26.0, *)
enum DocumentStructure {
    static func improve(lines: [TextLine], cgImage: CGImage) async -> [TextLine] {
        let request = RecognizeDocumentsRequest()
        guard let observations = try? await request.perform(on: cgImage),
              let document = observations.first?.document else {
            return lines
        }
        var rows: [String] = []
        for table in document.tables {
            for row in table.rows {
                let cells = row.map { $0.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
                let text = cells.filter { !$0.isEmpty }.joined(separator: "   ")
                if !text.isEmpty { rows.append(text) }
            }
        }
        guard !rows.isEmpty else { return lines }
        return merge(lines: lines, tableRows: rows)
    }

    /// Replaces consecutive lines that together form one table row by a single line.
    static func merge(lines: [TextLine], tableRows: [String]) -> [TextLine] {
        var result: [TextLine] = []
        var index = 0
        let normalizedRows = Set(tableRows.map(normalize))
        while index < lines.count {
            if index + 1 < lines.count {
                let combined = lines[index].text + "   " + lines[index + 1].text
                if normalizedRows.contains(normalize(combined)) {
                    result.append(TextLine(text: combined, page: lines[index].page,
                                           rect: lines[index].rect.union(lines[index + 1].rect),
                                           confidence: min(lines[index].confidence, lines[index + 1].confidence)))
                    index += 2
                    continue
                }
            }
            result.append(lines[index])
            index += 1
        }
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}
#else
enum DocumentStructure {
    static func improve(lines: [TextLine], cgImage: CGImage) async -> [TextLine] { lines }
}
#endif
