import SwiftUI
import StoreKit
import KaufarchivCore

/// Purchase page. All prices are loaded from StoreKit; nothing is hard-coded.
struct PaywallView: View {
    var reason: String?

    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = StoreService.ProductID.yearly
    @State private var purchasing = false
    @State private var error: String?
    @State private var pendingInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                        Text("Kaufarchiv Pro")
                            .font(.largeTitle.bold())
                        if let reason {
                            Text(reason)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        Feature(symbol: "infinity", title: "Unbegrenzte Produkte", text: "Statt \(Entitlements.freeProductLimit) Produkten in der Gratisversion.")
                        Feature(symbol: "icloud", title: "iCloud auf allen Geräten", text: "Privat und verschlüsselt in deinem iCloud-Konto.")
                        Feature(symbol: "doc.richtext", title: "Reklamationsdossier", text: "Rechnung, Seriennummer, Fotos und Verlauf in einem PDF.")
                        Feature(symbol: "heart", title: "Unabhängige Entwicklung", text: "Keine Werbung, kein Tracking.")
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if store.products.isEmpty {
                        if store.isLoading {
                            ProgressView()
                        } else {
                            VStack(spacing: 8) {
                                Text(store.loadError ?? "Die Angebote sind gerade nicht verfügbar.")
                                    .foregroundStyle(.secondary)
                                Button("Erneut versuchen") { Task { await store.loadProducts() } }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products, id: \.id) { product in
                                OfferRow(product: product, selected: product.id == selectedID)
                                    .onTapGesture { selectedID = product.id }
                            }
                        }
                        Button {
                            Task { await buy() }
                        } label: {
                            Group {
                                if purchasing { ProgressView() } else { Text(buttonTitle).font(.headline) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchasing)
                    }

                    VStack(spacing: 6) {
                        Text("Deine Belege und der vollständige Export bleiben immer verfügbar – auch ohne Pro und nach einem Abo-Ende.")
                        Text("Das Jahresabo verlängert sich automatisch, wenn es nicht mindestens 24 Stunden vor Ablauf in den Einstellungen der Apple-ID gekündigt wird.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button("Käufe wiederherstellen") {
                            Task {
                                try? await store.restore()
                                if store.isPro { dismiss() }
                            }
                        }
                        Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { dismiss() } }
            }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert("Kauf nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .alert("Kauf ausstehend", isPresented: $pendingInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Der Kauf muss noch bestätigt werden, z. B. durch die Familienfreigabe. Pro wird danach automatisch aktiviert.")
            }
        }
    }

    private var selected: StoreKit.Product? { store.products.first { $0.id == selectedID } }

    private var buttonTitle: String {
        guard let selected else { return "Weiter" }
        if selected.id == StoreService.ProductID.yearly, let offer = selected.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "Kostenlos testen"
        }
        return "Für \(selected.displayPrice) freischalten"
    }

    private func buy() async {
        guard let selected else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await store.purchase(selected) {
            case .success: dismiss()
            case .pending: pendingInfo = true
            case .cancelled: break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OfferRow: View {
    let product: StoreKit.Product
    let selected: Bool

    var body: some View {
        HStack {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.id == StoreService.ProductID.lifetime ? "Dauerhaft" : "Jährlich")
                    .font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.displayPrice).font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var subtitle: String {
        if product.id == StoreService.ProductID.lifetime { return "Einmalkauf, kein Abo" }
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "\(offer.period.value) \(unit(offer.period.unit)) gratis, danach \(product.displayPrice) pro Jahr"
        }
        return "Pro Jahr, jederzeit kündbar"
    }

    private func unit(_ unit: StoreKit.Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: "Tage"
        case .week: "Wochen"
        case .month: "Monate"
        case .year: "Jahre"
        @unknown default: ""
        }
    }
}
