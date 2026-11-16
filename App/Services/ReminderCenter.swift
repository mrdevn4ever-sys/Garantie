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
    /// Kennungen der Fristen, deren Erinnerungen erst später eingeplant werden können.
    private(set) var deferredDeadlineIDs: Set<String> = []

    enum Status {
        case scheduled, notificationsOff, outsideWindow, disabled, unconfirmed, notApplicable
    }

    /// Erinnerungsstatus einer einzelnen Frist – für die Anzeige in der Produktakte.
    func status(for coverage: Coverage) -> Status {
        guard coverage.isActive() else { return .notApplicable }
        if !coverage.isConfirmed { return .unconfirmed }
        if !coverage.remindersEnabled || coverage.isDecided { return .disabled }
        if !isAuthorized { return .notificationsOff }
        let id = coverage.uid.uuidString
        if pending.contains(where: { $0.id.contains(id) }) { return .scheduled }
        if deferredDeadlineIDs.contains(id) { return .outsideWindow }
        return .notApplicable
    }

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
            // Nur bestätigte Fristen lösen Erinnerungen aus; Vorschläge bleiben still.
            guard coverage.remindersEnabled, coverage.isConfirmed, !coverage.isDecided, coverage.endDate > now,
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
            hour: (0...23).contains(hour) ? hour : 9,
            showProductNames: !Prefs.defaults.bool(forKey: Prefs.hideNamesInReminders)
        )
        deferredCount = plan.deferred.count
        deferredDeadlineIDs = Set(plan.deferred.map { $0.deadlineID })

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
