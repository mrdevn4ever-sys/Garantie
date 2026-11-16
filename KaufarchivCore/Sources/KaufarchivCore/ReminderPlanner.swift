import Foundation

public struct DeadlineInput: Equatable, Sendable {
    public var id: String
    public var productName: String
    public var kind: CoverageKind
    public var endDate: Date

    public init(id: String, productName: String, kind: CoverageKind, endDate: Date) {
        self.id = id
        self.productName = productName
        self.kind = kind
        self.endDate = endDate
    }
}

public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public var id: String
    public var deadlineID: String
    public var fireDate: Date
    public var daysBefore: Int
    public var title: String
    public var body: String
}

public struct ReminderPlan: Equatable, Sendable {
    /// Diese Erinnerungen passen in das Systemlimit und werden tatsächlich eingeplant.
    public var scheduled: [PlannedReminder]
    /// Diese liegen weiter in der Zukunft und werden erst beim nächsten Öffnen der App eingeplant.
    public var deferred: [PlannedReminder]
}

/// Plant lokale Erinnerungen. iOS erlaubt höchstens 64 ausstehende lokale Mitteilungen pro App;
/// deshalb werden immer die zeitlich nächsten eingeplant und der Rest ehrlich als «später» ausgewiesen.
public enum ReminderPlanner {
    public static let systemLimit = 64
    public static let identifierPrefix = "kaufarchiv.reminder."

    public static func plan(
        deadlines: [DeadlineInput],
        leadDays: [CoverageKind: [Int]],
        now: Date,
        hour: Int = 9,
        limit: Int = 60,
        showProductNames: Bool = true,
        calendar: Calendar = .current
    ) -> ReminderPlan {
        var all: [PlannedReminder] = []
        for deadline in deadlines where deadline.endDate > now {
            let days = Set(leadDays[deadline.kind] ?? [7]).sorted(by: >)
            for daysBefore in days {
                guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: deadline.endDate),
                      let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      fireDate > now else { continue }
                all.append(PlannedReminder(
                    id: "\(identifierPrefix)\(deadline.id).\(daysBefore)",
                    deadlineID: deadline.id,
                    fireDate: fireDate,
                    daysBefore: daysBefore,
                    title: title(for: deadline, daysBefore: daysBefore),
                    body: body(for: deadline, showProductName: showProductNames)
                ))
            }
        }
        all.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        let cap = max(0, min(limit, systemLimit))
        return ReminderPlan(scheduled: Array(all.prefix(cap)), deferred: Array(all.dropFirst(cap)))
    }

    static func title(for deadline: DeadlineInput, daysBefore: Int) -> String {
        switch deadline.kind {
        case .returnWindow: return "Rückgabefrist endet \(when(daysBefore))"
        case .legal: return "Mängelrechte prüfen – Ende \(when(daysBefore))"
        case .manufacturer: return "Herstellergarantie prüfen – Ende \(when(daysBefore))"
        case .extended: return "Zusatzgarantie prüfen – Ende \(when(daysBefore))"
        }
    }

    /// Bewusst ohne Druck formuliert: Eine auslaufende Garantie ist kein Grund, ein funktionierendes Produkt zu reklamieren.
    static func body(for deadline: DeadlineInput, showProductName: Bool) -> String {
        let name = showProductName ? deadline.productName : "Ein Produkt in deinem Kaufarchiv"
        switch deadline.kind {
        case .returnWindow:
            return "\(name): Behalten oder Rückgabe vorbereiten?"
        default:
            return "\(name): Unterlagen liegen bereit. Nur nötig, falls etwas nicht funktioniert."
        }
    }

    static func when(_ daysBefore: Int) -> String {
        switch daysBefore {
        case 0: return "heute"
        case 1: return "morgen"
        default: return "in \(daysBefore) Tagen"
        }
    }
}
