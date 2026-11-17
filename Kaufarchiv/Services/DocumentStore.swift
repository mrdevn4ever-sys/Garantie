import Foundation
import SwiftData
import UIKit
import PDFKit
import CryptoKit
import UniformTypeIdentifiers
import KaufarchivCore

/// A file the user wants to import, before it is stored.
struct IncomingFile: Identifiable {
    let id = UUID()
    var data: Data
    var filename: String
    var type: UTType

    var isPDF: Bool { type.conforms(to: .pdf) }

    static func image(_ image: UIImage, name: String) -> IncomingFile? {
        // HEIC keeps quality at smaller size; fall back to JPEG with high quality.
        if let data = image.heicData() {
            return IncomingFile(data: data, filename: name + ".heic", type: .heic)
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        return IncomingFile(data: data, filename: name + ".jpg", type: .jpeg)
    }

    static func file(at url: URL) throws -> IncomingFile {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return IncomingFile(data: data, filename: url.lastPathComponent, type: type)
    }
}

enum DocumentStoreError: LocalizedError {
    case unsupportedType
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedType: "Dieses Dateiformat wird nicht unterstützt. Verwende ein Bild oder ein PDF."
        case .unreadable: "Die Datei konnte nicht gelesen werden."
        }
    }
}

/// Stores original files untouched (with checksum) and creates a separate preview.
enum DocumentStore {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    static func makeDocument(from file: IncomingFile, kind: DocumentKind, title: String? = nil, lines: [TextLine] = [], in context: ModelContext) throws -> StoredDocument {
        guard file.isPDF || file.type.conforms(to: .image) else { throw DocumentStoreError.unsupportedType }
        let doc = StoredDocument(kind: kind,
                                 title: title ?? kind.title,
                                 originalFilename: file.filename,
                                 contentType: file.isPDF ? UTType.pdf.identifier : file.type.identifier)
        doc.byteCount = file.data.count
        doc.sha256 = sha256(file.data)
        doc.pageCount = file.isPDF ? (PDFDocument(data: file.data)?.pageCount ?? 1) : 1
        doc.thumbnail = thumbnail(for: file.data, isPDF: file.isPDF)
        doc.lines = lines
        doc.ocrText = lines.map(\.text).joined(separator: "\n")
        context.insert(doc)
        let blob = DocumentBlob(data: file.data)
        context.insert(blob)
        doc.blob = blob
        return doc
    }

    /// Verifies the stored bytes still match the checksum taken at import.
    static func verify(_ document: StoredDocument) -> Bool {
        guard let data = document.originalData else { return false }
        return sha256(data) == document.sha256
    }

    static func thumbnail(for data: Data, isPDF: Bool, maxPixel: CGFloat = 600) -> Data? {
        let image: UIImage?
        if isPDF {
            image = PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: maxPixel, height: maxPixel), for: .mediaBox)
        } else {
            image = downsample(data: data, maxPixel: maxPixel)
        }
        return image?.jpegData(compressionQuality: 0.75)
    }

    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Full-resolution page images (orientation corrected) used for OCR and dossiers.
    static func pageImages(for data: Data, isPDF: Bool, maxPixel: CGFloat = 2600) -> [UIImage] {
        if isPDF {
            guard let pdf = PDFDocument(data: data) else { return [] }
            return (0..<pdf.pageCount).compactMap { index in
                guard let page = pdf.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = min(maxPixel / max(bounds.width, bounds.height), 4)
                return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            }
        }
        return downsample(data: data, maxPixel: maxPixel).map { [$0] } ?? []
    }

    static func temporaryURL(for document: StoredDocument) throws -> URL {
        guard let data = document.originalData else { throw DocumentStoreError.unreadable }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(document.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = document.originalFilename.isEmpty ? "\(document.title).\(document.isPDF ? "pdf" : "jpg")" : document.originalFilename
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
