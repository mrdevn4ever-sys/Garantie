import Foundation
import EventKit
import KaufarchivCore

/// Optional hand-over of deadlines to the system calendar (write-only access).
enum CalendarService {
    enum CalendarError: LocalizedError {
        case denied
        case noEndDate

        var errorDescription: String? {
            switch self {
            case .denied: "Kein Zugriff auf den Kalender. Du kannst ihn in den Einstellungen erlauben."
            case .noEndDate: "Diese Frist hat kein Enddatum."
            }
        }
    }

    static func addEvent(for coverage: Coverage, productName: String) async throws {
        guard let end = coverage.endDate else { throw CalendarError.noEndDate }
        let store = EKEventStore()
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw CalendarError.denied }
        let event = EKEvent(eventStore: store)
        event.title = "\(coverage.kind.title) endet: \(productName)"
        event.isAllDay = true
        event.startDate = end
        event.endDate = end
        event.notes = "Erstellt von Kaufarchiv. \(LegalRules.disclaimer)"
        event.calendar = store.defaultCalendarForNewEvents
        for offset in coverage.reminderOffsets {
            event.addAlarm(EKAlarm(relativeOffset: -Double(offset) * 86_400 + 9 * 3600))
        }
        try store.save(event, span: .thisEvent)
    }
}
