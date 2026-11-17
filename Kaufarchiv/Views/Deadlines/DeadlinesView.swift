import SwiftUI
import SwiftData
import UserNotifications
import KaufarchivCore

struct DeadlinesView: View {
    @Environment(ReminderService.self) private var reminders
    @Environment(\.modelContext) private var context
    @Query private var coverages: [Coverage]

    enum Scope: String, CaseIterable, Identifiable {
        case upcoming, expired, reminders
        var id: String { rawValue }
        var title: String {
            switch self {
            case .upcoming: "Laufend"
            case .expired: "Abgelaufen"
            case .reminders: "Erinnerungen"
            }
        }
    }

    @State private var scope: Scope = .upcoming
    @State private var kindFilter: CoverageKind?

    private var relevant: [Coverage] {
        coverages.filter { coverage in
            guard let product = coverage.product, !product.status.isClosed else { return false }
            if let kindFilter, coverage.kind != kindFilter { return false }
            return true
        }
    }

    private var upcoming: [Coverage] {
        relevant.filter { $0.status.isActive }.sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    private var expired: [Coverage] {
        relevant.filter { !$0.status.isActive }.sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
    }

    private func groupedByMonth(_ list: [Coverage]) -> [(String, [Coverage])] {
        var order: [String] = []
        var dict: [String: [Coverage]] = [:]
        for coverage in list {
            let key = coverage.endDate.map(Formatters.monthYear) ?? "Ohne Datum"
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(coverage)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Ansicht", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                switch scope {
                case .upcoming:
                    coverageSections(upcoming, empty: "Keine laufenden Fristen")
                case .expired:
                    coverageSections(expired, empty: "Keine abgelaufenen Fristen")
                case .reminders:
                    ReminderStatusSection()
                }
            }
            .navigationTitle("Fristen")
            .toolbar {
                if scope != .reminders {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Art", selection: $kindFilter) {
                                Text("Alle Arten").tag(CoverageKind?.none)
                                ForEach(CoverageKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag(CoverageKind?.some($0)) }
                            }
                        } label: {
                            Label("Filtern", systemImage: kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .navigationDestination(for: Claim.self) { ClaimDetailView(claim: $0) }
            .refreshable { await reminders.reschedule(context: context) }
        }
    }

    @ViewBuilder
    private func coverageSections(_ list: [Coverage], empty: String) -> some View {
        if list.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            ForEach(groupedByMonth(list), id: \.0) { month, items in
                Section(month) {
                    ForEach(items) { coverage in
                        if let product = coverage.product {
                            NavigationLink(value: product) {
                                DeadlineListRow(product: product, coverage: coverage)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Transparent view of what iOS will actually deliver.
private struct ReminderStatusSection: View {
    @Environment(ReminderService.self) private var reminders
    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            LabeledContent("Mitteilungen", value: authorizationText)
            if let plan = reminders.lastPlan {
                LabeledContent("Bei iOS geplant", value: "\(plan.scheduled.count)")
                LabeledContent("Wartend (Limit erreicht)", value: "\(plan.deferred.count)")
                if !plan.missed.isEmpty {
                    LabeledContent("Verpasst, Frist läuft noch", value: "\(plan.missed.count)")
                }
                if let openBefore = plan.openAppBefore {
                    Text("Öffne Kaufarchiv vor dem \(Formatters.date(openBefore)), damit die wartenden Erinnerungen geplant werden. Du erhältst vorher eine Mitteilung.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if let refresh = reminders.lastRefresh {
                LabeledContent("Zuletzt aktualisiert", value: Formatters.relative(refresh))
            }
            Button("Jetzt neu planen") {
                Task { await reminders.reschedule(context: context) }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("iOS speichert pro App höchstens 64 Erinnerungen und entscheidet selbst, wann die App im Hintergrund laufen darf. Hier siehst du, was tatsächlich geplant ist.")
        }

        if let plan = reminders.lastPlan, !plan.missed.isEmpty {
            Section("Verpasste Erinnerungen") {
                ForEach(plan.missed) { candidate in
                    VStack(alignment: .leading) {
                        Text(candidate.title)
                        Text("\(candidate.body) Frist: \(Formatters.date(candidate.deadline))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section("Geplante Erinnerungen") {
            if reminders.pendingRequests.isEmpty {
                Text("Keine Erinnerungen geplant").foregroundStyle(.secondary)
            }
            ForEach(reminders.pendingRequests, id: \.identifier) { request in
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.content.title)
                    Text(request.content.body).font(.caption).foregroundStyle(.secondary)
                    if let date = reminders.nextDate(request) {
                        Text(date.formatted(.dateTime.day().month().year().hour().minute().locale(Formatters.locale)))
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .task { await reminders.reschedule(context: context) }
    }

    private var authorizationText: String {
        switch reminders.authorization {
        case .authorized: "erlaubt"
        case .provisional: "still erlaubt"
        case .ephemeral: "vorübergehend"
        case .denied: "ausgeschaltet"
        case .notDetermined: "nicht gefragt"
        @unknown default: "unbekannt"
        }
    }
}
