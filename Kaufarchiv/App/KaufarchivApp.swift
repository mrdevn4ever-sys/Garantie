import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications
import CoreSpotlight

@main
struct KaufarchivApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    @State private var store = StoreService.shared
    @State private var reminders = ReminderService.shared
    @State private var lock = AppLock()

    let container: ModelContainer

    init() {
        container = Persistence.makeContainer()
        AppDelegate.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(store)
                .environment(reminders)
                .environment(lock)
                .onAppear {
                    AppDelegate.router = router
                    store.start()
                }
                .onOpenURL { url in
                    if url.host == "inbox" { router.checkInbox() }
                    if url.host == "product" { router.open(productID: url.lastPathComponent) }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        router.open(productID: id)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                router.checkInbox()
                Task { await reminders.reschedule(context: container.mainContext) }
            case .background:
                lock.lockIfNeeded()
                indexSpotlight()
            default:
                break
            }
        }
    }

    private func indexSpotlight() {
        let products = (try? container.mainContext.fetch(FetchDescriptor<Product>())) ?? []
        SpotlightIndexer.index(products)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var container: ModelContainer?
    @MainActor static weak var router: AppRouter?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: ReminderService.refreshTaskID, using: nil) { task in
            Self.handleRefresh(task: task)
        }
        return true
    }

    private static func handleRefresh(task: BGTask) {
        let work = Task { @MainActor in
            if let container = AppDelegate.container {
                await ReminderService.shared.reschedule(context: container.mainContext)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // Show reminders also while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let productID = response.notification.request.content.userInfo["productID"] as? String else { return }
        await MainActor.run {
            AppDelegate.router?.open(productID: productID)
        }
    }
}
