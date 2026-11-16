import SwiftUI
import SwiftData
import KaufarchivCore

// MARK: Übersicht

struct OverviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PurchaseManager.self) private var purchases
    @Environment(ReminderCenter.self) private var reminders
    @Query(sort: \OwnedProduct.createdAt, order: .reverse) private var products: [OwnedProduct]
    @Query(sort: \Coverage.endDate) private var coverages: [Coverage]
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]

    @State private var showClaimPicker = false
    @State private var showPaywall = false
    @State private var inboxError: String?

    private var activeProducts: [OwnedProduct] { products.filter { $0.status == .active } }

    private var upcoming: [Coverage] {
        coverages.filter { $0.isActive() && $0.product?.status == .active }
    }

    private var openClaims: [Claim] { claims.filter { $0.status.isOpen } }

    var body: some View {
        List {
            if DataController.isTemporaryStore {
                Section {
                    Label("Der Datenspeicher konnte nicht geöffnet werden. Änderungen gehen beim Beenden verloren. Bitte App neu starten und genügend freien Speicher sicherstellen.",
                          systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    router.startImport()
                } label: {
                    Label("Beleg erfassen", systemImage: "doc.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button {
                    showClaimPicker = true
                } label: {
                    Label("Etwas ist kaputt – Reklamation starten", systemImage: "wrench.and.screwdriver")
                }
                .disabled(activeProducts.isEmpty)
            }

            if !router.inbox.isEmpty {
                Section {
                    ForEach(router.inbox) { item in
                        Button {
                            do {
                                try router.open(item)
                            } catch {
                                inboxError = error.localizedDescription
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray.and.arrow.down")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).foregroundStyle(.primary).lineLimit(1)
                                    Text("Übernommen am \(Fmt.dateTime(item.addedAt)) · noch nicht erfasst")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) { router.discard(item) }
                        }
                    }
                } header: {
                    Text("Eingang (\(router.inbox.count))")
                } footer: {
                    Text("Geteilte Belege und gesicherte Entwürfe. Antippen, um die Erfassung abzuschliessen.")
                }
            }

            if products.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Noch keine Käufe",
                        systemImage: "shippingbox",
                        description: Text("Erfasse deinen ersten Beleg. Rechnung fotografieren, Produkte auswählen, Fristen bestätigen – fertig.")
                    )
                }
            } else {
                Section("Auf einen Blick") {
                    LabeledContent("Produkte im Besitz", value: "\(activeProducts.count)")
                    ForEach(valueByCurrency, id: \.currency) { entry in
                        LabeledContent("Kaufwert \(entry.currency)", value: Money.format(cents: entry.cents, currency: entry.currency))
                    }
                    LabeledContent("Laufende Fristen", value: "\(upcoming.count)")
                    if !purchases.isPro {
                        Button {
                            showPaywall = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Kostenlos: \(min(products.count, Prefs.freeProductLimit)) von \(Prefs.freeProductLimit) Produkten")
                                        .font(.footnote)
                                    Spacer()
                                    ProBadge()
                                }
                                ProgressView(value: Double(min(products.count, Prefs.freeProductLimit)), total: Double(Prefs.freeProductLimit))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !openClaims.isEmpty {
                    Section("Offene Fälle") {
                        ForEach(openClaims) { claim in
                            NavigationLink {
                                ClaimDetailView(claim: claim)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(claim.product?.displayName ?? "Produkt").font(.body.weight(.medium))
                                    Text("\(claim.kind.label) · \(claim.status.label) · seit \(Fmt.date(claim.createdAt))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    if upcoming.isEmpty {
                        Text("Keine laufenden Fristen.").foregroundStyle(.secondary)
                    }
                    ForEach(upcoming.prefix(5)) { coverage in
                        if let product = coverage.product {
                            NavigationLink {
                                ProductDetailView(product: product)
                            } label: {
                                CoverageRow(coverage: coverage, showProduct: true)
                            }
                        }
                    }
                    if upcoming.count > 5 {
                        Button("Alle Fristen anzeigen") { router.tab = .deadlines }
                    }
                } header: {
                    Text("Nächste Fristen")
                } footer: {
                    if !reminders.isAuthorized && !upcoming.isEmpty {
                        Text("Mitteilungen sind ausgeschaltet – du wirst nicht an Fristen erinnert. Aktiviere sie unter Einstellungen › Erinnerungen.")
                    }
                }

                Section("Zuletzt erfasst") {
                    ForEach(products.prefix(4)) { product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            ProductRow(product: product)
                        }
                    }
                }
            }
        }
        .navigationTitle("Kaufarchiv")
        .sheet(isPresented: $showClaimPicker) {
            ClaimStartView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: nil)
        }
        .alert("Beleg konnte nicht geöffnet werden", isPresented: Binding(get: { inboxError != nil }, set: { if !$0 { inboxError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inboxError ?? "")
        }
    }

    private var valueByCurrency: [(currency: String, cents: Int)] {
        var totals: [String: Int] = [:]
        for product in activeProducts {
            guard let price = product.priceCents else { continue }
            totals[product.currency, default: 0] += price * max(product.quantity, 1)
        }
        return totals.map { (currency: $0.key, cents: $0.value) }.sorted { $0.currency < $1.currency }
    }
}

struct ProductRow: View {
    let product: OwnedProduct

    var body: some View {
        HStack(spacing: 12) {
            if let document = product.allDocuments.first {
                DocumentThumbnail(document: document, size: 40)
            } else {
                Image(systemName: "shippingbox")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 52)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text("\(product.receipt?.displayMerchant ?? "Ohne Rechnung") · \(Fmt.date(product.purchaseDate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 0)
            if let price = product.priceCents {
                Text(Money.format(cents: price, currency: product.currency))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if product.status != .active {
            Text(product.status.label).font(.caption).foregroundStyle(.secondary)
        } else if let next = product.nextDeadline() {
            let days = next.daysRemaining()
            HStack(spacing: 4) {
                Text("\(next.kind.shortLabel): \(Fmt.remaining(days: days))")
                    .font(.caption)
                    .foregroundStyle(next.isConfirmed ? Color.deadline(daysRemaining: days) : Color.secondary)
                if !next.isConfirmed { SuggestionBadge() }
            }
        } else if !product.coverageList.isEmpty {
            Text("Alle Fristen abgelaufen").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Meine Käufe

enum PurchaseSort: String, CaseIterable, Identifiable {
    case newest, name, price, deadline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Neueste zuerst"
        case .name: return "Name"
        case .price: return "Preis"
        case .deadline: return "Nächste Frist"
        }
    }
}

struct PurchasesView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \OwnedProduct.createdAt, order: .reverse) private var products: [OwnedProduct]

    @State private var query = ""
    @State private var sort: PurchaseSort = .newest
    @State private var categoryFilter = ""
    @State private var showInactive = true

    private var categories: [String] {
        Array(Set(products.map { $0.category }.filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [OwnedProduct] {
        var result = products.filter { product in
            (showInactive || product.status == .active)
                && (categoryFilter.isEmpty || product.category == categoryFilter)
                && product.matches(query)
        }
        switch sort {
        case .newest:
            result.sort { $0.purchaseDate > $1.purchaseDate }
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .price:
            result.sort { ($0.priceCents ?? 0) > ($1.priceCents ?? 0) }
        case .deadline:
            result.sort {
                ($0.nextDeadline()?.endDate ?? .distantFuture) < ($1.nextDeadline()?.endDate ?? .distantFuture)
            }
        }
        return result
    }

    var body: some View {
        List {
            if products.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Käufe", systemImage: "shippingbox")
                } description: {
                    Text("Hier erscheinen alle Produkte mit Rechnung, Fristen und Unterlagen.")
                } actions: {
                    Button("Beleg erfassen") { router.startImport() }
                        .buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(filtered) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        ProductRow(product: product)
                    }
                }
            }
        }
        .navigationTitle("Meine Käufe")
        .searchable(text: $query, prompt: "Produkt, Händler, Seriennummer, Belegtext")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sortierung", selection: $sort) {
                        ForEach(PurchaseSort.allCases) { Text($0.label).tag($0) }
                    }
                    if !categories.isEmpty {
                        Picker("Kategorie", selection: $categoryFilter) {
                            Text("Alle Kategorien").tag("")
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Toggle("Auch zurückgegebene und verkaufte", isOn: $showInactive)
                } label: {
                    Label("Filter", systemImage: categoryFilter.isEmpty && showInactive
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.startImport()
                } label: {
                    Label("Beleg erfassen", systemImage: "plus")
                }
            }
        }
    }
}
