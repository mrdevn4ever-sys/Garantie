import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import KaufarchivCore

struct ProductDetailView: View {
    @Bindable var product: Product

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderService.self) private var reminders

    @State private var showEdit = false
    @State private var editingCoverage: Coverage?
    @State private var addingCoverage = false
    @State private var viewing: StoredDocument?
    @State private var showSource = false
    @State private var showAddDocument = false
    @State private var showAddEvent = false
    @State private var showClaim = false
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        List {
            header

            if let purchase = product.purchase {
                Section("Kauf") {
                    InfoRow(label: "Händler", value: purchase.merchant)
                    InfoRow(label: "Kaufdatum", value: Formatters.longDate(purchase.purchaseDate))
                    if let delivery = purchase.deliveryDate {
                        InfoRow(label: "Lieferdatum", value: Formatters.longDate(delivery))
                    }
                    if let price = product.price {
                        InfoRow(label: product.quantity > 1 ? "Preis (\(product.quantity) Stück)" : "Preis",
                                value: Formatters.money(price, currency: purchase.currency))
                    }
                    InfoRow(label: "Beleg-/Bestellnummer", value: purchase.orderNumber, copyable: true)
                    InfoRow(label: "Land", value: Formatters.countryName(purchase.countryCode))
                    let siblings = purchase.productList.filter { $0.id != product.id }
                    if !siblings.isEmpty {
                        DisclosureGroup("Auf derselben Rechnung (\(siblings.count))") {
                            ForEach(siblings) { sibling in
                                NavigationLink(value: sibling) { Text(sibling.name) }
                            }
                        }
                    }
                    if product.source != nil, !purchase.receiptDocuments.isEmpty {
                        Button {
                            showSource = true
                        } label: {
                            Label("Position im Beleg zeigen", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }

            Section {
                if product.coverageList.isEmpty {
                    Text("Keine Fristen erfasst").foregroundStyle(.secondary)
                }
                ForEach(product.coverageList) { coverage in
                    Button {
                        editingCoverage = coverage
                    } label: {
                        CoverageRow(coverage: coverage)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Löschen", role: .destructive) {
                            context.delete(coverage)
                            saveAndReschedule()
                        }
                    }
                    .contextMenu {
                        Button("In Kalender eintragen", systemImage: "calendar.badge.plus") {
                            Task { await addToCalendar(coverage) }
                        }
                    }
                }
                Button {
                    addingCoverage = true
                } label: {
                    Label("Frist hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Fristen")
            } footer: {
                Text("Halte eine Frist gedrückt, um sie in den Kalender zu übertragen.")
            }

            Section("Dokumente") {
                let docs = product.allDocuments
                if docs.isEmpty {
                    Text("Keine Dokumente").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(docs) { doc in
                                Button {
                                    viewing = doc
                                } label: {
                                    VStack(spacing: 4) {
                                        DocumentThumbnail(document: doc, size: 70)
                                        Text(doc.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 76)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if doc.product?.id == product.id {
                                        Button("Löschen", systemImage: "trash", role: .destructive) {
                                            context.delete(doc)
                                            try? context.save()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Button {
                    showAddDocument = true
                } label: {
                    Label("Dokument oder Foto hinzufügen", systemImage: "paperclip")
                }
            }

            if !product.claimList.isEmpty {
                Section("Reklamationen") {
                    ForEach(product.claimList) { claim in
                        NavigationLink(value: claim) { ClaimRow(claim: claim) }
                    }
                }
            }

            Section("Verlauf") {
                ForEach(product.eventList) { event in
                    EventRow(event: event, currency: product.purchase?.currency ?? "CHF")
                        .swipeActions {
                            Button("Löschen", role: .destructive) {
                                context.delete(event)
                                try? context.save()
                            }
                        }
                }
                Button {
                    showAddEvent = true
                } label: {
                    Label("Eintrag hinzufügen", systemImage: "plus")
                }
            }

            if !product.notes.isEmpty {
                Section("Notizen") { Text(product.notes) }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Produkt löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { showEdit = true }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showClaim = true
                } label: {
                    Label("Defekt melden", systemImage: "exclamationmark.bubble")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(product.status.isClosed)
            }
        }
        .sheet(isPresented: $showEdit) { ProductEditView(product: product) }
        .sheet(item: $editingCoverage) { CoverageEditView(product: product, coverage: $0) }
        .sheet(isPresented: $addingCoverage) { CoverageEditView(product: product, coverage: nil) }
        .sheet(item: $viewing) { DocumentViewer(document: $0) }
        .sheet(isPresented: $showSource) {
            if let purchase = product.purchase, let source = product.source {
                PurchaseSourceViewer(purchase: purchase, source: source)
            }
        }
        .sheet(isPresented: $showAddDocument) { AddDocumentView(product: product) }
        .sheet(isPresented: $showAddEvent) { AddEventView(product: product) }
        .sheet(isPresented: $showClaim) { ClaimWizardView(product: product) }
        .confirmationDialog("„\(product.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Produkt löschen", role: .destructive) { deleteProduct() }
        } message: {
            Text("Fristen, Fotos und Reklamationen dieses Produkts werden gelöscht. Der Beleg bleibt erhalten, solange weitere Produkte darauf verweisen.")
        }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var header: some View {
        Section {
            HStack(spacing: 14) {
                ProductIcon(product: product, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.title3.bold())
                    if !product.subtitle.isEmpty {
                        Text(product.subtitle).foregroundStyle(.secondary)
                    }
                    Label(product.status.title, systemImage: product.status.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            InfoRow(label: "Seriennummer", value: product.serialNumber, copyable: true)
            InfoRow(label: "Artikelnummer", value: product.articleNumber, copyable: true)
            InfoRow(label: "Kategorie", value: product.category)
            InfoRow(label: "Raum", value: product.room)
        }
    }

    private func saveAndReschedule() {
        product.updatedAt = Date()
        try? context.save()
        Task { await reminders.reschedule(context: context) }
    }

    private func addToCalendar(_ coverage: Coverage) async {
        do {
            try await CalendarService.addEvent(for: coverage, productName: product.name)
            message = "Die Frist wurde in deinen Kalender eingetragen."
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteProduct() {
        let purchase = product.purchase
        context.delete(product)
        // Remove the purchase (and its receipt) only when no other product uses it.
        if let purchase, (purchase.products ?? []).allSatisfy({ $0.id == product.id }) {
            context.delete(purchase)
        }
        try? context.save()
        Task { await reminders.reschedule(context: context) }
        dismiss()
    }
}

struct EventRow: View {
    let event: ProductEvent
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                if !event.details.isEmpty {
                    Text(event.details).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(Formatters.date(event.date))
                    if let cost = event.cost {
                        Text("· \(Formatters.money(cost, currency: currency))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Edit product

struct ProductEditView: View {
    @Bindable var product: Product
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ReminderService.self) private var reminders
    @Query private var allProducts: [Product]

    private var knownRooms: [String] {
        Array(Set(allProducts.map(\.room).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produkt") {
                    TextField("Name", text: $product.name)
                    TextField("Marke", text: $product.brand)
                    TextField("Modell", text: $product.modelName)
                    TextField("Seriennummer", text: $product.serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Artikelnummer", text: $product.articleNumber)
                        .autocorrectionDisabled()
                    Picker("Kategorie", selection: $product.category) {
                        Text("Keine").tag("")
                        ForEach(CategoryCatalog.all, id: \.name) { Label($0.name, systemImage: $0.symbol).tag($0.name) }
                    }
                }
                Section {
                    TextField("Raum, z. B. Küche", text: $product.room)
                    if !knownRooms.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownRooms, id: \.self) { room in
                                    Button(room) { product.room = room }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Standort")
                }
                Section("Preis") {
                    HStack {
                        Text("Preis")
                        DecimalField(title: "0.00", value: $product.price)
                        Text(product.purchase?.currency ?? "CHF").foregroundStyle(.secondary)
                    }
                    Stepper("Anzahl: \(product.quantity)", value: $product.quantity, in: 1...999)
                }
                Section("Status") {
                    Picker("Status", selection: Binding(get: { product.status }, set: { product.status = $0 })) {
                        ForEach(ProductStatus.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                }
                if let purchase = product.purchase {
                    PurchaseEditSection(purchase: purchase)
                }
                Section("Notizen") {
                    TextField("Notizen", text: $product.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle("Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        product.updatedAt = Date()
                        try? context.save()
                        Task { await reminders.reschedule(context: context) }
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PurchaseEditSection: View {
    @Bindable var purchase: Purchase

    var body: some View {
        Section {
            TextField("Händler", text: $purchase.merchant)
            DatePicker("Kaufdatum", selection: $purchase.purchaseDate, displayedComponents: .date)
            Picker("Kaufart", selection: Binding(get: { purchase.channel }, set: { purchase.channel = $0 })) {
                Text("Im Geschäft").tag(SalesChannel.store)
                Text("Online/Versand").tag(SalesChannel.online)
                Text("Unbekannt").tag(SalesChannel.unknown)
            }
            CountryPicker(code: $purchase.countryCode)
            TextField("Beleg-/Bestellnummer", text: $purchase.orderNumber)
            HStack {
                Text("Belegtotal")
                DecimalField(title: "0.00", value: $purchase.totalAmount)
                Picker("Währung", selection: $purchase.currency) {
                    ForEach(["CHF", "EUR", "USD", "GBP"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        } header: {
            Text("Kauf")
        } footer: {
            Text("Änderungen am Kauf gelten für alle Produkte derselben Rechnung. Fristen passt du einzeln an.")
        }
    }
}

// MARK: - Coverage editor

struct CoverageEditView: View {
    let product: Product
    let coverage: Coverage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ReminderService.self) private var reminders

    @State private var kind: CoverageKind = .manufacturer
    @State private var start = Date()
    @State private var mode: Mode = .months
    @State private var months = 24
    @State private var days = 30
    @State private var end = Date()
    @State private var provider = ""
    @State private var notes = ""
    @State private var remindersEnabled = true
    @State private var offsets: Set<Int> = [30, 7]

    enum Mode: String, CaseIterable, Identifiable {
        case months, days, date
        var id: String { rawValue }
        var title: String {
            switch self {
            case .months: "Monate"
            case .days: "Tage"
            case .date: "Datum"
            }
        }
    }

    static let offsetChoices = [90, 60, 30, 14, 7, 3, 1, 0]

    private var computedEnd: Date {
        switch mode {
        case .months: Calendar.current.date(byAdding: .month, value: months, to: start) ?? start
        case .days: Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        case .date: end
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(CoverageKind.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    DatePicker("Beginn", selection: $start, displayedComponents: .date)
                    Picker("Dauer in", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch mode {
                    case .months: MonthsStepper(months: $months)
                    case .days: Stepper("\(days) Tage", value: $days, in: 1...3650)
                    case .date: DatePicker("Ende", selection: $end, in: start..., displayedComponents: .date)
                    }
                    LabeledContent("Endet am", value: Formatters.longDate(computedEnd))
                } footer: {
                    if kind == .statutory, let country = product.purchase?.countryCode {
                        Text(LegalRules.rules(for: country).notes.first ?? "")
                    }
                }
                if kind == .extended || kind == .manufacturer {
                    Section("Anbieter") {
                        TextField(kind == .manufacturer ? "Hersteller" : "Versicherung/Anbieter", text: $provider)
                    }
                }
                Section {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    if remindersEnabled {
                        ForEach(Self.offsetChoices, id: \.self) { offset in
                            Button {
                                if offsets.contains(offset) { offsets.remove(offset) } else { offsets.insert(offset) }
                            } label: {
                                HStack {
                                    Text(offset == 0 ? "Am Tag des Ablaufs" : (offset == 1 ? "1 Tag vorher" : "\(offset) Tage vorher"))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if offsets.contains(offset) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Erinnerungen")
                }
                Section("Notizen") {
                    TextField("z. B. Bedingungen, Kontakt, Fall-Nummer", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(coverage == nil ? "Neue Frist" : kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                if coverage == nil { offsets = Set(newKind.defaultReminderOffsets) }
            }
        }
    }

    private func load() {
        guard let coverage else {
            start = product.purchaseDate
            return
        }
        kind = coverage.kind
        start = coverage.startDate
        if let m = coverage.months {
            mode = .months
            months = m
        } else if let d = coverage.days {
            mode = .days
            days = d
        } else {
            mode = .date
        }
        end = coverage.endDate ?? Date()
        provider = coverage.provider
        notes = coverage.notes
        remindersEnabled = coverage.remindersEnabled
        offsets = Set(coverage.reminderOffsets)
    }

    private func save() {
        let target: Coverage
        if let coverage {
            target = coverage
        } else {
            target = Coverage(kind: kind, start: start)
            context.insert(target)
            target.product = product
        }
        target.kind = kind
        target.startDate = start
        target.months = mode == .months ? months : nil
        target.days = mode == .days ? days : nil
        target.endDate = computedEnd
        target.provider = provider
        target.notes = notes
        target.remindersEnabled = remindersEnabled
        target.reminderOffsets = offsets.sorted(by: >)
        target.confirmed = true
        product.updatedAt = Date()
        try? context.save()
        Task { await reminders.reschedule(context: context) }
        dismiss()
    }
}

// MARK: - Add document

struct AddDocumentView: View {
    let product: Product
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var kind: DocumentKind = .photo
    @State private var title = ""
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(DocumentKind.allCases.filter { $0 != .claimDossier }) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    TextField("Titel (optional)", text: $title)
                }
                Section {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                    }
                    if DocumentScannerView.isAvailable {
                        Button { showScanner = true } label: { Label("Dokument scannen", systemImage: "doc.viewfinder") }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                    }
                    Button { showFiles = true } label: { Label("Aus Dateien wählen", systemImage: "folder") }
                }
                if working {
                    Section { ProgressView("Wird gespeichert …") }
                }
            }
            .navigationTitle("Dokument hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { images in
                    showScanner = false
                    Task { await store(images.compactMap { IncomingFile.image($0, name: "Scan") }) }
                } onCancel: { showScanner = false }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await store([IncomingFile.image(image, name: "Foto")].compactMap { $0 }) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result {
                    Task { await store(urls.compactMap { try? IncomingFile.file(at: $0) }) }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var files: [IncomingFile] = []
                    for (i, item) in items.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let type = item.supportedContentTypes.first ?? .jpeg
                            files.append(IncomingFile(data: data, filename: "Foto-\(i + 1).\(type.preferredFilenameExtension ?? "jpg")", type: type))
                        }
                    }
                    photoItems = []
                    await store(files)
                }
            }
            .alert("Fehler", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func store(_ files: [IncomingFile]) async {
        guard !files.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            for (index, file) in files.enumerated() {
                // Text recognition makes manuals and warranty terms searchable.
                let lines = kind == .photo ? [] : await TextRecognizer.recognize(data: file.data, isPDF: file.isPDF)
                let baseTitle = title.isEmpty ? kind.title : title
                let doc = try DocumentStore.makeDocument(from: file, kind: kind,
                                                         title: files.count > 1 ? "\(baseTitle) \(index + 1)" : baseTitle,
                                                         lines: lines, in: context)
                doc.product = product
            }
            try context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Add history event

struct AddEventView: View {
    let product: Product
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var kind: EventKind = .repair
    @State private var title = ""
    @State private var details = ""
    @State private var date = Date()
    @State private var cost: Decimal?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Art", selection: $kind) {
                    ForEach(EventKind.allCases.filter { $0 != .purchase }) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                TextField("Titel", text: $title)
                DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                HStack {
                    Text("Kosten")
                    DecimalField(title: "optional", value: $cost)
                }
                TextField("Details", text: $details, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let event = ProductEvent(kind: kind, title: title.isEmpty ? kind.title : title, details: details, date: date)
                        event.cost = cost
                        context.insert(event)
                        event.product = product
                        if kind == .returned { product.status = .returned }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
