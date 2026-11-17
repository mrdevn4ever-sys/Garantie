import Foundation
import KaufarchivCore

enum Formatters {
    static let locale = Locale(identifier: "de_CH")

    static func money(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency).locale(locale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.twoDigits).year().locale(locale))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func countryName(_ code: String) -> String {
        LegalRules.rules(for: code).name
    }
}
