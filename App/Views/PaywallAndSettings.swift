import SwiftUI
import SwiftData
import StoreKit
import UniformTypeIdentifiers
import KaufarchivCore

enum AppLinks {
    // Vor der Veröffentlichung durch die eigenen Seiten ersetzen (siehe README).
    static let privacy = URL(string: "https://example.com/kaufarchiv/datenschutz")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

// MARK: Kaufseite

struct PaywallView: View {
    let reason: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var selectedID = PurchaseManager.yearlyID
    @State private var isPurchasing = false

    private let features: [(String, String, String)] = [
        ("infinity", "Unbegrenzt viele Produkte", "Die kostenlose Version verwaltet \(Prefs.freeProductLimit) Produkte."),
        ("doc.richtext", "Reklamationsdossier als PDF", "Rechnung, Seriennummer, Fotos und Verlauf in einem Dokument."),
        ("icloud", "iCloud-Synchronisation", "Deine Käufe auf all deinen Geräten, in deinem privaten iCloud-Konto.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)
                    Text("Kaufarchiv Pro").font(.largeTitle.weight(.bold))
                    if let reason {
                        Text(reason)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features, id: \.1) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: feature.0)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.1).font(.body.weight(.semibold))
                                    Text(feature.2).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if purchases.isPro {
                        Label("Pro ist aktiv. Danke für deine Unterstützung!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .padding()
                    } else if purchases.products.isEmpty {
                        VStack(spacing: 8) {
                            if purchases.isLoading {
                                ProgressView()
                            } else {
                                Text(purchases.message ?? "Die Angebote konnten nicht geladen werden.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Erneut versuchen") {
                                    Task { await purchases.loadProducts() }
                                }
                            }
                        }
                        .padding()
                    } else {
                        offers
                    }

                    Text("Deine Originalbelege, die Suche, Erinnerungen und der Datenexport bleiben immer kostenlos zugänglich – auch nach dem Ende eines Abos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button("Käufe wiederherstellen") {
                            Task { await purchases.restore() }
                        }
                        Link("Nutzungsbedingungen", destination: AppLinks.terms)
                        Link("Datenschutz", destination: AppLinks.privacy)
                    }
                    .font(.caption)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
            .onAppear {
                if purchases.products.isEmpty {
                    Task { await purchases.loadProducts() }
                }
            }
        }
    }

    private var offers: some View {
        VStack(spacing: 12) {
            ForEach(purchases.products, id: \.id) { product in
                Button {
                    selectedID = product.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.body.weight(.semibold))
                            Text(product.description).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(product.displayPrice).font(.body.weight(.semibold))
                            Text(product.type == .autoRenewable ? "pro Jahr" : "einmalig")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedID == product.id ? Color.accentColor : Color(.separator),
                                    lineWidth: selectedID == product.id ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                guard let product = purchases.products.first(where: { $0.id == selectedID }) ?? purchases.products.first else { return }
                isPurchasing = true
                Task {
                    let success = await purchases.purchase(product)
                    isPurchasing = false
                    if success { dismiss() }
                }
            } label: {
                HStack {
                    if isPurchasing { ProgressView().tint(.white) }
                    Text("Weiter")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPurchasing)

            if let message = purchases.message {
                Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            Text("Das Jahresabo verlängert sich automatisch, bis du es in den App-Store-Einstellungen kündigst. Der Einmalkauf wird nur einmal belastet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: Einstellungen

struct SettingsView: View {
    let usesCloud: Bool

    @Environment(\.modelContext) private var context
    @Environment(PurchaseManager.self) private var purchases
    @Environment(ReminderCenter.self) private var reminders

    @AppStorage(Prefs.countryCode) private var countryCode = "CH"
    @AppStorage(Prefs.currency) private var currency = "CHF"
    @AppStorage(Prefs.senderName) private var senderName = ""
    @AppStorage(Prefs.returnLeadDays) private var returnLeadDays = 3
    @AppStorage(Prefs.warrantyLeadDays) private var warrantyLeadDays = 30
    @AppStorage(Prefs.reminderHour) private var reminderHour = 9
    @AppStorage(Prefs.iCloudEnabled) private var iCloudEnabled = false
    @AppStorage(Prefs.appLockEnabled) private var appLockEnabled = false
    #if DEBUG
    @AppStorage(Prefs.debugPro) private var debugPro = false
    #endif

    @State private var showPaywall = false

    var body: some View {
        Form {
            Section {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kaufarchiv Pro").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(purchases.isPro
                                 ? (purchases.ownsLifetime ? "Dauerhaft freigeschaltet" : "Aktiv")
                                 : "Unbegrenzte Produkte, Dossiers, iCloud")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if purchases.isPro {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        } else {
                            ProBadge()
                        }
                    }
                }
                if !purchases.isPro {
                    Button("Käufe wiederherstellen") {
                        Task { await purchases.restore() }
                    }
                }
            }

            Section {
                CountryPicker(selection: $countryCode)
                Picker("Währung", selection: $currency) {
                    ForEach(Catalog.currencies.contains(currency) ? Catalog.currencies : Catalog.currencies + [currency], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("Dein Name (für Reklamationen)", text: $senderName)
                    .textContentType(.name)
            } header: {
                Text("Standardwerte für neue Käufe")
            } footer: {
                Text(DeadlineRules.rule(for: countryCode).legalNote)
            }

            Section {
                NavigationLink {
                    ScheduledRemindersView()
                } label: {
                    HStack {
                        Text("Geplante Erinnerungen")
                        Spacer()
                        Text(reminders.isAuthorized ? "\(reminders.pending.count)" : "Aus").foregroundStyle(.secondary)
                    }
                }
                Stepper("Rückgabe: \(returnLeadDays) Tage vorher", value: $returnLeadDays, in: 2...14)
                Stepper("Garantie: \(warrantyLeadDays) Tage vorher", value: $warrantyLeadDays, in: 14...90, step: 2)
                Picker("Uhrzeit", selection: $reminderHour) {
                    ForEach(6..<22, id: \.self) { hour in
                        Text("\(hour):00 Uhr").tag(hour)
                    }
                }
            } header: {
                Text("Erinnerungen")
            } footer: {
                Text("Zusätzlich erinnert Kaufarchiv einen Tag vor Ablauf der Rückgabe und eine Woche vor Ablauf einer Garantie.")
            }
            .onChange(of: returnLeadDays) { _, _ in replan() }
            .onChange(of: warrantyLeadDays) { _, _ in replan() }
            .onChange(of: reminderHour) { _, _ in replan() }

            Section {
                Toggle(isOn: Binding(
                    get: { iCloudEnabled && purchases.isPro },
                    set: { newValue in
                        if purchases.isPro { iCloudEnabled = newValue } else { showPaywall = true }
                    }
                )) {
                    HStack {
                        Text("iCloud-Synchronisation")
                        if !purchases.isPro { ProBadge() }
                    }
                }
                LabeledContent("Status", value: cloudStatus)
            } header: {
                Text("iCloud")
            } footer: {
                Text("Die Daten liegen in deinem privaten iCloud-Konto. Die Änderung wird beim nächsten Start der App wirksam. Ohne iCloud bleibt alles ausschliesslich auf diesem Gerät.")
            }

            Section {
                Toggle("App-Sperre mit Face ID / Code", isOn: $appLockEnabled)
                    .disabled(!AppLock.canProtect)
            } header: {
                Text("Sicherheit")
            } footer: {
                if !AppLock.canProtect {
                    Text("Richte zuerst einen Gerätecode ein, um die App-Sperre zu verwenden.")
                }
            }

            Section("Daten") {
                NavigationLink("Export, Sicherung und Wiederherstellung") {
                    DataManagementView()
                }
            }

            Section("Über Kaufarchiv") {
                NavigationLink("Hinweise zu den Fristen") { LegalInfoView() }
                Link("Datenschutz", destination: AppLinks.privacy)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }

            #if DEBUG
            Section("Entwicklung") {
                Toggle("Pro simulieren", isOn: $debugPro)
                    .onChange(of: debugPro) { _, value in purchases.setDebugOverride(value) }
            }
            #endif
        }
        .navigationTitle("Einstellungen")
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: nil)
        }
    }

    private var cloudStatus: String {
        let wanted = iCloudEnabled && purchases.isPro
        switch (usesCloud, wanted) {
        case (true, true): return "Aktiv"
        case (false, true): return "Wird nach Neustart aktiv"
        case (true, false): return "Wird nach Neustart beendet"
        case (false, false): return "Aus – nur auf diesem Gerät"
        }
    }

    private func replan() {
        Task { await reminders.refresh(context: context) }
    }
}

struct LegalInfoView: View {
    var body: some View {
        List {
            Section {
                Text("Kaufarchiv führt vier Dinge getrennt: die Rückgabe- bzw. Widerrufsfrist, die gesetzlichen Mängelrechte gegenüber dem Händler, die freiwillige Herstellergarantie und kostenpflichtige Zusatzgarantien.")
                Text("Alle automatisch berechneten Fristen sind Vorschläge auf Basis der unten stehenden Ausgangswerte. Verbindlich sind Kaufvertrag, AGB, Garantiebedingungen und das anwendbare Recht. Kaufarchiv ersetzt keine Rechtsberatung.")
            }
            .font(.subheadline)

            ForEach(DeadlineRules.countries) { country in
                Section(country.name) {
                    LabeledContent("Mängelrechte", value: "\(country.legalMonths) Monate")
                    LabeledContent("Widerruf online", value: country.withdrawalDays.map { "\($0) Tage" } ?? "Kein allgemeines Recht")
                    Text(country.legalNote).font(.footnote).foregroundStyle(.secondary)
                    Text(country.withdrawalNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Fristen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Export, Sicherung, Wiederherstellung

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(ReminderCenter.self) private var reminders
    @Query private var documents: [StoredDocument]

    @State private var sharedFile: SharedFile?
    @State private var isWorking = false
    @State private var resultTitle = ""
    @State private var resultMessage: String?
    @State private var showRestorePicker = false

    var body: some View {
        List {
            Section {
                Button("Produktliste als CSV", systemImage: "tablecells") {
                    run { sharedFile = SharedFile(url: try ExportService.productsCSV(context: context)) }
                }
                Button("Alle Originalbelege als ZIP", systemImage: "doc.zipper") {
                    run { sharedFile = SharedFile(url: try ExportService.originalsArchive(context: context)) }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Der Export ist in jeder Version kostenlos. \(documents.count) Dokumente gespeichert.")
            }

            Section {
                Button("Sicherung erstellen", systemImage: "externaldrive.badge.plus") {
                    run { sharedFile = SharedFile(url: try BackupService.createBackup(context: context)) }
                }
                Button("Sicherung jetzt testen", systemImage: "checkmark.shield") {
                    run {
                        let url = try BackupService.createBackup(context: context)
                        let report = try BackupService.verify(url: url)
                        show(report, title: report.isHealthy ? "Sicherung ist vollständig" : "Sicherung unvollständig", restored: false)
                    }
                }
                Button("Aus Sicherung wiederherstellen", systemImage: "arrow.counterclockwise") {
                    showRestorePicker = true
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Eine Sicherung enthält alle Käufe, Fristen, Reklamationen und sämtliche Originaldateien in einer Datei. Der Test erstellt eine Sicherung, liest sie vollständig wieder ein und vergleicht jedes Original mit seiner Prüfsumme. Beim Wiederherstellen werden fehlende Einträge ergänzt; vorhandene bleiben unverändert.")
            }
        }
        .navigationTitle("Daten")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .overlay {
            if isWorking {
                ProgressView("Bitte warten …")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(url: file.url)
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                run {
                    let report = try BackupService.restore(url: url, context: context)
                    show(report, title: "Wiederherstellung abgeschlossen", restored: true)
                    Task { await reminders.refresh(context: context) }
                }
            case .failure(let error):
                resultTitle = "Datei konnte nicht geöffnet werden"
                resultMessage = error.localizedDescription
            }
        }
        .alert(resultTitle, isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    /// Führt eine Aktion nach dem nächsten Bildaufbau aus, damit die Warteanzeige sichtbar wird.
    private func run(_ action: @escaping @MainActor () throws -> Void) {
        isWorking = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            do {
                try action()
            } catch {
                resultTitle = "Aktion fehlgeschlagen"
                resultMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func show(_ report: BackupReport, title: String, restored: Bool) {
        var lines = [
            "\(report.receipts) Rechnungen, \(report.products) Produkte, \(report.documents) Dokumente gelesen."
        ]
        if restored, report.skippedExisting > 0 {
            lines.append("\(report.skippedExisting) bereits vorhandene Einträge wurden übersprungen.")
        }
        if report.isHealthy {
            lines.append("Alle Originaldateien stimmen mit ihrer Prüfsumme überein.")
        } else {
            lines.append("Beschädigt oder fehlend: \(report.damagedDocuments.joined(separator: ", "))")
        }
        resultTitle = title
        resultMessage = lines.joined(separator: "\n")
    }
}
