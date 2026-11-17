import SwiftUI
import KaufarchivCore

extension DeadlineStatus {
    var color: Color {
        switch self {
        case .active: .green
        case .soon, .endsToday: .orange
        case .expired: .secondary
        case .unknown: .secondary
        }
    }
}

/// Capsule showing the remaining time of a coverage.
struct DeadlineBadge: View {
    let status: DeadlineStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Frist: \(status.label)")
    }
}

/// Row with title, dates and progress bar of one coverage.
struct CoverageRow: View {
    let coverage: Coverage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(coverage.kind.title, systemImage: coverage.kind.symbolName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                DeadlineBadge(status: coverage.status)
            }
            ProgressView(value: coverage.progress)
                .tint(coverage.status.color)
            HStack {
                Text(Formatters.date(coverage.startDate))
                Spacer()
                if let end = coverage.endDate {
                    Text("bis \(Formatters.date(end))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !coverage.confirmed {
                SuggestionBadge(text: "Vorschlag – bitte prüfen")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Marks a value the app recognised but is not sure about.
struct SuggestionBadge: View {
    var text = "Vorschlag"

    var body: some View {
        Label(text, systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.12), in: Capsule())
    }
}

/// Thumbnail of a stored document.
struct DocumentThumbnail: View {
    let document: StoredDocument
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let data = document.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: document.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .frame(width: size, height: size * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
        .accessibilityLabel(document.title)
    }
}

/// Product list row.
struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            ProductIcon(product: product)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if product.status.isClosed {
                Text(product.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let next = product.nextDeadline {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(next.kind.shortTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    DeadlineBadge(status: next.status)
                }
            } else {
                Text("abgelaufen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var secondary: String {
        var parts: [String] = []
        if let merchant = product.purchase?.merchant, !merchant.isEmpty { parts.append(merchant) }
        parts.append(Formatters.date(product.purchaseDate))
        if let price = product.price { parts.append(Formatters.money(price, currency: product.purchase?.currency ?? "CHF")) }
        return parts.joined(separator: " · ")
    }
}

struct ProductIcon: View {
    let product: Product
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo = product.documentList.first(where: { $0.kind == .photo })?.thumbnail, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: CategoryCatalog.symbol(for: product.category))
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

enum CategoryCatalog {
    static let all: [(name: String, symbol: String)] = [
        ("Computer", "laptopcomputer"),
        ("Smartphone & Tablet", "iphone"),
        ("TV & Audio", "tv"),
        ("Foto & Video", "camera"),
        ("Haushalt", "house"),
        ("Küche", "fork.knife"),
        ("Werkzeug & Garten", "hammer"),
        ("Möbel", "sofa"),
        ("Sport & Freizeit", "bicycle"),
        ("Kleidung", "tshirt"),
        ("Spiele", "gamecontroller"),
        ("Fahrzeug", "car"),
        ("Andere", "shippingbox")
    ]

    static func symbol(for category: String) -> String {
        all.first { $0.name == category }?.symbol ?? "shippingbox"
    }
}

/// Labeled value used in detail screens; hides itself when empty.
struct InfoRow: View {
    let label: String
    let value: String
    var copyable = false

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .contextMenu {
                if copyable {
                    Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
                }
            }
        }
    }
}

/// Decimal text field that accepts both "12.50" and "12,50".
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { text = value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" }
            .onChange(of: text) { _, new in
                value = new.isEmpty ? nil : MoneyParser.parseAmount(new)
            }
            .onChange(of: value) { _, new in
                guard !focused else { return }
                text = new.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            }
    }
}

struct CountryPicker: View {
    @Binding var code: String

    var body: some View {
        Picker("Land", selection: $code) {
            ForEach(LegalRules.all) { rules in
                Text(rules.name).tag(rules.code)
            }
        }
    }
}
