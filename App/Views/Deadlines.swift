import SwiftUI
import SwiftData
import UserNotifications
import KaufarchivCore

// MARK: Fristen

struct DeadlinesView: View {
    @Environment(ReminderCenter.self) private var reminders
    @Query(sort: \Coverage.endDate) private var coverages: [Coverage]

    @State private var kindFilter: CoverageKind?
    @State private var calendarRequest: CalendarRequest?
    @State private var showExpired = false

    private var relevant: [Coverage] {
        coverages.filter { coverage in
            coverage.product?.status == .active && (kindFilter == nil || coverage.kind == kindFilter)
        }
    }

    private func group(_ range: ClosedRange<Int>) -> [Coverage] {
        relevant.filter { range.contains($0.daysRemaining()) }
    }

    private var expired: [Coverage] {
        relevant.filter { $0.daysRemaining() < 0 }.sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ScheduledRemindersView()
                } label: {
                    HStack {
                        Label("Geplante Erinnerungen", systemImage: reminders.isAuthorized ? "bell.badge" : "bell.slash")
                        Spacer()
                        Text(reminders.isAuthorized ? "\(reminders.pending.count)" : "Aus")
                            .foregroundStyle(reminders.isAuthorized ? Color.secondary : Color.orange)
                    }
                }
                Picker("Anzeigen", selection: $kindFilter) {
                    Text("Alle Fristen").tag(CoverageKind?.none)
                    ForEach(CoverageKind.allCases) { kind in
                        Text(kind.label).tag(CoverageKind?.some(kind))
                    }
                }
            }

            if relevant.isEmpty {
                ContentUnavailableView(
                    "Keine Fristen",
                    systemImage: "calendar",
                    description: Text("Sobald du Käufe erfasst, erscheinen hier Rückgabe- und Garantiefristen.")
                )
            }

            section("In den nächsten 7 Tagen", group(0...7))
            section("In den nächsten 30 Tagen", group(8...30))
            section("In den nächsten 12 Monaten", group(31...365))
            section("Später", group(366...100_000))

            if !expired.isEmpty {
                Section {
                    DisclosureGroup("Abgelaufen (\(expired.count))", isExpanded: $showExpired) {
                        ForEach(expired) { coverage in
                            row(coverage)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fristen")
        .sheet(item: $calendarRequest) { request in
            CalendarEventEditor(title: request.title, date: request.date, notes: request.notes) {
                calendarRequest = nil
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Coverage]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { coverage in
                    row(coverage)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ coverage: Coverage) -> some View {
        if let product = coverage.product {
            NavigationLink {
                ProductDetailView(product: product)
            } label: {
                CoverageRow(coverage: coverage, showProduct: true)
            }
            .swipeActions {
                Button("Kalender", systemImage: "calendar.badge.plus") {
                    calendarRequest = CalendarRequest(coverage: coverage)
                }
                .tint(.blue)
            }
        }
    }
}

// MARK: Tatsächlich geplante Erinnerungen

struct ScheduledRemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(ReminderCenter.self) private var reminders

    var body: some View {
        List {
            Section {
                switch reminders.authorization {
                case .notDetermined:
                    Button("Mitteilungen erlauben") {
                        Task {
                            await reminders.requestAuthorization()
                            await reminders.refresh(context: context)
                        }
                    }
                case .denied:
                    Label("Mitteilungen sind für Kaufarchiv ausgeschaltet. Es können keine Erinnerungen zugestellt werden.",
                          systemImage: "bell.slash")
                        .foregroundStyle(.orange)
                    Button("Systemeinstellungen öffnen") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                default:
                    Label("Mitteilungen sind erlaubt.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            } footer: {
                Text("Diese Liste zeigt, was iOS tatsächlich eingeplant hat – nicht bloss, was die App sich vorgenommen hat.")
            }

            if reminders.isAuthorized {
                Section {
                    if reminders.pending.isEmpty {
                        Text("Im Moment ist keine Erinnerung eingeplant.").foregroundStyle(.secondary)
                    }
                    ForEach(reminders.pending) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title).font(.body.weight(.medium))
                            Text(reminder.body).font(.footnote).foregroundStyle(.secondary)
                            if let date = reminder.fireDate {
                                Text(Fmt.dateTime(date)).font(.caption).foregroundStyle(.tint)
                            }
                        }
                    }
                } header: {
                    Text("Eingeplant (\(reminders.pending.count))")
                } footer: {
                    if reminders.deferredCount > 0 {
                        Text("\(reminders.deferredCount) weiter entfernte Erinnerungen werden eingeplant, sobald du die App wieder öffnest. iOS erlaubt höchstens \(ReminderPlanner.systemLimit) gleichzeitig geplante Mitteilungen. Für wichtige Fristen kannst du zusätzlich einen Kalendereintrag anlegen.")
                    } else {
                        Text("Alle anstehenden Erinnerungen sind eingeplant. Für wichtige Fristen kannst du zusätzlich einen Kalendereintrag anlegen.")
                    }
                }
            }

            if let error = reminders.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section {
                Button("Jetzt neu planen") {
                    Task { await reminders.refresh(context: context) }
                }
                if let last = reminders.lastRefresh {
                    LabeledContent("Zuletzt geplant", value: Fmt.dateTime(last))
                }
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminders.refresh(context: context) }
    }
}
