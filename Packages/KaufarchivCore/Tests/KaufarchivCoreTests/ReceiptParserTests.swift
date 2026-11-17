import XCTest
@testable import KaufarchivCore

final class ReceiptParserTests: XCTestCase {
    let parser = ReceiptParser(now: DateParser.make(year: 2026, month: 11, day: 17)!)

    func testCashReceiptDoesNotPickCashGivenOrChange() {
        let text = """
        Elektro Muster AG
        Bahnhofstrasse 1, 8001 Zürich
        Datum 14.11.2026 10:22
        Kaffeemaschine Barista 2000   349.00
        Entkalker                      14.90
        Total CHF                     363.90
        Bar                           400.00
        Rückgeld                       36.10
        MwSt 8.1% inkl.                27.23
        """
        let r = parser.parse(text: text)
        XCTAssertEqual(r.total?.value, Decimal(string: "363.90"))
        XCTAssertEqual(r.total?.certainty, .certain)
        XCTAssertEqual(r.currency?.value, "CHF")
        XCTAssertEqual(r.merchant?.value, "Elektro Muster AG")
        XCTAssertEqual(r.purchaseDate?.value, DateParser.make(year: 2026, month: 11, day: 14))
        XCTAssertEqual(r.items.map(\.name), ["Kaffeemaschine Barista 2000", "Entkalker"])
        XCTAssertEqual(r.countryCode?.value, "CH")
        XCTAssertEqual(r.channel?.value, .store)
    }

    func testMultipleProductsAndDiscount() {
        let text = """
        TechShop GmbH
        Rechnung Nr. R-2026-1182
        Rechnungsdatum: 02.10.2026
        1 x Laptop ProBook 14  S/N: 5CD12345XY   1'299.00
        1 x Monitor 27" 4K                         399.00
        2 x Kopfhörer Studio                       258.00
        Versandkosten                                9.90
        Rabatt                                     -50.00
        Zwischensumme                            1'915.90
        Total zu bezahlen CHF                    1'915.90
        Visa                                     1'915.90
        2 Jahre Herstellergarantie
        Umtausch innert 30 Tagen
        """
        let r = parser.parse(text: text)
        XCTAssertEqual(r.total?.value, Decimal(string: "1915.90"))
        XCTAssertEqual(r.total?.certainty, .certain)
        XCTAssertEqual(r.items.count, 4)
        XCTAssertEqual(r.items[2].quantity, 2)
        XCTAssertEqual(r.items[2].unitPrice, Decimal(129))
        XCTAssertTrue(r.items[3].looksLikeService)
        XCTAssertEqual(r.serialNumbers.first?.value, "5CD12345XY")
        XCTAssertEqual(r.orderNumber?.value, "R-2026-1182")
        XCTAssertEqual(r.manufacturerWarrantyMonths?.value, 24)
        XCTAssertEqual(r.returnWindowDays?.value, 30)
        XCTAssertEqual(r.purchaseDate?.certainty, .certain)
    }

    func testDepositIsNotTotal() {
        let text = """
        Möbelhaus Beispiel
        12.09.2026
        Sofa Lounge 3-Sitzer           1'890.00
        Total                          1'890.00
        Anzahlung                        500.00
        Restbetrag                     1'390.00
        """
        let r = parser.parse(text: text)
        XCTAssertEqual(r.total?.value, Decimal(1890))
    }

    func testOnlineOrderInEuro() {
        let text = """
        Bestellbestätigung
        Shop Online GmbH
        Bestellnummer: 302-1234567
        Bestelldatum: 5. Oktober 2026
        Akkuschrauber 18V      89,99 €
        Versand                 4,99 €
        Gesamtbetrag           94,98 €
        Deutschland
        """
        let r = parser.parse(text: text)
        XCTAssertEqual(r.currency?.value, "EUR")
        XCTAssertEqual(r.total?.value, Decimal(string: "94.98"))
        XCTAssertEqual(r.channel?.value, .online)
        XCTAssertEqual(r.countryCode?.value, "DE")
        XCTAssertEqual(r.merchant?.value, "Shop Online GmbH")
        XCTAssertEqual(r.orderNumber?.value, "302-1234567")
    }

    func testEveryValueIsTraceable() {
        let r = parser.parse(text: "Laden\n01.11.2026\nArtikel 10.00\nTotal 10.00")
        XCTAssertEqual(r.total?.source?.excerpt, "Total 10.00")
        XCTAssertEqual(r.purchaseDate?.source?.lineIndex, 1)
        XCTAssertEqual(r.items.first?.source.lineIndex, 2)
    }
}
