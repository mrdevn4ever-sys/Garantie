import Foundation
import UIKit
import PDFKit
import KaufarchivCore

/// Erstellt das Reklamationsdossier: Übersicht, Mangelbeschreibung, Verlauf, Fotos und alle Originalunterlagen in einem PDF.
@MainActor
enum DossierBuilder {
    private static let pageSize = CGSize(width: 595, height: 842) // A4
    private static let margin: CGFloat = 48

    static func build(claim: Claim) throws -> URL {
        let product = claim.product
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(claim.kind.label) \(product?.displayName ?? "")",
            kCGPDFContextCreator as String: "Kaufarchiv"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            var cursor: CGFloat = margin
            let contentWidth = pageSize.width - margin * 2

            func newPage() {
                context.beginPage(withBounds: pageRect, pageInfo: [:])
                cursor = margin
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat = 6) {
                guard !text.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph
                ])
                let bounding = attributed.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
                )
                let height = ceil(bounding.height)
                if cursor + height > pageSize.height - margin { newPage() }
                attributed.draw(with: CGRect(x: margin, y: cursor, width: contentWidth, height: height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                cursor += height + spacingAfter
            }

            func heading(_ text: String) {
                cursor += 10
                draw(text, font: .boldSystemFont(ofSize: 14), spacingAfter: 4)
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: cursor))
                line.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor))
                UIColor.lightGray.setStroke()
                line.lineWidth = 0.5
                line.stroke()
                cursor += 8
            }

            func row(_ label: String, _ value: String) {
                guard !value.isEmpty else { return }
                draw("\(label): \(value)", font: .systemFont(ofSize: 11), spacingAfter: 3)
            }

            func drawImagePage(_ image: UIImage, caption: String) {
                newPage()
                draw(caption, font: .systemFont(ofSize: 10), color: .darkGray, spacingAfter: 8)
                let available = CGRect(x: margin, y: cursor, width: contentWidth, height: pageSize.height - margin - cursor)
                let scale = min(available.width / max(image.size.width, 1), available.height / max(image.size.height, 1), 1.5)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: available.midX - size.width / 2, y: available.minY, width: size.width, height: size.height))
            }

            // Seite 1: Übersicht
            newPage()
            draw(claim.kind == .productReturn ? "Rückgabedossier" : "Reklamationsdossier", font: .boldSystemFont(ofSize: 22), spacingAfter: 2)
            draw("Erstellt am \(Fmt.date(Date())) mit Kaufarchiv", font: .systemFont(ofSize: 10), color: .darkGray, spacingAfter: 10)

            heading("Produkt")
            row("Bezeichnung", product?.displayName ?? "")
            row("Marke", product?.brand ?? "")
            row("Modell", product?.modelName ?? "")
            row("Seriennummer", product?.serialNumber ?? "")

            heading("Kauf")
            row("Händler", product?.receipt?.merchant ?? "")
            if let product { row("Kaufdatum", Fmt.date(product.purchaseDate)) }
            if let delivery = product?.receipt?.deliveryDate { row("Erhalten am", Fmt.date(delivery)) }
            row("Bestell-/Rechnungsnummer", product?.receipt?.orderNumber ?? "")
            if let product, let price = product.priceCents {
                row("Kaufpreis", Money.format(cents: price, currency: product.currency))
            }

            if let product, !product.coverageList.isEmpty {
                heading("Fristen")
                for coverage in product.coverageList {
                    var value = "bis \(Fmt.date(coverage.endDate))"
                    if !coverage.provider.isEmpty { value += " (\(coverage.provider))" }
                    if !coverage.isConfirmed { value += " – unbestätigter Vorschlag" }
                    row(coverage.kind.label, value)
                }
            }

            heading(claim.kind == .productReturn ? "Rückgabe" : "Mangel")
            row("Erfasst am", Fmt.date(claim.createdAt))
            row("Gewünschte Lösung", claim.remedy.label)
            row("Sendungsnummer", claim.trackingNumber)
            row("Status", claim.status.label)
            row("Kontakt", claim.contact)
            row("Vorgangsnummer", claim.reference)
            cursor += 4
            draw(claim.issue.isEmpty ? "Keine Beschreibung erfasst." : claim.issue, font: .systemFont(ofSize: 11))

            if !claim.eventList.isEmpty {
                heading("Verlauf")
                for event in claim.eventList {
                    draw("\(Fmt.date(event.date))  \(event.text)", font: .systemFont(ofSize: 11), spacingAfter: 3)
                }
            }

            if let product, !product.repairList.isEmpty {
                heading("Frühere Reparaturen")
                for repair in product.repairList {
                    var text = "\(Fmt.date(repair.date))  \(repair.summary)"
                    if !repair.provider.isEmpty { text += " – \(repair.provider)" }
                    draw(text, font: .systemFont(ofSize: 11), spacingAfter: 3)
                }
            }

            let attachments = claim.documentList + (product?.allDocuments ?? [])
            if !attachments.isEmpty {
                heading("Anhänge")
                for (index, document) in attachments.enumerated() {
                    draw("\(index + 1). \(document.displayTitle) – \(document.filename)", font: .systemFont(ofSize: 11), spacingAfter: 3)
                }
            }

            // Folgeseiten: Anhänge. PDFs werden als Vektorseiten übernommen, Bilder eingepasst.
            for (index, document) in attachments.enumerated() {
                guard let original = document.originalData else { continue }
                let caption = "Anhang \(index + 1): \(document.displayTitle)"
                if DocumentRenderer.isPDF(data: original, typeIdentifier: document.typeIdentifier),
                   let pdf = PDFDocument(data: original) {
                    for pageIndex in 0..<pdf.pageCount {
                        guard let page = pdf.page(at: pageIndex) else { continue }
                        let bounds = page.bounds(for: .mediaBox)
                        context.beginPage(withBounds: CGRect(origin: .zero, size: bounds.size), pageInfo: [:])
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: 0, y: bounds.height)
                        cg.scaleBy(x: 1, y: -1)
                        page.draw(with: .mediaBox, to: cg)
                        cg.restoreGState()
                    }
                } else if let image = UIImage(data: original) {
                    drawImagePage(image, caption: caption)
                }
            }
        }

        let name = "\(claim.kind.label) \(product?.displayName ?? "Produkt") \(Fmt.fileStamp()).pdf"
        return try TempFiles.write(data, name: name)
    }

    static func context(for claim: Claim, senderName: String, attachmentCount: Int) -> ClaimContext {
        let product = claim.product
        return ClaimContext(
            productName: product?.displayName ?? "Produkt",
            brand: product?.brand ?? "",
            model: product?.modelName ?? "",
            serialNumber: product?.serialNumber ?? "",
            merchant: product?.receipt?.merchant ?? "",
            purchaseDate: product?.receipt?.purchaseDate,
            orderNumber: product?.receipt?.orderNumber ?? "",
            issue: claim.issue,
            remedy: claim.remedy,
            coverage: product?.bestActiveCoverage(now: claim.createdAt)?.kind,
            senderName: senderName,
            attachmentCount: attachmentCount,
            isReturn: claim.kind == .productReturn
        )
    }
}
