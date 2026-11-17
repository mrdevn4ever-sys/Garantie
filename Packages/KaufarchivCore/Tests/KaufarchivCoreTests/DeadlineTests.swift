import XCTest
@testable import KaufarchivCore

final class DeadlineTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testSwissOnlinePurchaseHasNoWithdrawal() {
        let specs = DeadlineCalculator.defaultCoverages(purchaseDate: date(2026, 1, 10), countryCode: "CH", channel: .online, returnDays: nil, manufacturerMonths: nil)
        XCTAssertFalse(specs.contains { $0.kind == .withdrawal })
        XCTAssertEqual(specs.first { $0.kind == .statutory }?.months, 24)
    }

    func testGermanOnlinePurchaseHasWithdrawal() {
        let specs = DeadlineCalculator.defaultCoverages(purchaseDate: date(2026, 1, 10), deliveryDate: date(2026, 1, 13), countryCode: "DE", channel: .online, returnDays: 30, manufacturerMonths: 36)
        let withdrawal = specs.first { $0.kind == .withdrawal }!
        XCTAssertEqual(withdrawal.endDate(calendar: calendar), date(2026, 1, 27))
        XCTAssertNotNil(specs.first { $0.kind == .returnPolicy })
        XCTAssertEqual(specs.first { $0.kind == .manufacturer }?.months, 36)
    }

    func testPortugalUsesThreeYears() {
        XCTAssertEqual(LegalRules.rules(for: "PT").statutoryMonths, 36)
        XCTAssertNil(LegalRules.rules(for: "CH").onlineWithdrawalDays)
        XCTAssertEqual(LegalRules.rules(for: "zz").code, "XX")
    }

    func testStatus() {
        let now = date(2026, 11, 17)
        XCTAssertEqual(DeadlineCalculator.status(end: date(2026, 11, 17), kind: .returnPolicy, now: now, calendar: calendar), .endsToday)
        XCTAssertEqual(DeadlineCalculator.status(end: date(2026, 11, 20), kind: .returnPolicy, now: now, calendar: calendar), .soon(daysLeft: 3))
        XCTAssertEqual(DeadlineCalculator.status(end: date(2027, 11, 20), kind: .statutory, now: now, calendar: calendar), .active(daysLeft: 368))
        XCTAssertEqual(DeadlineCalculator.status(end: date(2026, 11, 10), kind: .statutory, now: now, calendar: calendar), .expired(daysAgo: 7))
    }

    func testReminderPlannerRespectsLimitAndReportsDeferred() {
        let now = date(2026, 11, 17)
        var candidates: [ReminderCandidate] = []
        for i in 0..<40 {
            candidates += ReminderPlanner.candidates(productID: "p\(i)", productName: "Produkt \(i)",
                                                     coverages: [(.statutory, date(2027, 1, 1 + i % 28), [30, 7])],
                                                     calendar: calendar)
        }
        XCTAssertEqual(candidates.count, 80)
        let plan = ReminderPlanner.plan(candidates, now: now)
        XCTAssertEqual(plan.scheduled.count, 62)
        XCTAssertEqual(plan.deferred.count, 18)
        XCTAssertNotNil(plan.openAppBefore)
        XCTAssertTrue(plan.scheduled.allSatisfy { s in plan.deferred.allSatisfy { s.fireDate <= $0.fireDate } })
    }

    func testMissedReminders() {
        let now = date(2026, 11, 17)
        let c = ReminderPlanner.candidates(productID: "x", productName: "X", coverages: [(.returnPolicy, date(2026, 11, 19), [3, 1])], calendar: calendar)
        let plan = ReminderPlanner.plan(c, now: now)
        XCTAssertEqual(plan.missed.count, 1)
        XCTAssertEqual(plan.scheduled.count, 1)
    }

    func testSearchNormalizer() {
        XCTAssertTrue(SearchNormalizer.matches(query: "kaffee", in: "Kaffeemaschine Barista"))
        XCTAssertTrue(SearchNormalizer.matches(query: "cafe maschine", in: "Café-Maschine"))
        XCTAssertTrue(SearchNormalizer.matches(query: "strasse", in: "Hauptstraße"))
        XCTAssertFalse(SearchNormalizer.matches(query: "laptop", in: "Monitor"))
    }

    func testEntitlements() {
        XCTAssertTrue(Entitlements.canAddProducts(existing: 9, adding: 1, isPro: false))
        XCTAssertFalse(Entitlements.canAddProducts(existing: 10, adding: 1, isPro: false))
        XCTAssertTrue(Entitlements.canAddProducts(existing: 500, adding: 3, isPro: true))
    }

    func testClaimTemplate() {
        let ctx = ClaimContext(productName: "Kaffeemaschine", brand: "Muster", model: "B2000", serialNumber: "SN123", merchant: "Elektro Muster AG",
                               purchaseDate: date(2026, 1, 5), price: "CHF 349.00", orderNumber: nil, defectDescription: "Pumpe fördert kein Wasser.",
                               defectNoticedOn: date(2026, 11, 15), requestedRemedy: .repair, coverage: .statutory, coverageEnd: date(2028, 1, 5),
                               customerName: "Alex", attachments: ["Rechnung", "Foto 1"])
        XCTAssertEqual(ClaimTemplate.subject(ctx), "Reklamation: Kaffeemaschine (S/N SN123)")
        let body = ClaimTemplate.body(ctx)
        XCTAssertTrue(body.contains("Seriennummer: SN123"))
        XCTAssertTrue(body.contains("Gesetzliche Gewährleistung"))
        XCTAssertTrue(body.contains("• Foto 1"))
    }
}
