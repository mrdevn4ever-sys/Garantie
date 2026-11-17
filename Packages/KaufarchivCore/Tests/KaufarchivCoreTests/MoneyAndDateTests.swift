import XCTest
@testable import KaufarchivCore

final class MoneyParserTests: XCTestCase {
    func testSwissNotation() {
        XCTAssertEqual(MoneyParser.parseAmount("1'234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(MoneyParser.parseAmount("1’234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(MoneyParser.parseAmount("29.–"), Decimal(29))
        XCTAssertEqual(MoneyParser.parseAmount("29.-"), Decimal(29))
    }

    func testGermanAndEnglishNotation() {
        XCTAssertEqual(MoneyParser.parseAmount("1.234,50"), Decimal(string: "1234.50"))
        XCTAssertEqual(MoneyParser.parseAmount("1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(MoneyParser.parseAmount("12,90"), Decimal(string: "12.90"))
        XCTAssertEqual(MoneyParser.parseAmount("-5.00"), Decimal(-5))
    }

    func testPriceAmountsIgnoresIntegers() {
        let amounts = MoneyParser.priceAmounts(in: "2 x Kabel 4711 19.90")
        XCTAssertEqual(amounts, [Decimal(string: "19.90")!])
    }

    func testQuantityNotMergedIntoPrice() {
        XCTAssertEqual(MoneyParser.priceAmounts(in: "2 199.00"), [Decimal(199)])
    }

    func testCurrencyDetection() {
        XCTAssertEqual(MoneyParser.detectCurrency(in: "Total CHF 12.00"), "CHF")
        XCTAssertEqual(MoneyParser.detectCurrency(in: "Summe 12,00 €"), "EUR")
        XCTAssertEqual(MoneyParser.detectCurrency(in: "Fr. 12.00"), "CHF")
        XCTAssertNil(MoneyParser.detectCurrency(in: "Merchandise 12.00"))
    }
}

final class DateParserTests: XCTestCase {
    let now = DateParser.make(year: 2026, month: 11, day: 17)!

    func testNumericDates() {
        let d = DateParser.dates(in: "Datum: 03.10.2026 14:12", now: now)
        XCTAssertEqual(d.first?.date, DateParser.make(year: 2026, month: 10, day: 3))
        XCTAssertEqual(DateParser.dates(in: "3/10/26", now: now).first?.date, DateParser.make(year: 2026, month: 10, day: 3))
    }

    func testIsoAndWrittenDates() {
        XCTAssertEqual(DateParser.dates(in: "2026-02-28", now: now).first?.date, DateParser.make(year: 2026, month: 2, day: 28))
        XCTAssertEqual(DateParser.dates(in: "Bestellt am 12. März 2025", now: now).first?.date, DateParser.make(year: 2025, month: 3, day: 12))
        XCTAssertEqual(DateParser.dates(in: "le 5 juillet 2024", now: now).first?.date, DateParser.make(year: 2024, month: 7, day: 5))
    }

    func testRejectsInvalidAndFutureDates() {
        XCTAssertTrue(DateParser.dates(in: "31.02.2026", now: now).isEmpty)
        XCTAssertTrue(DateParser.dates(in: "01.01.2030", now: now).isEmpty)
    }
}
