import Foundation
import UIKit
import PDFKit
import SwiftData
import UniformTypeIdentifiers
import KaufarchivCore

/// Builds the claim dossier: one PDF with product data, defect description, coverages,
/// history, the original receipt pages and the defect photos.
enum DossierService {
    static let pageSize = CGSize(width: 595.2, height: 841.8) // A4 in points
    static let margin: CGFloat = 48

    @MainActor
    static func makePDF(claim: Claim) -> Data {
        guard let product = claim.product else { return Data() }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_CH")
        df.dateStyle = .long

        return renderer.pdfData { ctx in
            var cursor = PageCursor(ctx: ctx)
            cursor.newPage()

            cursor.draw("Reklamationsdossier", font: .systemFont(ofSize: 24, weight: .bold))
            cursor.draw("Erstellt am \(df.string(from: Date())) mit Kaufarchiv", font: .systemFont(ofSize: 11), color: .secondaryLabel)
            cursor.space(16)

            cursor.heading("Produkt")
            cursor.row("Bezeichnung", product.name)
            cursor.row("Marke", product.brand)
            cursor.row("Modell", product.modelName)
            cursor.row("Seriennummer", product.serialNumber)
            cursor.row("Artikelnummer", product.articleNumber)
            if let price = product.price {
                cursor.row("Kaufpreis", Formatters.money(price, currency: product.purchase?.currency ?? "CHF"))
            }

            if let purchase = product.purchase {
                cursor.heading("Kauf")
                cursor.row("Händler", purchase.merchant)
                cursor.row("Kaufdatum", df.string(from: purchase.purchaseDate))
                if let delivery = purchase.deliveryDate { cursor.row("Lieferdatum", df.string(from: delivery)) }
                cursor.row("Beleg-/Bestellnummer", purchase.orderNumber)
                if let total = purchase.totalAmount {
                    cursor.row("Belegtotal", Formatters.money(total, currency: purchase.currency))
                }
            }

            cursor.heading("Mangel")
            cursor.row("Festgestellt am", df.string(from: claim.defectNoticedOn))
            cursor.row("Gewünschte Lösung", claim.remedy.title)
            cursor.paragraph(claim.defectDescription)

            let coverages = product.coverageList
            if !coverages.isEmpty {
                cursor.heading("Fristen")
                for coverage in coverages {
                    let end = coverage.endDate.map { df.string(from: $0) } ?? "offen"
                    var text = "\(df.string(from: coverage.startDate)) – \(end) (\(coverage.status.label))"
                    if !coverage.provider.isEmpty { text += ", \(coverage.provider)" }
                    cursor.row(coverage.kind.title, text)
                }
            }

            let events = product.eventList
            if !events.isEmpty {
                cursor.heading("Verlauf")
                for event in events.reversed() {
                    var text = event.title
                    if !event.details.isEmpty { text += ": \(event.details)" }
                    cursor.row(df.string(from: event.date), text)
                }
            }

            cursor.space(12)
            cursor.draw(LegalRules.disclaimer, font: .systemFont(ofSize: 9), color: .secondaryLabel)

            // Original receipts and product documents (warranty terms, repair invoices).
            let documents = (product.purchase?.receiptDocuments ?? []) + product.documentList.filter { $0.kind == .warrantyTerms || $0.kind == .repairInvoice }
            for document in documents {
                guard let data = document.originalData else { continue }
                let images = DocumentStore.pageImages(for: data, isPDF: document.isPDF, maxPixel: 2000)
                for (index, image) in images.enumerated() {
                    let caption = images.count > 1 ? "\(document.title) – Seite \(index + 1)" : document.title
                    cursor.imagePage(image, caption: caption)
                }
            }

            // Defect photos, two per page.
            let photos = claim.photos.compactMap { $0.originalData }.compactMap { DocumentStore.downsample(data: $0, maxPixel: 1600) }
            var i = 0
            while i < photos.count {
                cursor.newPage()
                cursor.draw("Fotos des Mangels", font: .systemFont(ofSize: 16, weight: .semibold))
                cursor.space(8)
                let available = pageSize.height - cursor.y - margin
                let slot = (available - 16) / 2
                for photo in photos[i..<min(i + 2, photos.count)] {
                    cursor.drawImage(photo, maxHeight: slot)
                    cursor.space(16)
                }
                i += 2
            }
        }
    }

    /// Saves the dossier as a document of the claim, replacing an older one.
    @MainActor
    static func attachDossier(to claim: Claim, context: ModelContext) throws -> StoredDocument {
        if let old = claim.dossier {
            context.delete(old)
        }
        let data = makePDF(claim: claim)
        let name = "Reklamation-\(claim.product?.name.replacingOccurrences(of: "/", with: "-") ?? "Produkt").pdf"
        let file = IncomingFile(data: data, filename: name, type: .pdf)
        let doc = try DocumentStore.makeDocument(from: file, kind: .claimDossier, title: "Reklamationsdossier", in: context)
        doc.claim = claim
        try context.save()
        return doc
    }
}

/// Simple top-to-bottom layout helper for PDF pages.
private struct PageCursor {
    let ctx: UIGraphicsPDFRendererContext
    var y: CGFloat = DossierService.margin
    var width: CGFloat { DossierService.pageSize.width - 2 * DossierService.margin }

    init(ctx: UIGraphicsPDFRendererContext) {
        self.ctx = ctx
    }

    mutating func newPage() {
        ctx.beginPage()
        y = DossierService.margin
    }

    mutating func ensure(_ height: CGFloat) {
        if y + height > DossierService.pageSize.height - DossierService.margin { newPage() }
    }

    mutating func space(_ h: CGFloat) { y += h }

    mutating func draw(_ text: String, font: UIFont, color: UIColor = .label, x: CGFloat = DossierService.margin, width: CGFloat? = nil) {
        guard !text.isEmpty else { return }
        let w = width ?? self.width
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = (text as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        ensure(rect.height)
        (text as NSString).draw(with: CGRect(x: x, y: y, width: w, height: rect.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        y += ceil(rect.height) + 2
    }

    mutating func heading(_ text: String) {
        space(10)
        ensure(40)
        draw(text, font: .systemFont(ofSize: 15, weight: .semibold))
        let path = UIBezierPath()
        path.move(to: CGPoint(x: DossierService.margin, y: y))
        path.addLine(to: CGPoint(x: DossierService.margin + width, y: y))
        UIColor.separator.setStroke()
        path.stroke()
        space(6)
    }

    mutating func row(_ label: String, _ value: String) {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let labelWidth: CGFloat = 150
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let valueRect = (value as NSString).boundingRect(with: CGSize(width: width - labelWidth, height: .greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        ensure(valueRect.height)
        let startY = y
        (label as NSString).draw(in: CGRect(x: DossierService.margin, y: y, width: labelWidth - 8, height: 40),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.secondaryLabel])
        (value as NSString).draw(with: CGRect(x: DossierService.margin + labelWidth, y: startY, width: width - labelWidth, height: valueRect.height),
                                 options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        y = startY + max(ceil(valueRect.height), 14) + 4
    }

    mutating func paragraph(_ text: String) {
        space(4)
        draw(text, font: .systemFont(ofSize: 11))
    }

    mutating func drawImage(_ image: UIImage, maxHeight: CGFloat) {
        let scale = min(width / image.size.width, maxHeight / image.size.height, 1.5)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensure(size.height)
        image.draw(in: CGRect(x: DossierService.margin + (width - size.width) / 2, y: y, width: size.width, height: size.height))
        y += size.height
    }

    mutating func imagePage(_ image: UIImage, caption: String) {
        newPage()
        draw(caption, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabel)
        space(6)
        drawImage(image, maxHeight: DossierService.pageSize.height - y - DossierService.margin)
    }
}
