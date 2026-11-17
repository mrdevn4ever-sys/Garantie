import XCTest
import SwiftData
import UIKit
import PDFKit
import KaufarchivCore
@testable import Kaufarchiv

@MainActor
final class KaufarchivTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = Persistence.makeContainer(inMemory: true)
    }

    private func sampleImage() -> IncomingFile {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            ("Elektro Muster AG\nTotal CHF 349.00" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return IncomingFile(data: image.pngData()!, filename: "beleg.png", type: .png)
    }

    func testDraftSavesOneProductPerSelectedItemWithSharedReceipt() throws {
        let draft = ImportDraft(defaultCountry: "CH")
        draft.files = [sampleImage()]
        draft.linesPerFile = [[]]
        draft.pageCounts = [1]
        draft.apply(ReceiptParser().parse(text: """
        Elektro Muster AG
        Datum 14.11.2026
        Laptop 1'299.00
        Monitor 399.00
        Versand 9.90
        Total CHF 1'707.90
        """))
        XCTAssertEqual(draft.items.count, 3)
        XCTAssertEqual(draft.selectedItems.count, 2, "Shipping fee must not be preselected")

        let purchase = try draft.save(in: context)
        XCTAssertEqual(purchase.productList.count, 2)
        XCTAssertEqual(purchase.receiptDocuments.count, 1)
        for product in purchase.productList {
            XCTAssertTrue(product.coverageList.contains { $0.kind == .statutory })
            XCTAssertFalse(product.coverageList.contains { $0.kind == .withdrawal }, "No withdrawal right in Switzerland")
            XCTAssertEqual(product.allDocuments.first?.id, purchase.receiptDocuments.first?.id)
        }
    }

    func testOriginalIsKeptBitExactWithChecksum() throws {
        let file = sampleImage()
        let doc = try DocumentStore.makeDocument(from: file, kind: .receipt, in: context)
        XCTAssertEqual(doc.originalData, file.data)
        XCTAssertTrue(DocumentStore.verify(doc))
        XCTAssertNotNil(doc.thumbnail)
        XCTAssertNotEqual(doc.thumbnail, file.data, "Preview is stored separately from the original")
    }

    func testBackupRoundTripRestoresEverything() throws {
        let draft = ImportDraft(defaultCountry: "DE")
        draft.files = [sampleImage()]
        draft.linesPerFile = [[]]
        draft.pageCounts = [1]
        draft.apply(ReceiptParser().parse(text: "Shop\nAkkuschrauber 89,99 €\nGesamtbetrag 89,99 €"))
        draft.channel = .online
        try draft.save(in: context)

        let package = try BackupService.makePackage(context: context)
        let check = try BackupService.verifyRoundTrip(context: context)
        XCTAssertEqual(check.documents, check.valid)

        let target = Persistence.makeContainer(inMemory: true)
        let report = try BackupService.restore(from: package.wrapper, into: target.mainContext)
        XCTAssertEqual(report.purchasesAdded, 1)
        XCTAssertEqual(report.productsAdded, 1)
        XCTAssertEqual(report.documentsAdded, 1)
        XCTAssertTrue(report.corruptedDocuments.isEmpty)

        let restored = try target.mainContext.fetch(FetchDescriptor<Product>())
        XCTAssertEqual(restored.first?.name, "Akkuschrauber")
        XCTAssertTrue(restored.first?.coverageList.contains { $0.kind == .withdrawal } ?? false)
        XCTAssertTrue(DocumentStore.verify(restored.first!.purchase!.receiptDocuments.first!))

        // Restoring twice does not duplicate data.
        let second = try BackupService.restore(from: package.wrapper, into: target.mainContext)
        XCTAssertEqual(second.purchasesAdded, 0)
        XCTAssertEqual(second.skippedExisting, 1)
    }

    func testDossierContainsReceiptPage() throws {
        let draft = ImportDraft(defaultCountry: "CH")
        draft.files = [sampleImage()]
        draft.linesPerFile = [[]]
        draft.pageCounts = [1]
        draft.items = [DraftItem(selected: true, name: "Kaffeemaschine")]
        let purchase = try draft.save(in: context)
        let product = try XCTUnwrap(purchase.productList.first)
        let claim = Claim(product: product)
        claim.defectDescription = "Pumpe fördert kein Wasser."
        context.insert(claim)
        claim.product = product
        let pdf = DossierService.makePDF(claim: claim)
        let document = try XCTUnwrap(PDFDocumentLoader.pageCount(pdf))
        XCTAssertGreaterThanOrEqual(document, 2, "Cover page plus receipt page")
    }
}

enum PDFDocumentLoader {
    static func pageCount(_ data: Data) -> Int? { PDFDocument(data: data)?.pageCount }
}
