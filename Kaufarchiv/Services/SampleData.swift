import Foundation
import SwiftData
import KaufarchivCore

/// Demo content for SwiftUI previews and screenshots (never inserted in the real store).
enum SampleData {
    @MainActor
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: Date())! }

        let shop = Purchase(merchant: "Elektro Muster AG", purchaseDate: daysAgo(20))
        shop.totalAmount = 1957.90
        shop.orderNumber = "R-2026-1182"
        context.insert(shop)

        let items: [(String, String, String, Decimal, Int?)] = [
            ("Laptop ProBook 14", "HP", "5CD12345XY", 1299, 24),
            ("Monitor 27\" 4K", "Dell", "CN0X1234", 399, 36),
            ("Kopfhörer Studio", "Sony", "", 259.90, nil)
        ]
        for (name, brand, serial, price, manufacturer) in items {
            let product = Product(name: name)
            product.brand = brand
            product.serialNumber = serial
            product.price = price
            context.insert(product)
            product.purchase = shop
            let specs = DeadlineCalculator.defaultCoverages(purchaseDate: shop.purchaseDate, countryCode: "CH", channel: .store, returnDays: 30, manufacturerMonths: manufacturer)
            for spec in specs {
                let coverage = Coverage(kind: spec.kind, start: spec.start, months: spec.months, days: spec.days)
                context.insert(coverage)
                coverage.product = product
            }
        }

        let coffee = Purchase(merchant: "Haushalt & Co", purchaseDate: daysAgo(400))
        coffee.totalAmount = 349
        context.insert(coffee)
        let machine = Product(name: "Kaffeemaschine Barista 2000")
        machine.brand = "Muster"
        machine.room = "Küche"
        machine.price = 349
        context.insert(machine)
        machine.purchase = coffee
        let statutory = Coverage(kind: .statutory, start: coffee.purchaseDate, months: 24)
        context.insert(statutory)
        statutory.product = machine
    }
}
