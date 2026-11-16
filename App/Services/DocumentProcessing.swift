import Foundation
import UIKit
import PDFKit
import Vision
import UniformTypeIdentifiers
import KaufarchivCore

enum DocumentRenderer {
    static func isPDF(data: Data, typeIdentifier: String) -> Bool {
        if let type = UTType(typeIdentifier), type.conforms(to: .pdf) { return true }
        return data.prefix(5) == Data("%PDF-".utf8)
    }

    static func pageCount(data: Data, typeIdentifier: String) -> Int {
        guard isPDF(data: data, typeIdentifier: typeIdentifier) else { return 1 }
        return max(PDFDocument(data: data)?.pageCount ?? 1, 1)
    }

    /// Rendert eine Seite des Originals als Bild in aufrechter Ausrichtung.
    static func pageImage(data: Data, typeIdentifier: String, page: Int, maxDimension: CGFloat = 2400) -> UIImage? {
        if isPDF(data: data, typeIdentifier: typeIdentifier) {
            guard let document = PDFDocument(data: data), let pdfPage = document.page(at: page) else { return nil }
            let bounds = pdfPage.bounds(for: .mediaBox)
            let longest = max(bounds.width, bounds.height, 1)
            let scale = min(maxDimension / longest, 3)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let thumbnail = pdfPage.thumbnail(of: size, for: .mediaBox)
            return normalized(thumbnail, maxDimension: maxDimension)
        }
        guard page == 0, let image = UIImage(data: data) else { return nil }
        return normalized(image, maxDimension: maxDimension)
    }

    /// Zeichnet das Bild neu, damit Ausrichtung und Pixelraster eindeutig sind (Fundstellen beziehen sich darauf).
    static func normalized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height, 1)
        let scale = min(maxDimension / longest, 1)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func allPageImages(data: Data, typeIdentifier: String, maxPages: Int = 12) -> [UIImage] {
        let count = min(pageCount(data: data, typeIdentifier: typeIdentifier), maxPages)
        return (0..<count).compactMap { pageImage(data: data, typeIdentifier: typeIdentifier, page: $0) }
    }

    static func preview(from image: UIImage) -> Data? {
        normalized(image, maxDimension: 600).jpegData(compressionQuality: 0.7)
    }

    /// Fasst gescannte Seiten in voller Auflösung zu einem PDF zusammen.
    static func pdf(from images: [UIImage]) -> Data {
        let firstSize = images.first?.size ?? CGSize(width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstSize))
        return renderer.pdfData { context in
            for image in images {
                let bounds = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }
    }
}

enum OCRService {
    /// Erkennt Text vollständig auf dem Gerät und liefert zusammengesetzte Belegzeilen mit Fundstellen.
    static func recognize(images: [UIImage]) async throws -> [TextLine] {
        let cgImages = images.compactMap { $0.cgImage }
        return try await Task.detached(priority: .userInitiated) {
            var fragments: [TextLine] = []
            for (page, cgImage) in cgImages.enumerated() {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // Sprachkorrektur verfälscht Beträge, Modell- und Seriennummern.
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["de-DE", "fr-FR", "it-IT", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
                for observation in request.results ?? [] {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let box = observation.boundingBox
                    fragments.append(TextLine(
                        text: candidate.string,
                        box: NormRect(
                            x: Double(box.minX),
                            y: Double(1 - box.maxY),
                            width: Double(box.width),
                            height: Double(box.height)
                        ),
                        page: page,
                        confidence: Double(candidate.confidence)
                    ))
                }
            }
            return LayoutReconstructor.rows(from: fragments)
        }.value
    }
}

/// Ein importiertes Original, bevor es gespeichert wird.
struct ImportedFile {
    var data: Data
    var typeIdentifier: String
    var filename: String

    static func from(url: URL) throws -> ImportedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return ImportedFile(data: data, typeIdentifier: type.identifier, filename: url.lastPathComponent)
    }

    static func from(scannedPages: [UIImage]) -> ImportedFile {
        ImportedFile(
            data: DocumentRenderer.pdf(from: scannedPages),
            typeIdentifier: UTType.pdf.identifier,
            filename: "Scan \(Fmt.fileStamp()).pdf"
        )
    }

    static func from(imageData: Data) -> ImportedFile {
        let isPNG = imageData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
        let isHEIC = imageData.count > 12 && String(data: imageData.subdata(in: 4..<12), encoding: .ascii)?.hasPrefix("ftyphei") == true
        let type: UTType = isPNG ? .png : (isHEIC ? .heic : .jpeg)
        let ext = type.preferredFilenameExtension ?? "jpg"
        return ImportedFile(data: imageData, typeIdentifier: type.identifier, filename: "Foto \(Fmt.fileStamp()).\(ext)")
    }
}

enum DocumentFactory {
    /// Erstellt ein gespeichertes Dokument: Original unverändert, Vorschau und erkannter Text getrennt.
    @MainActor
    static func make(file: ImportedFile, kind: DocumentKind, title: String = "", lines: [TextLine]? = nil,
                     firstPage: UIImage? = nil) async -> StoredDocument {
        let document = StoredDocument(kind: kind, title: title, filename: file.filename, typeIdentifier: file.typeIdentifier)
        document.originalData = file.data
        document.sha256 = Hashing.sha256(file.data)
        document.pageCount = DocumentRenderer.pageCount(data: file.data, typeIdentifier: file.typeIdentifier)

        var recognized = lines
        var previewSource = firstPage
        if recognized == nil || previewSource == nil {
            let images = DocumentRenderer.allPageImages(data: file.data, typeIdentifier: file.typeIdentifier)
            if previewSource == nil { previewSource = images.first }
            if recognized == nil { recognized = (try? await OCRService.recognize(images: images)) ?? [] }
        }
        if let previewSource { document.previewData = DocumentRenderer.preview(from: previewSource) }
        let finalLines = recognized ?? []
        document.ocrText = finalLines.map { $0.text }.joined(separator: "\n")
        document.linesData = try? JSONEncoder().encode(finalLines)
        return document
    }
}
