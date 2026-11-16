import Foundation
import SwiftData
import UserNotifications
import Observation
import KaufarchivCore

struct PendingReminder: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date?
}

/// Plant lokale Erinnerungen und zeigt an, was tatsächlich im System eingeplant ist.
/// iOS erlaubt höchstens 64 ausstehende Mitteilungen; weiter entfernte Termine werden beim
/// nächsten Öffnen der App nachgeplant. Das wird in der App offen ausgewiesen.
@MainActor
@Observable
final class ReminderCenter {
    var authorization: UNAuthorizationStatus = .notDetermined
    /// Aus dem System zurückgelesen – nicht bloss «geplant», sondern wirklich eingereiht.
    var pending: [PendingReminder] = []
    var deferredCount = 0
    var lastRefresh: Date?
    var lastError: String?

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    func updateAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await updateAuthorization()
            return granted
        } catch {
            lastError = error.localizedDescription
            await updateAuthorization()
            return false
        }
    }

    /// Plant alle Erinnerungen neu. Wird bei jedem Start, beim Wechsel in den Vordergrund und nach jeder Änderung aufgerufen.
    func refresh(context: ModelContext) async {
        await updateAuthorization()
        let center = UNUserNotificationCenter.current()
        let now = Date()

        let coverages = (try? context.fetch(FetchDescriptor<Coverage>())) ?? []
        let deadlines: [DeadlineInput] = coverages.compactMap { coverage in
            guard coverage.remindersEnabled, coverage.endDate > now,
                  let product = coverage.product, product.status == .active else { return nil }
            return DeadlineInput(
                id: coverage.uid.uuidString,
                productName: product.displayName,
                kind: coverage.kind,
                endDate: coverage.endDate
            )
        }
        let hour = Prefs.defaults.integer(forKey: Prefs.reminderHour)
        let plan = ReminderPlanner.plan(
            deadlines: deadlines,
            leadDays: Prefs.leadDays,
            now: now,
            hour: (0...23).contains(hour) ? hour : 9
        )
        deferredCount = plan.deferred.count

        let existing = await center.pendingNotificationRequests()
            .map { $0.identifier }
            .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard isAuthorized else {
            pending = []
            lastRefresh = now
            return
        }

        lastError = nil
        let calendar = Calendar.current
        for reminder in plan.scheduled {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["coverage": reminder.deadlineID]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                lastError = error.localizedDescription
            }
        }

        // Zurücklesen, was das System wirklich angenommen hat.
        let requests = await center.pendingNotificationRequests()
        pending = requests
            .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) }
            .map { request in
                PendingReminder(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                )
            }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
        lastRefresh = now
    }
}
