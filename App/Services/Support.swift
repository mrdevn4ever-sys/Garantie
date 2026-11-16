import Foundation
import SwiftData
import CryptoKit
import KaufarchivCore

/// Schlüssel für einfache Einstellungen (UserDefaults / @AppStorage).
enum Prefs {
    static let didOnboard = "didOnboard"
    static let countryCode = "defaultCountryCode"
    static let currency = "defaultCurrency"
    static let returnLeadDays = "returnLeadDays"
    static let warrantyLeadDays = "warrantyLeadDays"
    static let reminderHour = "reminderHour"
    static let iCloudEnabled = "iCloudSyncEnabled"
    static let proCache = "proEntitlementCache"
    static let debugPro = "debugProOverride"
    static let appLockEnabled = "appLockEnabled"
    static let senderName = "senderName"
    static let hideNamesInReminders = "hideNamesInReminders"

    static let freeProductLimit = 10

    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        let region = Locale.current.region?.identifier ?? "CH"
        let known = DeadlineRules.countries.map { $0.code }
        defaults.register(defaults: [
            countryCode: known.contains(region) ? region : "CH",
            currency: Locale.current.currency?.identifier ?? "CHF",
            returnLeadDays: 3,
            warrantyLeadDays: 30,
            reminderHour: 9
        ])
    }

    static var leadDays: [CoverageKind: [Int]] {
        let returnLead = max(defaults.integer(forKey: returnLeadDays), 1)
        let warrantyLead = max(defaults.integer(forKey: warrantyLeadDays), 1)
        return [
            .returnWindow: [returnLead, 1],
            .legal: [warrantyLead, 7],
            .manufacturer: [warrantyLead, 7],
            .extended: [warrantyLead, 7]
        ]
    }
}

enum Money {
    static func cents(from decimal: Decimal) -> Int {
        Int((NSDecimalNumber(decimal: decimal).doubleValue * 100).rounded())
    }

    static func cents(fromText text: String) -> Int? {
        guard let decimal = AmountParser.decimal(from: text) else { return nil }
        return cents(from: decimal)
    }

    static func decimal(cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    static func format(cents: Int?, currency: String) -> String {
        guard let cents else { return "–" }
        return decimal(cents: cents).formatted(.currency(code: currency))
    }

    /// Eingabetext ohne Währung, z. B. «399.00».
    static func plainText(cents: Int?) -> String {
        guard let cents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }
}

enum Fmt {
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
    }

    static func remaining(days: Int) -> String {
        switch days {
        case 0: return "endet heute"
        case 1: return "noch 1 Tag"
        case 2...60: return "noch \(days) Tage"
        case 61...: 
            let months = days / 30
            return months >= 24 ? "noch \(months / 12) Jahre" : "noch \(months) Monate"
        case -1: return "seit gestern abgelaufen"
        default: return "abgelaufen"
        }
    }

    static func fileStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: date)
    }
}

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum TempFiles {
    /// Schreibt Daten in einen eigenen temporären Ordner und liefert die URL (für Vorschau und Teilen).
    static func write(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kaufarchiv", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(safeName(name))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func safeName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Datei" : cleaned
    }

    static func cleanUp() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Kaufarchiv", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}

enum DataController {
    /// `true`, wenn der dauerhafte Speicher nicht geöffnet werden konnte und nur im Arbeitsspeicher gearbeitet wird.
    static var isTemporaryStore = false

    /// Erstellt den Datenspeicher. iCloud wird nur verwendet, wenn Pro aktiv ist und der Schalter eingeschaltet wurde.
    /// Schlägt die iCloud-Einrichtung fehl, bleibt die App mit dem lokalen Speicher voll benutzbar.
    static func makeContainer() -> (container: ModelContainer, usesCloud: Bool) {
        let schema = Schema(AppSchema.models)
        let wantsCloud = Prefs.defaults.bool(forKey: Prefs.iCloudEnabled)
            && (Prefs.defaults.bool(forKey: Prefs.proCache) || Prefs.defaults.bool(forKey: Prefs.debugPro))

        if wantsCloud {
            let cloud = ModelConfiguration("Kaufarchiv", schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return (container, true)
            }
        }
        let local = ModelConfiguration("Kaufarchiv", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return (container, false)
        }
        // Letzter Ausweg, damit die App startet und der Fehler sichtbar wird, statt abzustürzen.
        let memory = ModelConfiguration("KaufarchivFallback", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        isTemporaryStore = true
        do {
            return (try ModelContainer(for: schema, configurations: [memory]), false)
        } catch {
            fatalError("Datenspeicher konnte nicht erstellt werden: \(error)")
        }
    }
}
