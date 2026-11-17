import Foundation
import SwiftData
import os

enum SettingsKey {
    static let iCloudSync = "settings.iCloudSync"
    static let defaultCountry = "settings.defaultCountry"
    static let reminderHour = "settings.reminderHour"
    static let appLock = "settings.appLock"
    static let onboardingDone = "settings.onboardingDone"
    static let customerName = "settings.customerName"
    static let customerEmail = "settings.customerEmail"
    static let lastBackupDate = "settings.lastBackupDate"
    static let cachedIsPro = "settings.cachedIsPro"
}

/// Builds the SwiftData container. iCloud sync is a Pro feature and takes effect at the
/// next launch, because a container's CloudKit configuration cannot change at runtime.
enum Persistence {
    static let logger = Logger(subsystem: "ch.kaufarchiv.app", category: "persistence")
    static let cloudContainerID = "iCloud.ch.kaufarchiv.app"

    static var syncEnabledAtLaunch = false

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let defaults = UserDefaults.standard
        let wantsSync = defaults.bool(forKey: SettingsKey.iCloudSync) && defaults.bool(forKey: SettingsKey.cachedIsPro)
        syncEnabledAtLaunch = wantsSync && !inMemory

        let configuration = ModelConfiguration(
            "Kaufarchiv",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: syncEnabledAtLaunch ? .private(cloudContainerID) : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("ModelContainer failed: \(error.localizedDescription, privacy: .public)")
            // Never lose data silently: fall back to local-only store with the same file.
            let local = ModelConfiguration("Kaufarchiv", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            syncEnabledAtLaunch = false
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
            }
        }
    }

    @MainActor
    static func previewContainer() -> ModelContainer {
        let container = makeContainer(inMemory: true)
        SampleData.insert(into: container.mainContext)
        return container
    }
}
