import SwiftUI
import SwiftData
import StoreKit
import KaufarchivCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(AppRouter.self) private var router

    @AppStorage(SettingsKey.defaultCountry) private var defaultCountry = "CH"
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 9
    @AppStorage(SettingsKey.iCloudSync) private var iCloudSync = false
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.customerName) private var customerName = ""
    @AppStorage(SettingsKey.lastBackupDate) private var lastBackup: Double = 0

    @Query private var products: [Product]
    @Query private var documents: [StoredDocument]

    @State private var exportPackage: BackupPackage?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: (title: String, text: String)?
    @State private var working = false
    @State private var showManageSubscriptions = false

    var body: some View {
        NavigationStack {
            Form {
                proSection

                Section {
                    CountryPicker(code: $defaultCountry)
                    NavigationLink("Rechtliche Grundlagen") { LegalInfoView() }
                } header: {
                    Text("Land")
                } footer: {
                    Text("Bestimmt die vorgeschlagenen Fristen für neue Käufe. Erkennt die App ein anderes Land auf dem Beleg, schlägt sie dieses vor.")
                }

                Section {
                    Picker("Uhrzeit", selection: $reminderHour) {
                        ForEach(6..<22) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    .onChange(of: reminderHour) { _, _ in Task { await reminders.reschedule(context: context) } }
                    NavigationLink("Status der Erinnerungen") {
                        List { ReminderStatusLink() }.navigationTitle("Erinnerungen")
                    }
                    if reminders.authorization == .denied {
                        Button("Mitteilungen in iOS erlauben") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else if reminders.authorization == .notDetermined {
                        Button("Mitteilungen erlauben") { Task { await reminders.requestAuthorization() } }
                    }
                } header: {
                    Text("Erinnerungen")
                }

                Section {
                    Toggle("iCloud-Synchronisation", isOn: Binding(get: { iCloudSync && store.isPro }, set: { newValue in
                        if newValue && !store.isPro {
                            router.requestPro(reason: "Mit Pro werden deine Belege über iCloud auf allen Geräten synchronisiert.")
                        } else {
                            iCloudSync = newValue
                            message = ("Neustart nötig", "Die Änderung wird beim nächsten Start von Kaufarchiv wirksam.")
                        }
                    }))
                    if iCloudSync != Persistence.syncEnabledAtLaunch && store.isPro {
                        Label("Wird beim nächsten Start aktiv", systemImage: "arrow.clockwise")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("Mit Face ID / Code schützen", isOn: $appLock)
                        .disabled(!AppLock.canUseBiometrics())
                } header: {
                    Text("Daten & Sicherheit")
                } footer: {
                    Text("Ohne iCloud bleiben alle Daten ausschliesslich auf diesem Gerät. Die Texterkennung läuft immer lokal.")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Sicherung exportieren", systemImage: "square.and.arrow.up")
                    }
                    .disabled(working)
                    Button {
                        showImporter = true
                    } label: {
                        Label("Sicherung wiederherstellen", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        verifyBackup()
                    } label: {
                        Label("Wiederherstellbarkeit prüfen", systemImage: "checkmark.shield")
                    }
                    if lastBackup > 0 {
                        LabeledContent("Letzte Sicherung", value: Formatters.relative(Date(timeIntervalSince1970: lastBackup)))
                    }
                    LabeledContent("Gespeichert", value: "\(products.count) Produkte, \(documents.count) Dokumente")
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text("Die Sicherung enthält alle Daten und die unveränderten Originaldateien – auch in der Gratisversion und nach einem Abo-Ende.")
                }

                Section("Reklamationen") {
                    TextField("Dein Name für Nachrichten", text: $customerName)
                        .textContentType(.name)
                }

                Section("Über") {
                    NavigationLink("Datenschutz") { PrivacyView() }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Link("Support kontaktieren", destination: URL(string: "mailto:support@kaufarchiv.app")!)
                }
            }
            .navigationTitle("Einstellungen")
            .fileExporter(isPresented: $showExporter, document: exportPackage, contentType: .kaufarchivBackup,
                          defaultFilename: BackupService.defaultFilename) { result in
                switch result {
                case .success:
                    lastBackup = Date().timeIntervalSince1970
                    message = ("Sicherung erstellt", "Bewahre die Datei an einem sicheren Ort auf, z. B. in iCloud Drive oder auf einem Computer.")
                case let .failure(error):
                    message = ("Export fehlgeschlagen", error.localizedDescription)
                }
                exportPackage = nil
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.kaufarchivBackup, .folder]) { result in
                restore(result)
            }
            .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message?.text ?? "")
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .overlay {
                if working {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                Label {
                    VStack(alignment: .leading) {
                        Text("Kaufarchiv Pro ist aktiv").font(.headline)
                        if store.activeProductID == StoreService.ProductID.lifetime {
                            Text("Dauerhaft freigeschaltet").font(.caption).foregroundStyle(.secondary)
                        } else if let renewal = store.renewalDate {
                            Text("Verlängert am \(Formatters.date(renewal))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "star.circle.fill").foregroundStyle(.yellow)
                }
                if store.activeProductID == StoreService.ProductID.yearly {
                    Button("Abo verwalten") { showManageSubscriptions = true }
                }
            } else {
                Button {
                    router.requestPro(reason: nil)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Kaufarchiv Pro").font(.headline)
                            Text("Unbegrenzte Produkte, iCloud und Reklamationsdossiers").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "star.circle").foregroundStyle(.yellow)
                    }
                }
                .buttonStyle(.plain)
            }
            Button("Käufe wiederherstellen") {
                Task {
                    do {
                        try await store.restore()
                        message = store.isPro ? ("Wiederhergestellt", "Kaufarchiv Pro ist aktiv.") : ("Keine Käufe gefunden", "Für diese Apple-ID wurde kein Pro-Kauf gefunden.")
                    } catch {
                        message = ("Wiederherstellen fehlgeschlagen", error.localizedDescription)
                    }
                }
            }
        }
    }

    private func exportBackup() {
        working = true
        defer { working = false }
        do {
            exportPackage = try BackupService.makePackage(context: context)
            showExporter = true
        } catch {
            message = ("Export fehlgeschlagen", error.localizedDescription)
        }
    }

    private func verifyBackup() {
        working = true
        defer { working = false }
        do {
            let result = try BackupService.verifyRoundTrip(context: context)
            if result.documents == result.valid {
                message = ("Alles in Ordnung", "Alle \(result.documents) Originaldateien wurden vollständig und unverändert in die Sicherung übernommen.")
            } else {
                message = ("Achtung", "\(result.documents - result.valid) von \(result.documents) Dateien sind nicht vollständig. Bitte kontaktiere den Support.")
            }
        } catch {
            message = ("Prüfung fehlgeschlagen", error.localizedDescription)
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            working = true
            defer { working = false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let wrapper = try FileWrapper(url: url, options: .immediate)
                let report = try BackupService.restore(from: wrapper, into: context)
                var text = "\(report.purchasesAdded) Käufe, \(report.productsAdded) Produkte und \(report.documentsAdded) Dokumente wiederhergestellt."
                if report.skippedExisting > 0 { text += " \(report.skippedExisting) bereits vorhandene Käufe wurden übersprungen." }
                if !report.corruptedDocuments.isEmpty { text += " Fehlerhafte Dateien: \(report.corruptedDocuments.joined(separator: ", "))." }
                message = ("Wiederherstellung abgeschlossen", text)
                Task { await reminders.reschedule(context: context) }
            } catch {
                message = ("Wiederherstellung fehlgeschlagen", error.localizedDescription)
            }
        case let .failure(error):
            message = ("Wiederherstellung fehlgeschlagen", error.localizedDescription)
        }
    }
}

/// Reuses the reminder status from the deadlines tab.
private struct ReminderStatusLink: View {
    @Environment(ReminderService.self) private var reminders

    var body: some View {
        Section {
            if let plan = reminders.lastPlan {
                LabeledContent("Bei iOS geplant", value: "\(plan.scheduled.count)")
                LabeledContent("Wartend", value: "\(plan.deferred.count)")
            }
            ForEach(reminders.pendingRequests, id: \.identifier) { request in
                VStack(alignment: .leading) {
                    Text(request.content.title)
                    if let date = reminders.nextDate(request) {
                        Text(Formatters.date(date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct LegalInfoView: View {
    var body: some View {
        List {
            Section {
                Text(LegalRules.disclaimer).font(.footnote)
                Text("Stand der Angaben: \(LegalRules.reviewedAt)").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Begriffe") {
                term(.statutory, "Gesetzliches Recht gegenüber dem Händler bei Mängeln, die beim Kauf schon bestanden.")
                term(.manufacturer, "Freiwilliges Versprechen des Herstellers. Die Bedingungen legt der Hersteller fest.")
                term(.extended, "Gekaufte Verlängerung oder Versicherung, oft mit eigenen Bedingungen.")
                term(.returnPolicy, "Freiwilliges Angebot des Händlers, Ware zurückzunehmen.")
                term(.withdrawal, "Gesetzliches Recht, einen Online-Kauf ohne Grund zu widerrufen (z. B. EU, nicht Schweiz).")
            }
            ForEach(LegalRules.all) { rules in
                Section(rules.name) {
                    LabeledContent("Gewährleistung", value: rules.statutoryMonths.map { "\($0 / 12) Jahre" } ?? "keine feste Frist")
                    LabeledContent("Widerruf online", value: rules.onlineWithdrawalDays.map { "\($0) Tage" } ?? "kein allgemeines Recht")
                    ForEach(rules.notes, id: \.self) { Text($0).font(.footnote) }
                }
            }
        }
        .navigationTitle("Rechtliches")
    }

    private func term(_ kind: CoverageKind, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: kind.symbolName).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Label("Keine Werbung, kein Tracking, keine Analyse-Dienste.", systemImage: "hand.raised")
                Label("Belege werden auf dem Gerät erkannt. Es werden keine Bilder an Server gesendet.", systemImage: "iphone")
                Label("Mit iCloud werden die Daten verschlüsselt in deinem privaten iCloud-Konto gespeichert. Der Entwickler hat keinen Zugriff.", systemImage: "icloud")
                Label("Deine Originalbelege und ein vollständiger Export bleiben immer verfügbar – auch ohne Pro.", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle("Datenschutz")
    }
}
