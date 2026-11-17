import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import KaufarchivCore

/// The five-step capture flow:
/// 1. Beleg aufnehmen/importieren  2. Produkte auswählen  3. Angaben prüfen
/// 4. Fristen bestätigen  5. Speichern
struct ImportFlowView: View {
    var initialFiles: [IncomingFile] = []
    var onFinish: (Purchase?) -> Void

    enum Step: Int, CaseIterable {
        case source, items, review, coverages

        var title: String {
            switch self {
            case .source: "Beleg"
            case .items: "Produkte"
            case .review: "Prüfen"
            case .coverages: "Fristen"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @Environment(ReminderService.self) private var reminders
    @AppStorage(SettingsKey.defaultCountry) private var defaultCountry = "CH"
    @Query private var allProducts: [Product]

    @State private var draft: ImportDraft?
    @State private var step: Step = .source
    @State private var saveError: String?
    @State private var showPaywall = false
    @State private var startedAt = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    content(draft)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { onFinish(nil) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(step != .source)
        .onAppear {
            guard draft == nil else { return }
            let d = ImportDraft(defaultCountry: defaultCountry)
            draft = d
            if !initialFiles.isEmpty {
                step = .items
                Task { await d.add(files: initialFiles) }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Mit Pro speicherst du unbegrenzt viele Produkte.")
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private func content(_ draft: ImportDraft) -> some View {
        VStack(spacing: 0) {
            StepIndicator(current: step)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            switch step {
            case .source:
                SourceStepView(draft: draft) { step = .items }
            case .items:
                ItemsStepView(draft: draft, remainingFree: remainingFree, isPro: store.isPro,
                              onPaywall: { showPaywall = true },
                              onNext: { step = .review })
            case .review:
                ReviewStepView(draft: draft, onNext: { step = .coverages })
            case .coverages:
                CoverageStepView(draft: draft, onSave: { save(draft) })
            }
        }
        .navigationTitle(step.title)
        .toolbar {
            if step != .source {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
                    } label: {
                        Label("Zurück", systemImage: "chevron.backward")
                    }
                }
            }
        }
    }

    private var remainingFree: Int {
        max(Entitlements.freeProductLimit - allProducts.count, 0)
    }

    private func save(_ draft: ImportDraft) {
        guard Entitlements.canAddProducts(existing: allProducts.count, adding: draft.selectedItems.count, isPro: store.isPro) else {
            showPaywall = true
            return
        }
        do {
            let purchase = try draft.save(in: context)
            Task { await reminders.reschedule(context: context) }
            onFinish(purchase)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct StepIndicator: View {
    let current: ImportFlowView.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ImportFlowView.Step.allCases, id: \.self) { step in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color(.systemFill))
                        .frame(height: 4)
                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(current.rawValue + 1) von \(ImportFlowView.Step.allCases.count): \(current.title)")
    }
}

// MARK: - Step 1: Source

private struct SourceStepView: View {
    @Bindable var draft: ImportDraft
    var onNext: () -> Void

    @State private var showScanner = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("Beleg erfassen")
                        .font(.title2.bold())
                    Text("Fotografiere die Rechnung oder wähle ein PDF. Die Erkennung läuft vollständig auf deinem Gerät.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)

                if DocumentScannerView.isAvailable {
                    SourceButton(title: "Beleg scannen", subtitle: "Mehrseitig, mit automatischem Zuschnitt", symbol: "camera.viewfinder") {
                        showScanner = true
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    SourceButtonLabel(title: "Aus Fotos", subtitle: "Screenshot oder Foto eines Belegs", symbol: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                SourceButton(title: "Aus Dateien", subtitle: "PDF-Rechnung, z. B. aus einer E-Mail", symbol: "folder") {
                    showFiles = true
                }
                SourceButton(title: "Ohne Beleg erfassen", subtitle: "Angaben von Hand eintragen", symbol: "square.and.pencil") {
                    draft.items = [DraftItem(selected: true, name: "")]
                    draft.phase = .ready
                    onNext()
                }

                Label("Tipp: In Mail oder Dateien kannst du eine Rechnung auch über „Teilen › Im Kaufarchiv sichern“ übernehmen.", systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { images in
                showScanner = false
                // Multi-page scans become one PDF so the pages stay together.
                let files = [makePDF(from: images)].compactMap { $0 }
                start(files)
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                let files = urls.compactMap { try? IncomingFile.file(at: $0) }
                if files.isEmpty { error = "Die Dateien konnten nicht gelesen werden." } else { start(files) }
            case let .failure(err):
                error = err.localizedDescription
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var files: [IncomingFile] = []
                for (index, item) in items.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let type = item.supportedContentTypes.first ?? .jpeg
                    files.append(IncomingFile(data: data, filename: "Foto-\(index + 1).\(type.preferredFilenameExtension ?? "jpg")", type: type))
                }
                photoItems = []
                if files.isEmpty { error = "Die Fotos konnten nicht geladen werden." } else { start(files) }
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func start(_ files: [IncomingFile]) {
        onNext()
        Task { await draft.add(files: files) }
    }

    private func makePDF(from images: [UIImage]) -> IncomingFile? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return IncomingFile.image(images[0], name: "Scan") }
        let first = images[0].size
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first))
        let data = renderer.pdfData { ctx in
            for image in images {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: image.size), pageInfo: [:])
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        return IncomingFile(data: data, filename: "Scan.pdf", type: .pdf)
    }
}

private struct SourceButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SourceButtonLabel(title: title, subtitle: subtitle, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct SourceButtonLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}

// MARK: - Step 2: Items

private struct ItemsStepView: View {
    @Bindable var draft: ImportDraft
    let remainingFree: Int
    let isPro: Bool
    var onPaywall: () -> Void
    var onNext: () -> Void

    var body: some View {
        switch draft.phase {
        case .idle, .recognizing:
            VStack(spacing: 16) {
                if case let .recognizing(progress) = draft.phase {
                    ProgressView(value: progress)
                        .frame(maxWidth: 220)
                }
                ProgressView()
                Text("Beleg wird gelesen …")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Erkennung fehlgeschlagen", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            itemList
        }
    }

    private var exceedsFree: Bool { !isPro && draft.selectedItems.count > remainingFree }

    private var itemList: some View {
        List {
            Section {
                ForEach($draft.items) { $item in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            item.selected.toggle()
                        } label: {
                            Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(item.selected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.selected ? "Ausgewählt" : "Nicht ausgewählt")
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Produktname", text: $item.name, axis: .vertical)
                                .font(.body.weight(.medium))
                            HStack {
                                if item.quantity > 1 {
                                    Text("\(item.quantity) ×")
                                        .foregroundStyle(.secondary)
                                }
                                DecimalField(title: "Preis", value: $item.price)
                                    .frame(maxWidth: 120)
                                Text(draft.currency).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            if item.looksLikeService {
                                Text("Sieht nach Gebühr oder Dienstleistung aus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                Button {
                    draft.addManualItem()
                } label: {
                    Label("Produkt hinzufügen", systemImage: "plus")
                }
            } header: {
                Text(draft.parsed.items.isEmpty ? "Produkt" : "Welche Produkte möchtest du verwalten?")
            } footer: {
                Text("Jedes ausgewählte Produkt erhält eigene Fristen und bleibt mit derselben Originalrechnung verbunden.")
            }

            if exceedsFree {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Die Gratisversion umfasst \(Entitlements.freeProductLimit) Produkte. Du kannst noch \(remainingFree) hinzufügen.")
                        Button("Pro ansehen", action: onPaywall)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Weiter", enabled: !draft.selectedItems.isEmpty && draft.selectedItems.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }, action: onNext)
        }
    }
}

struct NextButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
        .padding()
        .background(.bar)
    }
}

// MARK: - Step 3: Review

private struct ReviewStepView: View {
    @Bindable var draft: ImportDraft
    var onNext: () -> Void

    @State private var preview: SourceLocation?

    var body: some View {
        Form {
            Section {
                field(.merchant, source: draft.parsed.merchant?.source) {
                    TextField("Händler", text: $draft.merchant)
                }
                field(.date, source: draft.parsed.purchaseDate?.source) {
                    DatePicker("Kaufdatum", selection: $draft.purchaseDate, in: ...Date(), displayedComponents: .date)
                }
                field(.total, source: draft.parsed.total?.source) {
                    HStack {
                        Text("Total")
                        Spacer()
                        DecimalField(title: "Betrag", value: $draft.total)
                        Picker("Währung", selection: $draft.currency) {
                            ForEach(["CHF", "EUR", "USD", "GBP"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                field(.orderNumber, source: draft.parsed.orderNumber?.source) {
                    TextField("Beleg-/Bestellnummer", text: $draft.orderNumber)
                }
            } header: {
                Text("Beleg")
            } footer: {
                Text("Tippe auf das Dokumentsymbol, um die Stelle im Beleg zu sehen. Mit ✦ markierte Werte sind Vorschläge.")
            }

            Section("Wo gekauft?") {
                field(.channel, source: draft.parsed.channel?.source) {
                    Picker("Kaufart", selection: $draft.channel) {
                        Text("Im Geschäft").tag(SalesChannel.store)
                        Text("Online/Versand").tag(SalesChannel.online)
                    }
                }
                field(.country, source: draft.parsed.countryCode?.source) {
                    CountryPicker(code: $draft.countryCode)
                        .onChange(of: draft.countryCode) { _, _ in draft.countryChanged() }
                }
                if draft.channel == .online {
                    Toggle("Lieferdatum abweichend", isOn: $draft.hasDeliveryDate)
                    if draft.hasDeliveryDate {
                        DatePicker("Geliefert am", selection: $draft.deliveryDate, in: draft.purchaseDate..., displayedComponents: .date)
                    }
                }
            }

            ForEach($draft.items) { $item in
                if item.selected {
                    Section {
                        HStack {
                            TextField("Produktname", text: $item.name)
                            if let source = item.source {
                                sourceButton(source)
                            }
                        }
                        TextField("Marke", text: $item.brand)
                        TextField("Modell", text: $item.modelName)
                        TextField("Seriennummer", text: $item.serialNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Picker("Kategorie", selection: $item.category) {
                            Text("Keine").tag("")
                            ForEach(CategoryCatalog.all, id: \.name) { Text($0.name).tag($0.name) }
                        }
                    } header: {
                        Text(item.name.isEmpty ? "Produkt" : item.name)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Weiter zu den Fristen", enabled: !draft.selectedItems.isEmpty, action: onNext)
        }
        .sheet(item: $preview) { source in
            DraftSourcePreview(draft: draft, source: source)
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ field: ImportDraft.Field, source: SourceLocation?, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            if draft.suggestedFields.contains(field) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Vorschlag, bitte prüfen")
            }
            if let source {
                sourceButton(source)
            }
        }
    }

    private func sourceButton(_ source: SourceLocation) -> some View {
        Button {
            preview = source
        } label: {
            Image(systemName: "doc.text.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Im Beleg zeigen")
    }
}

extension SourceLocation: Identifiable {
    public var id: String { "\(page)-\(lineIndex)-\(excerpt)" }
}

/// Shows the highlighted value on the not-yet-saved receipt.
private struct DraftSourcePreview: View {
    let draft: ImportDraft
    let source: SourceLocation
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    HighlightedPageView(image: image, highlight: source.rect)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Im Beleg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Text("„\(source.excerpt)“").font(.caption).lineLimit(2)
                }
            }
            .task {
                guard let loc = draft.location(ofPage: source.page), loc.fileIndex < draft.files.count else { return }
                let file = draft.files[loc.fileIndex]
                let pages = DocumentStore.pageImages(for: file.data, isPDF: file.isPDF, maxPixel: 2200)
                if loc.localPage < pages.count { image = pages[loc.localPage] }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Step 4: Coverages

private struct CoverageStepView: View {
    @Bindable var draft: ImportDraft
    var onSave: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $draft.includeReturn) {
                    Label("Rückgabe/Umtausch des Händlers", systemImage: CoverageKind.returnPolicy.symbolName)
                }
                if draft.includeReturn {
                    Stepper(value: $draft.returnDays, in: 1...365) {
                        HStack {
                            Text("\(draft.returnDays) Tage")
                            if draft.suggestedFields.contains(.returnDays) { SuggestionBadge() }
                        }
                    }
                    endDate(days: draft.returnDays, from: draft.purchaseDate)
                }
            } footer: {
                Text("Freiwilliges Angebot des Händlers. Prüfe die Bedingungen auf dem Beleg oder der Website.")
            }

            if draft.channel == .online {
                Section {
                    if let days = draft.countryRules.onlineWithdrawalDays {
                        Toggle(isOn: $draft.includeWithdrawal) {
                            Label("Widerrufsrecht \(days) Tage", systemImage: CoverageKind.withdrawal.symbolName)
                        }
                        if draft.includeWithdrawal {
                            endDate(days: days, from: draft.hasDeliveryDate ? draft.deliveryDate : draft.purchaseDate)
                        }
                    } else {
                        Label("In \(draft.countryRules.name) gibt es kein allgemeines gesetzliches Widerrufsrecht für Online-Käufe.", systemImage: "info.circle")
                            .font(.subheadline)
                    }
                } footer: {
                    if draft.countryRules.onlineWithdrawalDays != nil {
                        Text("Die Frist beginnt in der Regel mit Erhalt der Ware.")
                    }
                }
            }

            Section {
                Toggle(isOn: $draft.includeStatutory) {
                    Label("Gesetzliche Gewährleistung", systemImage: CoverageKind.statutory.symbolName)
                }
                if draft.includeStatutory {
                    MonthsStepper(months: $draft.statutoryMonths)
                    endDate(months: draft.statutoryMonths, from: draft.hasDeliveryDate ? draft.deliveryDate : draft.purchaseDate)
                }
            } header: {
                Text("Mängelrechte – \(draft.countryRules.name)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.countryRules.notes, id: \.self) { Text("• \($0)") }
                }
            }

            Section {
                Toggle(isOn: $draft.includeManufacturer) {
                    Label("Herstellergarantie", systemImage: CoverageKind.manufacturer.symbolName)
                }
                if draft.includeManufacturer {
                    HStack {
                        MonthsStepper(months: $draft.manufacturerMonths)
                        if draft.suggestedFields.contains(.manufacturerMonths) { SuggestionBadge() }
                    }
                    endDate(months: draft.manufacturerMonths, from: draft.purchaseDate)
                }
                Toggle(isOn: $draft.includeExtended) {
                    Label("Zusatzgarantie/Versicherung", systemImage: CoverageKind.extended.symbolName)
                }
                if draft.includeExtended {
                    MonthsStepper(months: $draft.extendedMonths)
                    TextField("Anbieter", text: $draft.extendedProvider)
                    endDate(months: draft.extendedMonths, from: draft.purchaseDate)
                }
            } header: {
                Text("Freiwillige Garantien")
            } footer: {
                Text("Herstellergarantien gelten zusätzlich zur gesetzlichen Gewährleistung und ersetzen sie nicht. \(LegalRules.disclaimer)")
            }

            Section("Notiz") {
                TextField("Optional", text: $draft.notes, axis: .vertical)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: draft.selectedItems.count == 1 ? "Produkt speichern" : "\(draft.selectedItems.count) Produkte speichern", action: onSave)
        }
    }

    private func endDate(days: Int, from start: Date) -> some View {
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        return LabeledContent("Endet am", value: Formatters.longDate(end))
            .foregroundStyle(.secondary)
    }

    private func endDate(months: Int, from start: Date) -> some View {
        let end = Calendar.current.date(byAdding: .month, value: months, to: start) ?? start
        return LabeledContent("Endet am", value: Formatters.longDate(end))
            .foregroundStyle(.secondary)
    }
}

struct MonthsStepper: View {
    @Binding var months: Int

    var body: some View {
        Stepper(value: $months, in: 1...240) {
            Text(label)
        }
    }

    private var label: String {
        if months % 12 == 0 { return months == 12 ? "1 Jahr" : "\(months / 12) Jahre" }
        return "\(months) Monate"
    }
}
