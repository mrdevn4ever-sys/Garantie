import SwiftUI
import SwiftData
import Observation

enum AppTab: Hashable {
    case overview, purchases, deadlines, settings
}

struct ImportRequest: Identifiable {
    let id = UUID()
    var file: ImportedFile?
    /// Gesetzt, wenn der Beleg aus dem Eingang stammt; er wird nach dem Speichern dort entfernt.
    var inboxItem: InboxItem?
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .overview
    var importRequest: ImportRequest?
    /// Übernommene, aber noch nicht erfasste Belege (Teilen-Erweiterung und gesicherte Entwürfe).
    var inbox: [InboxItem] = []

    func startImport(file: ImportedFile? = nil) {
        importRequest = ImportRequest(file: file)
    }

    func reloadInbox() {
        inbox = InboxStore.items()
    }

    func open(_ item: InboxItem) throws {
        var file = try ImportedFile.from(url: item.url)
        file.filename = item.displayName
        importRequest = ImportRequest(file: file, inboxItem: item)
    }

    func discard(_ item: InboxItem) {
        InboxStore.remove(item)
        reloadInbox()
    }
}

@main
struct KaufarchivApp: App {
    private let store: (container: ModelContainer, usesCloud: Bool)
    @State private var purchases = PurchaseManager()
    @State private var reminders = ReminderCenter()
    @State private var router = AppRouter()
    @State private var lock = AppLock()

    init() {
        Prefs.registerDefaults()
        store = DataController.makeContainer()
        TempFiles.cleanUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView(usesCloud: store.usesCloud)
                .environment(purchases)
                .environment(reminders)
                .environment(router)
                .environment(lock)
        }
        .modelContainer(store.container)
    }
}

struct RootView: View {
    let usesCloud: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(ReminderCenter.self) private var reminders
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AppLock.self) private var lock
    @AppStorage(Prefs.didOnboard) private var didOnboard = false
    @State private var openError: String?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { OverviewView() }
                .tabItem { Label("Übersicht", systemImage: "house") }
                .tag(AppTab.overview)
            NavigationStack { PurchasesView() }
                .tabItem { Label("Meine Käufe", systemImage: "shippingbox") }
                .tag(AppTab.purchases)
            NavigationStack { DeadlinesView() }
                .tabItem { Label("Fristen", systemImage: "calendar.badge.clock") }
                .tag(AppTab.deadlines)
            NavigationStack { SettingsView(usesCloud: usesCloud) }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(item: $router.importRequest) { request in
            ImportFlowView(request: request)
        }
        .fullScreenCover(isPresented: Binding(get: { !didOnboard }, set: { if !$0 { didOnboard = true } })) {
            OnboardingView()
        }
        .overlay {
            if lock.isLocked { LockScreen() }
        }
        .alert("Datei konnte nicht geöffnet werden", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
        // Dateien, die aus anderen Apps über «Öffnen mit / Teilen» übergeben werden.
        .onOpenURL { url in
            do {
                router.startImport(file: try ImportedFile.from(url: url))
            } catch {
                openError = error.localizedDescription
            }
        }
        .task {
            router.reloadInbox()
            await lock.unlock()
            await reminders.refresh(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfEnabled()
            case .active:
                router.reloadInbox()
                Task {
                    await lock.unlock()
                    await purchases.refreshEntitlements()
                    await reminders.refresh(context: context)
                }
            default:
                break
            }
        }
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Kaufarchiv ist gesperrt")
                    .font(.title3.weight(.semibold))
                if let message = lock.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Entsperren") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct OnboardingView: View {
    @AppStorage(Prefs.didOnboard) private var didOnboard = false
    @AppStorage(Prefs.countryCode) private var countryCode = "CH"
    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                onboardingPage(
                    symbol: "doc.viewfinder",
                    title: "Beleg erfassen",
                    text: "Fotografiere eine Rechnung oder teile sie aus einer anderen App. Kaufarchiv erkennt Händler, Datum, Betrag und die einzelnen Produkte – direkt auf deinem Gerät."
                ).tag(0)
                onboardingPage(
                    symbol: "calendar.badge.clock",
                    title: "Fristen im Blick",
                    text: "Rückgabe, gesetzliche Mängelrechte, Herstellergarantie und Zusatzgarantie werden getrennt geführt. Erkannte Werte sind Vorschläge, die du bestätigst."
                ).tag(1)
                onboardingPage(
                    symbol: "wrench.and.screwdriver",
                    title: "Bereit, wenn etwas kaputtgeht",
                    text: "Produkt suchen, Mangel beschreiben, Fotos ergänzen: Du erhältst einen Nachrichtenentwurf und ein Dossier mit allen Unterlagen."
                ).tag(2)
                countryPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    didOnboard = true
                }
            } label: {
                Text(page < 3 ? "Weiter" : "Los geht's")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }

    private func onboardingPage(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title).font(.title.weight(.bold))
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var countryPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Wo kaufst du meistens ein?").font(.title2.weight(.bold))
            Text("Die gesetzlichen Fristen unterscheiden sich je nach Land. Du kannst das Land bei jedem Kauf ändern.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            CountryPicker(selection: $countryCode)
                .pickerStyle(.wheel)
                .frame(height: 140)
            Spacer()
        }
    }
}
