import SwiftUI
import SwiftData
import KaufarchivCore

struct PurchasesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(StoreService.self) private var store
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    enum Filter: String, CaseIterable, Identifiable {
        case all, protected, expired, archived
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .protected: "Geschützt"
            case .expired: "Abgelaufen"
            case .archived: "Archiv"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, name, deadline, price
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: "Neueste zuerst"
            case .oldest: "Älteste zuerst"
            case .name: "Name"
            case .deadline: "Nächste Frist"
            case .price: "Preis"
            }
        }
    }

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .newest
    @State private var groupByRoom = false
    @State private var path = NavigationPath()

    private var filtered: [Product] {
        var list = products.filter { product in
            switch filter {
            case .all: !product.status.isClosed
            case .protected: !product.status.isClosed && product.bestActiveCoverage != nil
            case .expired: !product.status.isClosed && product.bestActiveCoverage == nil
            case .archived: product.status.isClosed
            }
        }
        if !search.isEmpty {
            list = list.filter { SearchNormalizer.matches(query: search, in: $0.searchText) }
        }
        switch sort {
        case .newest: list.sort { $0.purchaseDate > $1.purchaseDate }
        case .oldest: list.sort { $0.purchaseDate < $1.purchaseDate }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .deadline: list.sort { ($0.nextDeadline?.endDate ?? .distantFuture) < ($1.nextDeadline?.endDate ?? .distantFuture) }
        case .price: list.sort { ($0.price ?? 0) > ($1.price ?? 0) }
        }
        return list
    }

    private var grouped: [(String, [Product])] {
        let dict = Dictionary(grouping: filtered) { $0.room.isEmpty ? "Ohne Raum" : $0.room }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                if groupByRoom {
                    ForEach(grouped, id: \.0) { room, items in
                        Section(room) {
                            ForEach(items) { row($0) }
                        }
                    }
                } else {
                    ForEach(filtered) { row($0) }
                }
            }
            .overlay {
                if products.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Käufe", systemImage: "shippingbox")
                    } description: {
                        Text("Fotografiere eine Rechnung oder importiere ein PDF.")
                    } actions: {
                        Button("Beleg erfassen") { router.showImport = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("Keine Produkte in „\(filter.title)“", systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Produkt, Händler, Seriennummer, Belegtext")
            .navigationTitle("Meine Käufe")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if !store.isPro && products.count >= Entitlements.freeProductLimit {
                            router.requestPro(reason: "Die Gratisversion umfasst \(Entitlements.freeProductLimit) Produkte.")
                        } else {
                            router.pendingInbox = []
                            router.showImport = true
                        }
                    } label: {
                        Label("Beleg erfassen", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sortierung", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Nach Raum gruppieren", isOn: $groupByRoom)
                    } label: {
                        Label("Sortieren", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .navigationDestination(for: Claim.self) { ClaimDetailView(claim: $0) }
            .onChange(of: router.openProductID, initial: true) { _, id in
                guard let id, let product = products.first(where: { $0.id == id }) else { return }
                path = NavigationPath()
                path.append(product)
                router.openProductID = nil
            }
        }
    }

    private func row(_ product: Product) -> some View {
        NavigationLink(value: product) {
            ProductRow(product: product)
        }
    }
}
