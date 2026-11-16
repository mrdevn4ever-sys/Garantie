import SwiftUI
import PhotosUI
import VisionKit
import EventKit
import EventKitUI
import UniformTypeIdentifiers
import KaufarchivCore

// MARK: Kleine Bausteine

struct SuggestionBadge: View {
    var text = "Vorschlag"

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
            .accessibilityLabel("Unbestätigter Vorschlag")
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

struct CountryPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Kaufland", selection: $selection) {
            ForEach(DeadlineRules.countries) { country in
                Text(country.name).tag(country.code)
            }
        }
    }
}

enum Catalog {
    static let categories = [
        "Elektronik", "Haushaltgeräte", "Küche", "Möbel", "Werkzeug", "Sport & Freizeit",
        "Mode & Uhren", "Auto & Velo", "Garten", "Kinder", "Sonstiges"
    ]
    static let rooms = ["Wohnzimmer", "Küche", "Schlafzimmer", "Büro", "Bad", "Keller", "Garage", "Kinderzimmer"]
    static let currencies = ["CHF", "EUR", "USD", "GBP"]
}

extension Color {
    static func deadline(daysRemaining: Int) -> Color {
        if daysRemaining < 0 { return .secondary }
        if daysRemaining <= 7 { return .red }
        if daysRemaining <= 30 { return .orange }
        return .green
    }
}

/// Zeile für eine Frist – in Übersicht, Fristenliste und Produktakte verwendet.
struct CoverageRow: View {
    let coverage: Coverage
    var showProduct = false

    var body: some View {
        let days = coverage.daysRemaining()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.deadline(daysRemaining: days))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                if showProduct {
                    Text(coverage.product?.displayName ?? "Produkt")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(coverage.kind.label)
                        .font(showProduct ? .subheadline : .body)
                        .foregroundStyle(showProduct ? .secondary : .primary)
                    if !coverage.isConfirmed { SuggestionBadge() }
                }
                Text("bis \(Fmt.date(coverage.endDate)) · \(Fmt.remaining(days: days))")
                    .font(.footnote)
                    .foregroundStyle(Color.deadline(daysRemaining: days))
                if !showProduct, days >= 0 {
                    ProgressView(value: coverage.progress())
                        .tint(Color.deadline(daysRemaining: days))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch coverage.kind {
        case .returnWindow: return "arrow.uturn.backward.circle"
        case .legal: return "building.columns"
        case .manufacturer: return "checkmark.shield"
        case .extended: return "plus.circle"
        }
    }
}

struct DocumentThumbnail: View {
    let document: StoredDocument
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
            if let data = document.previewData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: document.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
    }
}

// MARK: Fundstelle im Beleg

struct EvidenceItem: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var image: UIImage
    var box: NormRect?
}

/// Zeigt, an welcher Stelle des Belegs ein Wert erkannt wurde.
struct EvidenceView: View {
    let item: EvidenceItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.caption).foregroundStyle(.secondary)
                        Text(item.value.isEmpty ? "–" : item.value).font(.headline)
                    }
                    .padding(.horizontal)

                    if item.box == nil {
                        Label("Für diesen Wert gibt es keine eindeutige Fundstelle.", systemImage: "questionmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            GeometryReader { proxy in
                                if let box = item.box {
                                    let width = max(box.width * proxy.size.width + 10, 24)
                                    let height = max(box.height * proxy.size.height + 8, 18)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.yellow.opacity(0.28))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange, lineWidth: 2))
                                        .frame(width: width, height: height)
                                        .position(
                                            x: (box.x + box.width / 2) * proxy.size.width,
                                            y: (box.y + box.height / 2) * proxy.size.height
                                        )
                                }
                            }
                        }
                }
                .padding(.vertical)
            }
            .navigationTitle("Fundstelle im Beleg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

extension StoredDocument {
    /// Baut die Fundstellenansicht für eine gespeicherte Zeile dieses Dokuments.
    func evidence(title: String, value: String, lineIndex: Int) -> EvidenceItem? {
        guard let data = originalData else { return nil }
        let allLines = lines
        let line = allLines.indices.contains(lineIndex) ? allLines[lineIndex] : nil
        guard let image = DocumentRenderer.pageImage(data: data, typeIdentifier: typeIdentifier, page: line?.page ?? 0) else {
            return nil
        }
        return EvidenceItem(title: title, value: value, image: image, box: line?.box)
    }

    func temporaryFileURL() -> URL? {
        guard let data = originalData else { return nil }
        return try? TempFiles.write(data, name: filename.isEmpty ? displayTitle : filename)
    }
}

// MARK: Dokumente hinzufügen (Scan, Foto, Datei)

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}

/// Bündelt Scanner, Fotoauswahl und Dateiauswahl hinter drei Schaltern.
struct DocumentPickers: ViewModifier {
    @Binding var showScanner: Bool
    @Binding var showPhotos: Bool
    @Binding var showFiles: Bool
    var onImport: (ImportedFile) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(
                    onFinish: { images in
                        showScanner = false
                        if !images.isEmpty { onImport(ImportedFile.from(scannedPages: images)) }
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        onImport(ImportedFile.from(imageData: data))
                    } else {
                        errorMessage = "Das Foto konnte nicht geladen werden."
                    }
                    photoItem = nil
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { result in
                switch result {
                case .success(let url):
                    do {
                        onImport(try ImportedFile.from(url: url))
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

/// Menü «Dokument hinzufügen» für Produktakte und Reklamation.
struct AddDocumentMenu<MenuLabel: View>: View {
    var onImport: (ImportedFile) -> Void
    @ViewBuilder var label: () -> MenuLabel

    @State private var showScanner = false
    @State private var showPhotos = false
    @State private var showFiles = false

    var body: some View {
        Menu {
            if VNDocumentCameraViewController.isSupported {
                Button("Dokument scannen", systemImage: "doc.viewfinder") { showScanner = true }
            }
            Button("Foto auswählen", systemImage: "photo") { showPhotos = true }
            Button("Datei auswählen", systemImage: "folder") { showFiles = true }
        } label: {
            label()
        }
        .modifier(DocumentPickers(showScanner: $showScanner, showPhotos: $showPhotos, showFiles: $showFiles, onImport: onImport))
    }
}

// MARK: Kalenderübergabe

/// Übergibt eine Frist an die Kalender-App. Die Systemansicht läuft getrennt von der App,
/// deshalb braucht Kaufarchiv dafür keinen Zugriff auf den Kalender.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let date: Date
    let notes: String
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = date
        event.endDate = date
        event.isAllDay = true
        event.notes = notes
        event.addAlarm(EKAlarm(relativeOffset: -7 * 86_400))
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}

struct CalendarRequest: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var notes: String

    init(coverage: Coverage) {
        let product = coverage.product?.displayName ?? "Produkt"
        title = "\(coverage.kind.label) endet: \(product)"
        date = coverage.endDate
        var text = "Aus Kaufarchiv."
        if let merchant = coverage.product?.receipt?.merchant, !merchant.isEmpty { text += " Gekauft bei \(merchant)." }
        notes = text
    }
}
