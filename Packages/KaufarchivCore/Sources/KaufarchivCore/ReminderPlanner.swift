import Foundation

/// A reminder the app would like to deliver.
public struct ReminderCandidate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Identifier of the product the reminder belongs to (for deep links).
    public var productID: String
    public var kind: CoverageKind
    public var deadline: Date

    public init(id: String, fireDate: Date, title: String, body: String, productID: String, kind: CoverageKind, deadline: Date) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.productID = productID
        self.kind = kind
        self.deadline = deadline
    }
}

public struct ReminderPlan: Sendable {
    /// Reminders that will actually be handed to the system.
    public var scheduled: [ReminderCandidate]
    /// Reminders that exceed the system limit and are planned once the app runs again.
    public var deferred: [ReminderCandidate]
    /// Reminders whose fire date already passed (deadline may still be ahead).
    public var missed: [ReminderCandidate]

    /// The user must open the app before this date, otherwise deferred reminders cannot be planned.
    public var openAppBefore: Date? { deferred.isEmpty ? nil : scheduled.last?.fireDate }
}

/// iOS keeps at most 64 pending local notifications per app and decides on its own when
/// background refresh runs. The planner therefore schedules the earliest reminders only and
/// reports honestly which ones are not yet scheduled.
public enum ReminderPlanner {
    public static let systemLimit = 64
    /// Slots reserved for the "please open the app" safety reminder and ad-hoc notifications.
    public static let reservedSlots = 2

    public static func candidates(productID: String,
                                  productName: String,
                                  coverages: [(kind: CoverageKind, end: Date, offsets: [Int])],
                                  hour: Int = 9,
                                  calendar: Calendar = .current) -> [ReminderCandidate] {
        var result: [ReminderCandidate] = []
        for coverage in coverages {
            for offset in Set(coverage.offsets).sorted(by: >) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: coverage.end)),
                      let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { continue }
                let when: String = switch offset {
                case 0: "heute"
                case 1: "morgen"
                default: "in \(offset) Tagen"
                }
                let title = "\(coverage.kind.title) endet \(when)"
                let body = "\(productName): Prüfe jetzt, ob alles in Ordnung ist."
                result.append(ReminderCandidate(id: "\(productID).\(coverage.kind.rawValue).\(offset)",
                                                fireDate: fire, title: title, body: body,
                                                productID: productID, kind: coverage.kind, deadline: coverage.end))
            }
        }
        return result
    }

    public static func plan(_ candidates: [ReminderCandidate], now: Date = Date(), limit: Int = systemLimit - reservedSlots) -> ReminderPlan {
        let sorted = candidates.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        let missed = sorted.filter { $0.fireDate <= now && $0.deadline >= now }
        let upcoming = sorted.filter { $0.fireDate > now }
        let scheduled = Array(upcoming.prefix(max(limit, 0)))
        let deferred = Array(upcoming.dropFirst(max(limit, 0)))
        return ReminderPlan(scheduled: scheduled, deferred: deferred, missed: missed)
    }
}
