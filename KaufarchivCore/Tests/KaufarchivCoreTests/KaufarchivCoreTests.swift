import XCTest
@testable import KaufarchivCore

final class KaufarchivCoreTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

    /// Baut Belegzeilen mit künstlichen Fundstellen; die erste Zeile ist grösser (Logo/Kopfzeile).
    private func lines(_ texts: [String]) -> [TextLine] {
        texts.enumerated().map { index, text in
            TextLine(
                text: text,
                box: NormRect(x: 0.05, y: 0.05 + Double(index) * 0.03, width: 0.9, height: index == 0 ? 0.04 : 0.02)
            )
        }
    }

    // MARK: Beträge

    func testAmountFormats() {
        XCTAssertEqual(AmountParser.amounts(in: "Preis 1'299.00").map(\.value), [dec("1299")])
        XCTAssertEqual(AmountParser.amounts(in: "Summe 1.299,00").map(\.value), [dec("1299")])
        XCTAssertEqual(AmountParser.amounts(in: "49,90 €").map(\.value), [dec("49.9")])
        XCTAssertEqual(AmountParser.amounts(in: "Stuhl 399.–").map(\.value), [dec("399")])
        XCTAssertEqual(AmountParser.amounts(in: "Rabatt -5.00").map(\.value), [dec("-5")])
        XCTAssertEqual(AmountParser.amounts(in: "Rabatt 5.00-").map(\.value), [dec("-5")])
    }

    func testAmountIgnoresDatesPercentagesAndQuantities() {
        XCTAssertTrue(AmountParser.amounts(in: "Datum 12.05.2024 14:35").isEmpty)
        XCTAssertTrue(AmountParser.amounts(in: "MwSt 8.10 %").isEmpty)
        // Menge und Preis dürfen nicht zu «2199.00» verschmelzen.
        XCTAssertEqual(AmountParser.amounts(in: "2 199.00").map(\.value), [dec("199")])
    }

    func testDecimalFromUserInput() {
        XCTAssertEqual(AmountParser.decimal(from: "1'299.50"), dec("1299.5"))
        XCTAssertEqual(AmountParser.decimal(from: "59,9"), dec("59.9"))
        XCTAssertEqual(AmountParser.decimal(from: "1299"), dec("1299"))
        XCTAssertNil(AmountParser.decimal(from: "abc"))
    }

    // MARK: Datum

    func testDateFormats() {
        let expected = date(2024, 5, 12)
        XCTAssertEqual(DateParser.dates(in: "12.05.2024", calendar: calendar).first?.date, expected)
        XCTAssertEqual(DateParser.dates(in: "12.05.24", calendar: calendar).first?.date, expected)
        XCTAssertEqual(DateParser.dates(in: "2024-05-12", calendar: calendar).first?.date, expected)
        XCTAssertEqual(DateParser.dates(in: "12. Mai 2024", calendar: calendar).first?.date, expected)
        XCTAssertEqual(DateParser.dates(in: "May 12, 2024", calendar: calendar).first?.date, expected)
        XCTAssertEqual(DateParser.dates(in: "3 février 2024", calendar: calendar).first?.date, date(2024, 2, 3))
        XCTAssertTrue(DateParser.dates(in: "31.02.2024", calendar: calendar).isEmpty)
    }

    // MARK: Belege

    func testCashReceiptDoesNotUseCashOrChangeAsTotal() {
        let draft = ReceiptParser.parse(lines: lines([
            "Elektro Muster AG",
            "Bahnhofstrasse 1, 8000 Zürich",
            "Datum: 12.05.2024 14:35",
            "Kaffeemaschine DeLonghi  399.00",
            "HDMI Kabel 2 x 9.95  19.90",
            "Total CHF  418.90",
            "Bar gegeben  500.00",
            "Rückgeld  81.10",
            "inkl. 8.1% MwSt  31.39"
        ]), now: date(2024, 6, 1), calendar: calendar)

        XCTAssertEqual(draft.merchant?.value, "Elektro Muster AG")
        XCTAssertEqual(draft.merchant?.lineIndex, 0)
        XCTAssertEqual(draft.purchaseDate?.value, date(2024, 5, 12))
        XCTAssertEqual(draft.purchaseDate?.confidence, .high)
        XCTAssertEqual(draft.total?.value, dec("418.90"))
        XCTAssertEqual(draft.total?.confidence, .high)
        XCTAssertEqual(draft.total?.lineIndex, 5)
        XCTAssertEqual(draft.cashGiven, dec("500"))
        XCTAssertEqual(draft.change, dec("81.10"))
        XCTAssertEqual(draft.currency, "CHF")
        XCTAssertFalse(draft.isOnlineOrder)

        XCTAssertEqual(draft.items.map(\.name), ["Kaffeemaschine DeLonghi", "HDMI Kabel"])
        XCTAssertEqual(draft.items.map(\.quantity), [1, 2])
        XCTAssertEqual(draft.items[1].unitPrice, dec("9.95"))
        XCTAssertEqual(draft.items[1].totalPrice, dec("19.90"))
        XCTAssertEqual(draft.items.map(\.lineIndex), [3, 4])
    }

    func testOnlineInvoiceWithSeveralProducts() {
        let draft = ReceiptParser.parse(lines: lines([
            "Digitec Galaxus AG",
            "Rechnung Nr. 2024-00123",
            "Bestelldatum: 03.02.2024",
            "Lieferadresse: Max Muster",
            "Pos Artikel Menge Preis",
            "Laptop Lenovo ThinkPad T14",
            "1 x 1.299,00  1.299,00",
            "Monitor Dell U2723QE  549,00",
            "Kopfhörer Sony WH-1000XM5  329,00",
            "Zwischensumme  2.177,00",
            "Versandkosten  0,00",
            "Gesamtbetrag EUR  2.177,00",
            "Zahlung: Kreditkarte"
        ]), now: date(2024, 6, 1), calendar: calendar)

        XCTAssertEqual(draft.merchant?.value, "Digitec")
        XCTAssertEqual(draft.merchant?.confidence, .high)
        XCTAssertEqual(draft.orderNumber?.value, "2024-00123")
        XCTAssertEqual(draft.purchaseDate?.value, date(2024, 2, 3))
        XCTAssertEqual(draft.total?.value, dec("2177"))
        XCTAssertEqual(draft.total?.lineIndex, 11)
        XCTAssertEqual(draft.currency, "EUR")
        XCTAssertTrue(draft.isOnlineOrder)

        XCTAssertEqual(draft.items.map(\.name), [
            "Laptop Lenovo ThinkPad T14", "Monitor Dell U2723QE", "Kopfhörer Sony WH-1000XM5"
        ])
        XCTAssertEqual(draft.items.map(\.totalPrice), [dec("1299"), dec("549"), dec("329")])
        // Zweizeilige Position: Fundstelle ist die Zeile mit der Bezeichnung.
        XCTAssertEqual(draft.items[0].lineIndex, 5)
        XCTAssertEqual(draft.items[0].confidence, .medium)
    }

    func testDiscountReducesPreviousItem() {
        let draft = ReceiptParser.parse(lines: lines([
            "Coop",
            "Toaster Philips  49.90",
            "Rabatt 20%  -9.98",
            "Summe  39.92"
        ]), now: date(2024, 6, 1), calendar: calendar)

        XCTAssertEqual(draft.merchant?.value, "Coop")
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.totalPrice, dec("39.92"))
        XCTAssertEqual(draft.total?.value, dec("39.92"))
        XCTAssertEqual(draft.total?.confidence, .high)
    }

    func testMissingTotalIsOnlyALowConfidenceSuggestion() {
        let draft = ReceiptParser.parse(lines: lines([
            "Velo Werkstatt Huber",
            "Fahrradhelm Giro  89.00",
            "Veloschloss Abus  45.50"
        ]), now: date(2024, 6, 1), calendar: calendar)

        XCTAssertEqual(draft.items.count, 2)
        XCTAssertEqual(draft.total?.value, dec("134.50"))
        XCTAssertEqual(draft.total?.confidence, .low)
        XCTAssertNil(draft.purchaseDate)
    }

    func testProductLineIsNotMistakenForMerchant() {
        let draft = ReceiptParser.parse(lines: lines([
            "Elektrohaus Meier",
            "Apple iPad Air  599.00",
            "Total  599.00"
        ]), now: date(2024, 6, 1), calendar: calendar)
        XCTAssertEqual(draft.merchant?.value, "Elektrohaus Meier")
        XCTAssertEqual(draft.items.map(\.name), ["Apple iPad Air"])
    }

    func testSerialNumberDetection() {
        let draft = ReceiptParser.parse(lines: lines([
            "Fust",
            "Staubsauger Dyson V15  699.00",
            "S/N: DY4-EU-KJA1234A",
            "Total  699.00"
        ]), now: date(2024, 6, 1), calendar: calendar)
        XCTAssertEqual(draft.serialNumbers.first?.value, "DY4-EU-KJA1234A")
    }

    func testLayoutReconstructionJoinsNameAndPrice() {
        let fragments = [
            TextLine(text: "49.90", box: NormRect(x: 0.8, y: 0.101, width: 0.1, height: 0.02)),
            TextLine(text: "Toaster", box: NormRect(x: 0.1, y: 0.1, width: 0.3, height: 0.02)),
            TextLine(text: "Total", box: NormRect(x: 0.1, y: 0.2, width: 0.2, height: 0.02))
        ]
        let rows = LayoutReconstructor.rows(from: fragments)
        XCTAssertEqual(rows.map(\.text), ["Toaster  49.90", "Total"])
    }

    // MARK: Fristen

    func testSwitzerlandHasNoGeneralWithdrawalRight() {
        let start = date(2024, 1, 15)
        let suggestions = DeadlineRules.suggestions(countryCode: "CH", channel: .online, purchaseDate: start, calendar: calendar)
        XCTAssertEqual(suggestions.map(\.kind), [.legal])
        XCTAssertEqual(suggestions.first?.endDate, date(2026, 1, 15))
    }

    func testGermanyOnlineSuggestsWithdrawalAndLegalRights() {
        let start = date(2024, 1, 15)
        let suggestions = DeadlineRules.suggestions(countryCode: "DE", channel: .online, purchaseDate: start, calendar: calendar)
        XCTAssertEqual(suggestions.map(\.kind), [.returnWindow, .legal])
        XCTAssertEqual(suggestions.first?.endDate, date(2024, 1, 29))

        let store = DeadlineRules.suggestions(countryCode: "DE", channel: .store, purchaseDate: start, calendar: calendar)
        XCTAssertEqual(store.map(\.kind), [.legal])
    }

    func testPortugalUsesThreeYears() {
        let suggestions = DeadlineRules.suggestions(countryCode: "PT", channel: .store, purchaseDate: date(2024, 1, 15), calendar: calendar)
        XCTAssertEqual(suggestions.first?.months, 36)
        XCTAssertEqual(suggestions.first?.endDate, date(2027, 1, 15))
    }

    // MARK: Erinnerungen

    func testReminderPlanRespectsSystemLimitAndReportsDeferred() {
        let now = date(2024, 6, 1, hour: 8)
        let deadlines = (0..<40).map { index in
            DeadlineInput(
                id: "d\(index)", productName: "Produkt \(index)", kind: .legal,
                endDate: calendar.date(byAdding: .day, value: 40 + index, to: date(2024, 6, 1))!
            )
        }
        let plan = ReminderPlanner.plan(
            deadlines: deadlines, leadDays: [.legal: [30, 7]], now: now, hour: 9, limit: 60, calendar: calendar
        )
        XCTAssertEqual(plan.scheduled.count, 60)
        XCTAssertEqual(plan.deferred.count, 20)
        XCTAssertEqual(Set(plan.scheduled.map(\.id)).count, 60)
        XCTAssertEqual(plan.scheduled.map(\.fireDate), plan.scheduled.map(\.fireDate).sorted())
        if let lastScheduled = plan.scheduled.last, let firstDeferred = plan.deferred.first {
            XCTAssertLessThanOrEqual(lastScheduled.fireDate, firstDeferred.fireDate)
        }
    }

    func testReminderPlanSkipsPastDates() {
        let now = date(2024, 6, 1)
        let plan = ReminderPlanner.plan(
            deadlines: [
                DeadlineInput(id: "old", productName: "Alt", kind: .legal, endDate: date(2024, 5, 1)),
                DeadlineInput(id: "soon", productName: "Bald", kind: .returnWindow, endDate: date(2024, 6, 3))
            ],
            leadDays: [.legal: [30, 7], .returnWindow: [3, 1]],
            now: now, calendar: calendar
        )
        // «3 Tage vorher» läge in der Vergangenheit; nur «1 Tag vorher» bleibt.
        XCTAssertEqual(plan.scheduled.map(\.id), ["kaufarchiv.reminder.soon.1"])
        XCTAssertEqual(plan.scheduled.first?.fireDate, date(2024, 6, 2, hour: 9))
    }

    // MARK: Reklamation und Export

    func testClaimDraftContainsKeyFacts() {
        let context = ClaimContext(
            productName: "Kaffeemaschine", brand: "DeLonghi", model: "Magnifica S", serialNumber: "SN12345",
            merchant: "Fust", purchaseDate: date(2024, 5, 12), orderNumber: "A-77", issue: "Pumpe zieht kein Wasser mehr.",
            remedy: .repair, coverage: .legal, senderName: "Max Muster", attachmentCount: 1
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd.MM.yyyy"
        let body = ClaimComposer.body(context, dateFormatter: formatter)
        XCTAssertTrue(body.contains("am 12.05.2024 bei Fust gekauft"))
        XCTAssertTrue(body.contains("Seriennummer: SN12345"))
        XCTAssertTrue(body.contains("Pumpe zieht kein Wasser mehr."))
        XCTAssertTrue(body.contains("kostenlose Reparatur"))
        XCTAssertEqual(ClaimComposer.subject(context), "Reklamation: Kaffeemaschine (Bestellung A-77)")
    }

    func testReturnDraftDoesNotClaimADefect() {
        let context = ClaimContext(
            productName: "Kopfhörer", merchant: "Galaxus", purchaseDate: date(2024, 5, 12), orderNumber: "B-9",
            issue: "", senderName: "Max Muster", attachmentCount: 1, isReturn: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd.MM.yyyy"
        let body = ClaimComposer.body(context, dateFormatter: formatter)
        XCTAssertTrue(body.contains("ich möchte folgendes Produkt zurückgeben, das ich am 12.05.2024 bei Galaxus gekauft habe"))
        XCTAssertFalse(body.contains("Mangel"))
        XCTAssertEqual(ClaimComposer.subject(context), "Rückgabe: Kopfhörer (Bestellung B-9)")
    }

    func testReminderTextCanHideProductNames() {
        let plan = ReminderPlanner.plan(
            deadlines: [DeadlineInput(id: "x", productName: "Kaffeemaschine", kind: .legal, endDate: date(2024, 8, 1))],
            leadDays: [.legal: [7]], now: date(2024, 6, 1), showProductNames: false, calendar: calendar
        )
        XCTAssertEqual(plan.scheduled.count, 1)
        XCTAssertFalse(plan.scheduled[0].body.contains("Kaffeemaschine"))
    }

    func testCSVEscaping() {
        XCTAssertEqual(CSVBuilder.row(["a", "b;c", "d\"e"]), "a;\"b;c\";\"d\"\"e\"")
    }
}
