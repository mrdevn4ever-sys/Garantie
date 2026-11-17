import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks
import Observation
import KaufarchivCore
import os

/// Schedules local notifications for deadlines and reports honestly what is scheduled.
/// iOS allows at most 64 pending notifications per app and decides itself when background
/// refresh runs, so the service plans the earliest reminders and asks the user to open the
/// app before the last scheduled one if more are waiting.
@Observable
@MainActor
final class ReminderService {
    static let shared = ReminderService()
    static let refreshTaskID = "ch.kaufarchiv.app.refresh"
    static let identifierPrefix = "deadline."
    static let safetyIdentifier = "safety.openApp"

    @ObservationIgnored private let logger = Logger(subsystem: "ch.kaufarchiv.app", category: "reminders")
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    var authorization: UNAuthorizationStatus = .notDetermined
    var lastPlan: ReminderPlan?
    var pendingRequests: [UNNotificationRequest] = []
    var lastRefresh: Date?

    var reminderHour: Int {
        let stored = UserDefaults.standard.object(forKey: SettingsKey.reminderHour) as? Int
        return stored ?? 9
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Rebuilds all deadline notifications from the database.
    func reschedule(context: ModelContext) async {
        await refreshAuthorization()
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        var candidates: [ReminderCandidate] = []
        for product in products where !product.status.isClosed {
            let coverages = product.coverageList
                .filter { $0.remindersEnabled && $0.endDate != nil && $0.confirmed }
                .map { (kind: $0.kind, end: $0.endDate!, offsets: $0.reminderOffsets) }
            candidates += ReminderPlanner.candidates(productID: product.id.uuidString,
                                                     productName: product.name,
                                                     coverages: coverages,
                                                     hour: reminderHour)
        }
        let plan = ReminderPlanner.plan(candidates)
        lastPlan = plan
        lastRefresh = Date()

        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
            pendingRequests = []
            return
        }

        let existing = await center.pendingNotificationRequests()
        let ours = existing.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) || $0 == Self.safetyIdentifier }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for candidate in plan.scheduled {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            content.threadIdentifier = candidate.productID
            content.userInfo = ["productID": candidate.productID]
            content.interruptionLevel = candidate.kind == .returnPolicy || candidate.kind == .withdrawal ? .timeSensitive : .active
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + candidate.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                logger.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let openBefore = plan.openAppBefore {
            // Safety net: if the app is not opened, the user still learns that more reminders wait.
            let content = UNMutableNotificationContent()
            content.title = "Weitere Fristen warten"
            content.body = "Öffne Kaufarchiv kurz, damit die nächsten \(plan.deferred.count) Erinnerungen geplant werden."
            let fire = openBefore.addingTimeInterval(-3600)
            if fire > Date() {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: Self.safetyIdentifier, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
        }
        pendingRequests = await center.pendingNotificationRequests()
            .sorted { nextDate($0) ?? .distantFuture < nextDate($1) ?? .distantFuture }
        scheduleBackgroundRefresh()
    }

    func nextDate(_ request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    // MARK: Background refresh (best effort, never relied upon)

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.debug("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds a single reminder outside the deadline plan (e.g. "Rückmeldung Händler abwarten").
    func scheduleFollowUp(id: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: "followup." + id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
    }
}
