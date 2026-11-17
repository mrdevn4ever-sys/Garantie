import SwiftUI
import SwiftData
import KaufarchivCore

struct OverviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(StoreService.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]

    @State private var showClaimPicker = false
    @State private var claimProduct: Product?

    private var activeProducts: [Product] { products.filter { !$0.status.isClosed } }

    private var upcoming: [(Product, Coverage)] {
        activeProducts
            .flatMap { product in product.coverageList.filter { $0.status.isActive }.map { (product, $0) } }
            .sorted { ($0.1.endDate ?? .distantFuture) < ($1.1.endDate ?? .distantFuture) }
    }

    private var soonCount: Int {
        upcoming.filter { if case .soon = $0.1.status { return true }; if case .endsToday = $0.1.status { return true }; return false }.count
    }

    private var protectedCount: Int { activeProducts.filter { $0.bestActiveCoverage != nil }.count }

    private var openClaims: [Claim] { claims.filter { $0.status.isOpen } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        StatTile(value: "\(products.count)", label: "Produkte", symbol: "shippingbox")
                        StatTile(value: "\(protectedCount)", label: "geschützt", symbol: "checkmark.shield")
                        StatTile(value: "\(soonCount)", label: "bald fällig", symbol: "clock.badge.exclamationmark", highlight: soonCount > 0)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    QuickAction(title: "Beleg erfassen", symbol: "doc.viewfinder") {
                        if !store.isPro && products.count >= Entitlements.freeProductLimit {
                            router.requestPro(reason: "Die Gratisversion umfasst \(Entitlements.freeProductLimit) Produkte. Mit Pro speicherst du unbegrenzt viele.")
                        } else {
                            router.pendingInbox = []
                            router.showImport = true
                        }
                    }
                    QuickAction(title: "Defekt melden", symbol: "exclamationmark.bubble") {
                        showClaimPicker = true
                    }
                    .disabled(products.isEmpty)
                }

                if let warning = reminderWarning {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(warning.title).font(.subheadline.weight(.semibold))
                                Text(warning.message).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell.slash").foregroundStyle(.orange)
                        }
                        if reminders.authorization == .notDetermined {
                            Button("Mitteilungen erlauben") {
                                Task {
                                    await reminders.requestAuthorization()
                                }
                            }
                        } else if reminders.authorization == .denied {
                            Button("Einstellungen öffnen") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                }

                if !openClaims.isEmpty {
                    Section("Offene Reklamationen") {
                        ForEach(openClaims) { claim in
                            NavigationLink(value: claim) {
                                ClaimRow(claim: claim)
                            }
                        }
                    }
                }

                Section {
                    if upcoming.isEmpty {
                        Text(products.isEmpty ? "Erfasse deinen ersten Beleg, um Fristen zu verfolgen." : "Keine laufenden Fristen.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming.prefix(6), id: \.1.id) { product, coverage in
                        NavigationLink(value: product) {
                            DeadlineListRow(product: product, coverage: coverage)
                        }
                    }
                    if upcoming.count > 6 {
                        Button("Alle Fristen anzeigen") { router.selectedTab = .deadlines }
                    }
                } header: {
                    Text("Nächste Fristen")
                }

                if !store.isPro {
                    Section {
                        Button {
                            router.requestPro(reason: nil)
                        } label: {
                            HStack {
                                Image(systemName: "star.circle.fill").foregroundStyle(.yellow).font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Kaufarchiv Pro").font(.headline)
                                    Text("\(products.count) von \(Entitlements.freeProductLimit) Gratisprodukten belegt")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Übersicht")
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .navigationDestination(for: Claim.self) { ClaimDetailView(claim: $0) }
            .sheet(isPresented: $showClaimPicker) {
                ProductPickerView(products: activeProducts) { product in
                    showClaimPicker = false
                    claimProduct = product
                }
            }
            .sheet(item: $claimProduct) { product in
                ClaimWizardView(product: product)
            }
            .task { await reminders.refreshAuthorization() }
        }
    }

    private var reminderWarning: (title: String, message: String)? {
        guard !products.isEmpty else { return nil }
        switch reminders.authorization {
        case .denied:
            return ("Erinnerungen sind ausgeschaltet", "Ohne Mitteilungen kann Kaufarchiv dich nicht an Fristen erinnern.")
        case .notDetermined:
            return ("Erinnerungen aktivieren", "Erlaube Mitteilungen, damit du keine Rückgabe- oder Garantiefrist verpasst.")
        default:
            if let plan = reminders.lastPlan, let openBefore = plan.openAppBefore {
                return ("\(plan.deferred.count) Erinnerungen noch nicht geplant",
                        "iOS erlaubt nur eine begrenzte Anzahl. Öffne die App vor dem \(Formatters.date(openBefore)), dann werden die nächsten geplant.")
            }
            return nil
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(highlight ? Color.orange : Color.accentColor)
            Text(value)
                .font(.title.bold())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.medium))
        }
    }
}

struct DeadlineListRow: View {
    let product: Product
    let coverage: Coverage

    var body: some View {
        HStack(spacing: 12) {
            ProductIcon(product: product, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).lineLimit(1)
                Text("\(coverage.kind.title) · \(coverage.endDate.map(Formatters.date) ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DeadlineBadge(status: coverage.status)
        }
    }
}

/// Lets the user pick a product, e.g. for a claim.
struct ProductPickerView: View {
    let products: [Product]
    var onPick: (Product) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Product] {
        search.isEmpty ? products : products.filter { SearchNormalizer.matches(query: search, in: $0.searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { product in
                Button {
                    onPick(product)
                } label: {
                    ProductRow(product: product)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "z. B. Kaffeemaschine")
            .navigationTitle("Welches Produkt?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}
