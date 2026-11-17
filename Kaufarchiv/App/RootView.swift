import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(ReminderService.self) private var reminders
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            OverviewView()
                .tabItem { Label("Übersicht", systemImage: "house") }
                .tag(AppRouter.Tab.overview)
            PurchasesView()
                .tabItem { Label("Meine Käufe", systemImage: "shippingbox") }
                .tag(AppRouter.Tab.purchases)
            DeadlinesView()
                .tabItem { Label("Fristen", systemImage: "calendar.badge.clock") }
                .tag(AppRouter.Tab.deadlines)
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .sheet(isPresented: $router.showImport) {
            let pending = router.pendingInbox.first
            ImportFlowView(initialFiles: pending?.files ?? []) { purchase in
                if let pending {
                    // Only remove the shared files once they were saved or explicitly discarded.
                    SharedInbox.remove(batch: pending.batch)
                    router.pendingInbox.removeFirst()
                }
                router.showImport = false
                if let product = purchase?.productList.first {
                    router.open(productID: product.id.uuidString)
                }
            }
        }
        .sheet(isPresented: $router.showPaywall) {
            PaywallView(reason: router.paywallReason)
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) {
            OnboardingView {
                onboardingDone = true
                Task { await reminders.reschedule(context: context) }
            }
        }
        .overlay {
            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            }
        }
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Kaufarchiv ist gesperrt")
                .font(.title2.bold())
            if let error = lock.lastError {
                Text(error).foregroundStyle(.secondary)
            }
            Button("Entsperren") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await lock.unlock() }
    }
}
