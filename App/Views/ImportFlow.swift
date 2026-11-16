import SwiftUI
import SwiftData
import VisionKit
import Observation
import KaufarchivCore

// MARK: Zustand des Erfassungsablaufs

struct EditableItem: Identifiable {
    let id = UUID()
    var selected = true
    var name = ""
    var priceText = ""
    var quantity = 1
    var serial = ""
    var category = ""
    var lineIndex: Int?
    var confidence: Confidence = .high
}

@MainActor
@Observable
final class ImportSession {
    var file: ImportedFile?
    var pageImages: [UIImage] = []
    var lines: [TextLine] = []
    var draft: ReceiptDraft?
    var isProcessing = false
    var errorMessage: String?

    // Schritt 3: Angaben zum Kauf
    var merchant = ""
    var purchaseDate = Date()
    var totalText = ""
    var currency = Prefs.defaults.string(forKey: Prefs.currency) ?? "CHF"
    var channel: PurchaseChannel = .store
    var countryCode = Prefs.defaults.string(forKey: Prefs.countryCode) ?? "CH"
    var orderNumber = ""

    // Schritt 2: Produkte
    var items: [EditableItem] = []

    // Schritt 4: Fristen
    var returnEnabled = false
    var returnDays = 14
    var returnBasis = ""
    var legalEnabled = true
    var legalMonths = 24
    var legalBasis = ""
    var manufacturerEnabled = false
    var manufacturerMonths = 24
    var manufacturerProvider = ""
    var extendedEnabled = false
    var extendedMonths = 36
    var extendedProvider = ""
    var reviewLater = false

    var selectedItems: [EditableItem] {
        items.filter { $0.selected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var hasDocument: Bool { file != nil }

    init() {
        applyRuleSuggestions()
    }

    // MARK: Verarbeitung

    func process(_ file: ImportedFile) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let images = DocumentRenderer.allPageImages(data: file.data, typeIdentifier: file.typeIdentifier)
        guard !images.isEmpty else {
            errorMessage = "Die Datei konnte nicht gelesen werden. Unterstützt werden PDF-Dateien und Bilder."
            return
        }
        self.file = file
        pageImages = images
        do {
            lines = try await OCRService.recognize(images: images)
        } catch {
            lines = []
            errorMessage = "Die Texterkennung ist fehlgeschlagen. Du kannst die Angaben von Hand eintragen."
        }
        let parsed = ReceiptParser.parse(lines: lines, now: Date(), calendar: .current, defaultCurrency: currency)
        apply(parsed)
    }

    func startManual() {
        file = nil
        pageImages = []
        lines = []
        draft = nil
        if items.isEmpty { items = [EditableItem()] }
    }

    private func apply(_ parsed: ReceiptDraft) {
        draft = parsed
        merchant = parsed.merchant?.value ?? ""
        purchaseDate = parsed.purchaseDate?.value ?? Date()
        totalText = parsed.total.map { Money.plainText(cents: Money.cents(from: $0.value)) } ?? ""
        currency = parsed.currency
        channel = parsed.isOnlineOrder ? .online : .store
        orderNumber = parsed.orderNumber?.value ?? ""
        items = parsed.items.map { item in
            EditableItem(
                selected: true,
                name: item.name,
                priceText: item.unitPrice.map { Money.plainText(cents: Money.cents(from: $0)) } ?? "",
                quantity: max(item.quantity, 1),
                lineIndex: item.lineIndex,
                confidence: item.confidence
            )
        }
        if items.count == 1, parsed.serialNumbers.count == 1 {
            items[0].serial = parsed.serialNumbers[0].value
        }
        if items.isEmpty { items = [EditableItem()] }
        applyRuleSuggestions()
    }

    /// Setzt die Fristen auf die Ausgangswerte für Land und Kaufart zurück.
    func applyRuleSuggestions() {
        let rule = DeadlineRules.rule(for: countryCode)
        legalMonths = rule.legalMonths
        legalBasis = rule.legalNote
        if channel == .online, let days = rule.withdrawalDays {
            returnEnabled = true
            returnDays = days
            returnBasis = rule.withdrawalNote
        } else {
            returnEnabled = false
            returnBasis = channel == .online
                ? rule.withdrawalNote
                : "Eine Rückgabe im Geschäft ist freiwillig. Schalte sie ein, wenn der Händler eine Frist anbietet."
        }
    }

    // MARK: Fundstellen

    func evidence(title: String, value: String, lineIndex: Int?) -> EvidenceItem? {
        guard let lineIndex, lines.indices.contains(lineIndex) else {
            guard let first = pageImages.first else { return nil }
            return EvidenceItem(title: title, value: value, image: first, box: nil)
        }
        let line = lines[lineIndex]
        guard pageImages.indices.contains(line.page) else { return nil }
        return EvidenceItem(title: title, value: value, image: pageImages[line.page], box: line.box)
    }

    // MARK: Speichern

    func makeCoverages() -> [Coverage] {
        var result: [Coverage] = []
        let confirmed = !reviewLater
        if returnEnabled {
            result.append(Coverage(
                kind: .returnWindow, startDate: purchaseDate,
                endDate: DeadlineRules.endDate(from: purchaseDate, days: returnDays, calendar: .current),
                basis: returnBasis, isConfirmed: confirmed
            ))
        }
        if legalEnabled {
            result.append(Coverage(
                kind: .legal, startDate: purchaseDate,
                endDate: DeadlineRules.endDate(from: purchaseDate, months: legalMonths, calendar: .current),
                basis: legalBasis, isConfirmed: confirmed
            ))
        }
        if manufacturerEnabled {
            let coverage = Coverage(
                kind: .manufacturer, startDate: purchaseDate,
                endDate: DeadlineRules.endDate(from: purchaseDate, months: manufacturerMonths, calendar: .current),
                basis: "Freiwillige Garantie des Herstellers – massgebend sind dessen Garantiebedingungen.",
                isConfirmed: confirmed
            )
            coverage.provider = manufacturerProvider
            result.append(coverage)
        }
        if extendedEnabled {
            let coverage = Coverage(
                kind: .extended, startDate: purchaseDate,
                endDate: DeadlineRules.endDate(from: purchaseDate, months: extendedMonths, calendar: .current),
                basis: "Zusätzlich abgeschlossene Garantie – massgebend ist der Vertrag.",
                isConfirmed: confirmed
            )
            coverage.provider = extendedProvider
            result.append(coverage)
        }
        return result
    }

    func save(context: ModelContext) async throws {
        let receipt = Receipt(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), purchaseDate: purchaseDate)
        receipt.totalCents = Money.cents(fromText: totalText)
        receipt.currency = currency
        receipt.channel = channel
        receipt.countryCode = countryCode
        receipt.orderNumber = orderNumber.trimmingCharacters(in: .whitespaces)
        receipt.merchantLine = draft?.merchant?.lineIndex ?? -1
        receipt.dateLine = draft?.purchaseDate?.lineIndex ?? -1
        receipt.totalLine = draft?.total?.lineIndex ?? -1
        context.insert(receipt)

        if let file {
            let document = await DocumentFactory.make(
                file: file, kind: .receipt, title: "Rechnung", lines: lines, firstPage: pageImages.first
            )
            context.insert(document)
            document.receipt = receipt
        }

        for item in selectedItems {
            let product = OwnedProduct(name: item.name.trimmingCharacters(in: .whitespaces))
            product.priceCents = Money.cents(fromText: item.priceText)
            product.quantity = max(item.quantity, 1)
            product.serialNumber = item.serial.trimmingCharacters(in: .whitespaces)
            product.category = item.category
            product.sourceLine = item.lineIndex ?? -1
            context.insert(product)
            product.receipt = receipt
            for coverage in makeCoverages() {
                context.insert(coverage)
                coverage.product = product
            }
        }
        try context.save()
    }
}

// MARK: Ablauf

enum ImportStep: Hashable {
    case items, details, coverage
}

struct ImportFlowView: View {
    let request: ImportRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PurchaseManager.self) private var purchases
    @Environment(ReminderCenter.self) private var reminders
    @Query private var existingProducts: [OwnedProduct]

    @State private var session = ImportSession()
    @State private var path: [ImportStep] = []
    @State private var evidence: EvidenceItem?
    @State private var showPaywall = false
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack(path: $path) {
            ImportSourceStep(
                session: session,
                onFile: { file in
                    Task {
                        await session.process(file)
                        if session.hasDocument { path = [.items] }
                    }
                },
                onManual: {
                    session.startManual()
                    path = [.details]
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .navigationDestination(for: ImportStep.self) { step in
                Group {
                    switch step {
                    case .items:
                        ImportItemsStep(session: session, evidence: $evidence) { path.append(.details) }
                    case .details:
                        ImportDetailsStep(session: session, evidence: $evidence) { path.append(.coverage) }
                    case .coverage:
                        ImportCoverageStep(session: session, isSaving: isSaving) { save() }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: $evidence) { item in
            EvidenceView(item: item)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Die kostenlose Version verwaltet \(Prefs.freeProductLimit) Produkte. Mit Pro erfasst du unbegrenzt viele.")
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task {
            if let file = request.file, !session.hasDocument {
                await session.process(file)
                if session.hasDocument { path = [.items] }
            }
        }
    }

    private func save() {
        let newCount = session.selectedItems.count
        guard newCount > 0 else {
            saveError = "Bitte wähle mindestens ein Produkt mit Bezeichnung aus."
            return
        }
        // Kaufseite erst, wenn das Gratis-Kontingent tatsächlich überschritten würde.
        if !purchases.isPro, existingProducts.count + newCount > Prefs.freeProductLimit {
            showPaywall = true
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.save(context: context)
                if reminders.authorization == .notDetermined {
                    await reminders.requestAuthorization()
                }
                await reminders.refresh(context: context)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

private struct StepHeader: View {
    let step: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Schritt \(step) von 5")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step), total: 5)
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
        .listRowBackground(Color.clear)
    }
}

// MARK: Schritt 1 – Quelle

struct ImportSourceStep: View {
    let session: ImportSession
    var onFile: (ImportedFile) -> Void
    var onManual: () -> Void

    @State private var showScanner = false
    @State private var showPhotos = false
    @State private var showFiles = false

    var body: some View {
        List {
            Section {
                StepHeader(step: 1, title: "Beleg hinzufügen",
                           subtitle: "Die Erkennung läuft vollständig auf deinem Gerät. Das Original bleibt unverändert erhalten.")
            }
            Section {
                if VNDocumentCameraViewController.isSupported {
                    sourceButton("Beleg scannen", "Kamera mit automatischer Kantenerkennung", "doc.viewfinder") { showScanner = true }
                }
                sourceButton("Foto auswählen", "Aus deiner Fotomediathek", "photo.on.rectangle") { showPhotos = true }
                sourceButton("Datei auswählen", "PDF oder Bild aus Dateien, iCloud Drive, Mail", "folder") { showFiles = true }
            }
            Section {
                sourceButton("Ohne Beleg erfassen", "Angaben von Hand eintragen, Beleg später ergänzen", "square.and.pencil", action: onManual)
            } footer: {
                Text("Tipp: In Mail, Safari oder Dateien kannst du eine Rechnung über «Teilen» direkt an Kaufarchiv übergeben.")
            }
            if let message = session.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Neuer Kauf")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(session.isProcessing)
        .overlay {
            if session.isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Beleg wird gelesen …").font(.subheadline)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .modifier(DocumentPickers(showScanner: $showScanner, showPhotos: $showPhotos, showFiles: $showFiles, onImport: onFile))
    }

    private func sourceButton(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: Schritt 2 – Produkte auswählen

struct ImportItemsStep: View {
    @Bindable var session: ImportSession
    @Binding var evidence: EvidenceItem?
    var onNext: () -> Void

    var body: some View {
        List {
            Section {
                StepHeader(step: 2, title: "Produkte auswählen",
                           subtitle: "Jedes ausgewählte Produkt bekommt eine eigene Akte mit eigenen Fristen und bleibt mit dieser Rechnung verbunden.")
            }
            Section {
                ForEach($session.items) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Toggle(isOn: $item.selected) {
                                TextField("Bezeichnung", text: $item.name, axis: .vertical)
                                    .font(.body.weight(.medium))
                            }
                        }
                        HStack(spacing: 10) {
                            TextField("Preis", text: $item.priceText)
                                .keyboardType(.decimalPad)
                                .frame(width: 90)
                                .textFieldStyle(.roundedBorder)
                            Text(session.currency).foregroundStyle(.secondary)
                            Stepper("Menge \(item.quantity)", value: $item.quantity, in: 1...99)
                                .font(.footnote)
                        }
                        HStack(spacing: 8) {
                            if item.confidence != .high { SuggestionBadge(text: "Bitte prüfen") }
                            if session.hasDocument {
                                Button {
                                    evidence = session.evidence(title: "Position", value: item.name, lineIndex: item.lineIndex)
                                } label: {
                                    Label("Im Beleg zeigen", systemImage: "text.viewfinder")
                                        .font(.footnote)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .opacity(item.selected ? 1 : 0.5)
                }
                .onDelete { session.items.remove(atOffsets: $0) }

                Button("Position hinzufügen", systemImage: "plus") {
                    session.items.append(EditableItem())
                }
            } header: {
                Text("Erkannte Positionen")
            } footer: {
                if session.hasDocument && session.draft?.items.isEmpty == true {
                    Text("Auf dem Beleg wurden keine einzelnen Positionen erkannt. Trage das Produkt bitte selbst ein.")
                } else {
                    Text("Kleinteile wie Tragtaschen oder Versandkosten kannst du einfach abwählen.")
                }
            }
        }
        .navigationTitle("Produkte")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Weiter", disabled: session.selectedItems.isEmpty, action: onNext)
        }
    }
}

struct NextButton: View {
    let title: String
    var disabled = false
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isBusy { ProgressView().tint(.white) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled || isBusy)
        .padding()
        .background(.bar)
    }
}

// MARK: Schritt 3 – Angaben prüfen

struct ImportDetailsStep: View {
    @Bindable var session: ImportSession
    @Binding var evidence: EvidenceItem?
    var onNext: () -> Void

    var body: some View {
        Form {
            Section {
                StepHeader(step: 3, title: "Angaben prüfen",
                           subtitle: "Tippe auf das Sucher-Symbol, um die Stelle im Beleg zu sehen, an der ein Wert erkannt wurde.")
            }
            Section("Kauf") {
                fieldRow(title: "Händler", detected: session.draft?.merchant.map { ($0.confidence, $0.lineIndex) }, value: session.merchant) {
                    TextField("Händler", text: $session.merchant)
                        .textInputAutocapitalization(.words)
                }
                fieldRow(title: "Kaufdatum", detected: session.draft?.purchaseDate.map { ($0.confidence, $0.lineIndex) },
                         value: Fmt.date(session.purchaseDate), missingHint: session.hasDocument ? "Nicht erkannt – bitte prüfen" : nil) {
                    DatePicker("Kaufdatum", selection: $session.purchaseDate, in: ...Date(), displayedComponents: .date)
                }
                fieldRow(title: "Gesamtbetrag", detected: session.draft?.total.map { ($0.confidence, $0.lineIndex) }, value: session.totalText) {
                    HStack {
                        Text("Gesamtbetrag")
                        Spacer()
                        TextField("0.00", text: $session.totalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Picker("Währung", selection: $session.currency) {
                            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                if let given = session.draft?.cashGiven {
                    Label {
                        Text("Bar gegeben \(Money.format(cents: Money.cents(from: given), currency: session.currency))\(changeText) – nicht als Kaufpreis übernommen.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                TextField("Bestell- oder Rechnungsnummer", text: $session.orderNumber)
                    .autocorrectionDisabled()
            }
            Section {
                Picker("Kaufart", selection: $session.channel) {
                    ForEach(PurchaseChannel.allCases) { Text($0.label).tag($0) }
                }
                CountryPicker(selection: $session.countryCode)
            } header: {
                Text("Wo gekauft?")
            } footer: {
                Text("Kaufart und Land bestimmen, welche Fristen im nächsten Schritt vorgeschlagen werden.")
            }
        }
        .navigationTitle("Angaben")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.channel) { _, _ in session.applyRuleSuggestions() }
        .onChange(of: session.countryCode) { _, _ in session.applyRuleSuggestions() }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Weiter", action: onNext)
        }
    }

    private var currencyOptions: [String] {
        Catalog.currencies.contains(session.currency) ? Catalog.currencies : Catalog.currencies + [session.currency]
    }

    private var changeText: String {
        guard let change = session.draft?.change else { return "" }
        return ", Rückgeld \(Money.format(cents: Money.cents(from: change), currency: session.currency))"
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        title: String,
        detected: (Confidence, Int?)?,
        value: String,
        missingHint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            HStack(spacing: 8) {
                if let detected {
                    if detected.0 != .high { SuggestionBadge() }
                    Button {
                        evidence = session.evidence(title: title, value: value, lineIndex: detected.1)
                    } label: {
                        Label("Im Beleg zeigen", systemImage: "text.viewfinder").font(.footnote)
                    }
                    .buttonStyle(.borderless)
                } else if let missingHint {
                    SuggestionBadge(text: missingHint)
                }
            }
        }
    }
}

// MARK: Schritt 4 und 5 – Fristen bestätigen und speichern

struct ImportCoverageStep: View {
    @Bindable var session: ImportSession
    let isSaving: Bool
    var onSave: () -> Void

    var body: some View {
        Form {
            Section {
                StepHeader(step: 4, title: "Fristen bestätigen",
                           subtitle: "Die Werte sind Vorschläge für \(DeadlineRules.rule(for: session.countryCode).name). Massgebend sind Vertrag und AGB des Händlers.")
            }

            Section {
                Toggle("Rückgabe möglich", isOn: $session.returnEnabled)
                if session.returnEnabled {
                    Stepper("\(session.returnDays) Tage", value: $session.returnDays, in: 1...365)
                    endRow(DeadlineRules.endDate(from: session.purchaseDate, days: session.returnDays, calendar: .current))
                }
            } header: {
                Text(CoverageKind.returnWindow.label)
            } footer: {
                Text(session.returnBasis)
            }

            Section {
                Toggle("Gesetzliche Mängelrechte", isOn: $session.legalEnabled)
                if session.legalEnabled {
                    Stepper("\(session.legalMonths) Monate", value: $session.legalMonths, in: 1...120)
                    endRow(DeadlineRules.endDate(from: session.purchaseDate, months: session.legalMonths, calendar: .current))
                }
            } header: {
                Text(CoverageKind.legal.label)
            } footer: {
                Text(session.legalBasis)
            }

            Section {
                Toggle("Herstellergarantie", isOn: $session.manufacturerEnabled)
                if session.manufacturerEnabled {
                    Stepper("\(session.manufacturerMonths) Monate", value: $session.manufacturerMonths, in: 1...240)
                    TextField("Hersteller (optional)", text: $session.manufacturerProvider)
                    endRow(DeadlineRules.endDate(from: session.purchaseDate, months: session.manufacturerMonths, calendar: .current))
                }
            } header: {
                Text(CoverageKind.manufacturer.label)
            } footer: {
                Text("Freiwillige Leistung des Herstellers. Dauer und Umfang stehen in den Garantiebedingungen.")
            }

            Section {
                Toggle("Zusatzgarantie abgeschlossen", isOn: $session.extendedEnabled)
                if session.extendedEnabled {
                    Stepper("\(session.extendedMonths) Monate", value: $session.extendedMonths, in: 1...240)
                    TextField("Anbieter (optional)", text: $session.extendedProvider)
                    endRow(DeadlineRules.endDate(from: session.purchaseDate, months: session.extendedMonths, calendar: .current))
                }
            } header: {
                Text(CoverageKind.extended.label)
            }

            Section {
                Toggle("Fristen später prüfen", isOn: $session.reviewLater)
            } footer: {
                Text("Die Fristen werden dann als unbestätigte Vorschläge gespeichert und in der App entsprechend markiert.")
            }

            Section("Schritt 5 von 5 · Zusammenfassung") {
                LabeledContent("Händler", value: session.merchant.isEmpty ? "–" : session.merchant)
                LabeledContent("Kaufdatum", value: Fmt.date(session.purchaseDate))
                LabeledContent("Produkte", value: "\(session.selectedItems.count)")
                ForEach(session.selectedItems) { item in
                    Text("· \(item.name)").font(.footnote).foregroundStyle(.secondary)
                }
                if session.selectedItems.count > 1 {
                    Text("Die Fristen gelten für alle ausgewählten Produkte und lassen sich danach je Produkt anpassen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Fristen")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Speichern", disabled: session.selectedItems.isEmpty, isBusy: isSaving, action: onSave)
        }
    }

    private func endRow(_ date: Date) -> some View {
        LabeledContent("Endet am", value: Fmt.date(date))
            .foregroundStyle(.secondary)
    }
}
