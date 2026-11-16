import SwiftUI
import SwiftData
import QuickLook
import KaufarchivCore

// MARK: Produktakte

struct ProductDetailView: View {
    @Bindable var product: OwnedProduct

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderCenter.self) private var reminders

    @State private var showEdit = false
    @State private var coverageToEdit: Coverage?
    @State private var showNewCoverage = false
    @State private var previewURL: URL?
    @State private var evidence: EvidenceItem?
    @State private var calendarRequest: CalendarRequest?
    @State private var showDeleteConfirm = false
    @State private var showClaimEditor = false
    @State private var showReturnEditor = false
    @State private var repairToEdit: Repair?
    @State private var showNewRepair = false
    @State private var isAddingDocument = false

    /// Nach dem Löschen (auch über die Rechnung) darf auf das Produkt nicht mehr zugegriffen werden.
    private var isGone: Bool { product.isDeleted || product.modelContext == nil }

    var body: some View {
        Group {
            if isGone {
                ContentUnavailableView("Produkt gelöscht", systemImage: "trash")
            } else {
                content
            }
        }
        .onAppear {
            if isGone { dismiss() }
        }
    }

    private var content: some View {
        List {
            headerSection
            returnSection
            purchaseSection
            coverageSection
            documentSection
            detailSection
            claimSection
            repairSection
            Section {
                Button("Produkt löschen", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .navigationTitle(product.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: commit) {
            ProductEditView(product: product)
        }
        .sheet(item: $coverageToEdit, onDismiss: commit) { coverage in
            CoverageEditView(product: product, coverage: coverage)
        }
        .sheet(isPresented: $showNewCoverage, onDismiss: commit) {
            CoverageEditView(product: product, coverage: nil)
        }
        .sheet(item: $repairToEdit, onDismiss: commit) { repair in
            RepairEditView(product: product, repair: repair)
        }
        .sheet(isPresented: $showNewRepair, onDismiss: commit) {
            RepairEditView(product: product, repair: nil)
        }
        .sheet(isPresented: $showClaimEditor, onDismiss: commit) {
            ClaimEditorView(product: product, kind: .defect)
        }
        .sheet(isPresented: $showReturnEditor, onDismiss: commit) {
            ClaimEditorView(product: product, kind: .productReturn)
        }
        .sheet(item: $evidence) { item in
            EvidenceView(item: item)
        }
        .sheet(item: $calendarRequest) { request in
            CalendarEventEditor(title: request.title, date: request.date, notes: request.notes) {
                calendarRequest = nil
            }
            .ignoresSafeArea()
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Produkt wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteProduct() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: Abschnitte

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(product.displayName).font(.title3.weight(.semibold))
                let brandModel = [product.brand, product.modelName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !brandModel.isEmpty {
                    Text(brandModel).foregroundStyle(.secondary)
                }
                if let price = product.priceCents {
                    Text(Money.format(cents: price, currency: product.currency) + (product.quantity > 1 ? "  × \(product.quantity)" : ""))
                        .font(.headline)
                }
            }
            Picker("Status", selection: $product.statusRaw) {
                ForEach(ProductStatus.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: product.statusRaw) { _, _ in commit() }
        }
    }

    @ViewBuilder
    private var returnSection: some View {
        if product.status == .active, let window = product.openReturnWindow() {
            Section {
                Text(window.isConfirmed
                     ? "Rückgabe möglich bis \(Fmt.date(window.endDate)) (\(Fmt.remaining(days: window.daysRemaining())))."
                     : "Rückgabe voraussichtlich bis \(Fmt.date(window.endDate)) möglich – Frist noch nicht bestätigt.")
                    .font(.subheadline)
                Button("Behalten", systemImage: "hand.thumbsup") {
                    window.isDecided = true
                    commit()
                }
                Button("Rückgabe vorbereiten", systemImage: "arrow.uturn.backward") { showReturnEditor = true }
            } header: {
                Text("Behalten oder zurückgeben?")
            } footer: {
                Text("«Behalten» beendet die Erinnerungen an diese Rückgabefrist. Die Frist selbst bleibt in der Akte sichtbar.")
            }
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if let receipt = product.receipt {
            Section("Kauf") {
                NavigationLink {
                    ReceiptDetailView(receipt: receipt)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.displayMerchant)
                        Text("\(Fmt.date(receipt.purchaseDate)) · \(receipt.channel.label)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let delivery = receipt.deliveryDate {
                            Text("Erhalten am \(Fmt.date(delivery))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if receipt.productList.count > 1 {
                            Text("Rechnung mit \(receipt.productList.count) Produkten")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if product.sourceLine >= 0, let document = receipt.documentList.first {
                    Button("Position im Beleg zeigen", systemImage: "text.viewfinder") {
                        evidence = document.evidence(title: "Position", value: product.displayName, lineIndex: product.sourceLine)
                    }
                }
            }
        }
    }

    private var coverageSection: some View {
        Section {
            if product.coverageList.isEmpty {
                Text("Keine Fristen erfasst.").foregroundStyle(.secondary)
            }
            ForEach(product.coverageList) { coverage in
                Button {
                    coverageToEdit = coverage
                } label: {
                    CoverageRow(coverage: coverage, reminderStatus: reminders.status(for: coverage))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Löschen", role: .destructive) {
                        context.delete(coverage)
                        commit()
                    }
                    Button("Kalender", systemImage: "calendar.badge.plus") {
                        calendarRequest = CalendarRequest(coverage: coverage)
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    if !coverage.isConfirmed {
                        Button("Bestätigen", systemImage: "checkmark") {
                            coverage.isConfirmed = true
                            commit()
                        }
                        .tint(.green)
                    }
                }
            }
            Button("Frist hinzufügen", systemImage: "plus") { showNewCoverage = true }
        } header: {
            Text("Fristen")
        } footer: {
            Text("Antippen zum Bearbeiten. Wischen, um eine Frist in den Kalender zu übernehmen oder einen Vorschlag zu bestätigen.")
        }
    }

    private var documentSection: some View {
        Section {
            if product.allDocuments.isEmpty {
                Text("Noch keine Unterlagen. Ergänze Rechnung, Garantiebedingungen oder Fotos.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(product.allDocuments) { document in
                            DocumentTile(document: document, canEdit: document.product != nil) {
                                previewURL = document.temporaryFileURL()
                            } onDelete: {
                                context.delete(document)
                                commit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            AddDocumentMenu { file in
                addDocument(file)
            } label: {
                if isAddingDocument {
                    HStack { ProgressView(); Text("Dokument wird verarbeitet …") }
                } else {
                    Label("Dokument hinzufügen", systemImage: "plus")
                }
            }
            .disabled(isAddingDocument)
        } header: {
            Text("Unterlagen")
        } footer: {
            Text("Originale werden unverändert gespeichert und sind über die Suche auffindbar.")
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        let rows: [(String, String)] = [
            ("Seriennummer", product.serialNumber),
            ("Kategorie", product.category),
            ("Raum", product.room),
            ("Notizen", product.notes)
        ].filter { !$0.1.isEmpty }
        Section("Details") {
            if rows.isEmpty {
                Button("Seriennummer, Raum und Notizen ergänzen") { showEdit = true }
            }
            ForEach(rows, id: \.0) { row in
                LabeledContent(row.0) {
                    Text(row.1).textSelection(.enabled)
                }
            }
        }
    }

    private var claimSection: some View {
        Section("Reklamationen und Rückgaben") {
            ForEach(product.claimList) { claim in
                NavigationLink {
                    ClaimDetailView(claim: claim)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(claim.issue.isEmpty ? claim.kind.label : claim.issue).lineLimit(2)
                        Text("\(claim.kind.label) · \(claim.status.label) · \(Fmt.date(claim.createdAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Reklamation starten", systemImage: "wrench.and.screwdriver") { showClaimEditor = true }
        }
    }

    private var repairSection: some View {
        Section("Reparaturen") {
            ForEach(product.repairList) { repair in
                Button {
                    repairToEdit = repair
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repair.summary.isEmpty ? "Reparatur" : repair.summary).foregroundStyle(.primary)
                        Text([Fmt.date(repair.date), repair.provider,
                              repair.costCents.map { Money.format(cents: $0, currency: product.currency) } ?? ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Löschen", role: .destructive) {
                        context.delete(repair)
                        commit()
                    }
                }
            }
            Button("Reparatur eintragen", systemImage: "plus") { showNewRepair = true }
        }
    }

    // MARK: Aktionen

    private var deleteMessage: String {
        if let receipt = product.receipt, receipt.productList.count <= 1 {
            return "Die zugehörige Rechnung und alle Unterlagen werden ebenfalls gelöscht."
        }
        return "Fristen, eigene Unterlagen und Reklamationen dieses Produkts werden gelöscht. Die Rechnung bleibt bei den anderen Produkten erhalten."
    }

    private func commit() {
        try? context.save()
        Task { await reminders.refresh(context: context) }
    }

    private func addDocument(_ file: ImportedFile) {
        isAddingDocument = true
        Task {
            let isImage = !DocumentRenderer.isPDF(data: file.data, typeIdentifier: file.typeIdentifier)
            let document = await DocumentFactory.make(file: file, kind: isImage ? .photo : .other)
            context.insert(document)
            document.product = product
            isAddingDocument = false
            commit()
        }
    }

    private func deleteProduct() {
        // Erst die Ansicht schliessen, dann löschen – so wird kein gelöschter Eintrag mehr dargestellt.
        let context = self.context
        let reminders = self.reminders
        let product = self.product
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if let receipt = product.receipt, receipt.productList.count <= 1 {
                context.delete(receipt)
            } else {
                context.delete(product)
            }
            try? context.save()
            await reminders.refresh(context: context)
        }
    }
}

struct DocumentTile: View {
    @Bindable var document: StoredDocument
    let canEdit: Bool
    var onOpen: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onOpen) {
                DocumentThumbnail(document: document)
            }
            .buttonStyle(.plain)
            Text(document.displayTitle)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .contextMenu {
            Button("Öffnen", systemImage: "eye", action: onOpen)
            if canEdit {
                Picker("Art", selection: $document.kindRaw) {
                    ForEach(DocumentKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
                }
                Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .accessibilityLabel(document.displayTitle)
    }
}

// MARK: Produkt bearbeiten

struct ProductEditView: View {
    @Bindable var product: OwnedProduct
    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Produkt") {
                    TextField("Bezeichnung", text: $product.name, axis: .vertical)
                    TextField("Marke", text: $product.brand)
                    TextField("Modell", text: $product.modelName)
                    TextField("Seriennummer", text: $product.serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Preis") {
                    HStack {
                        TextField("Stückpreis", text: $priceText)
                            .keyboardType(.decimalPad)
                        Text(product.currency).foregroundStyle(.secondary)
                    }
                    Stepper("Menge \(product.quantity)", value: $product.quantity, in: 1...999)
                }
                Section("Einordnung") {
                    Picker("Kategorie", selection: $product.category) {
                        Text("Keine").tag("")
                        ForEach(categoryOptions, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        TextField("Raum", text: $product.room)
                        Menu {
                            ForEach(Catalog.rooms, id: \.self) { room in
                                Button(room) { product.room = room }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                }
                Section("Notizen") {
                    TextField("Notizen", text: $product.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Produkt bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        product.priceCents = Money.cents(fromText: priceText)
                        dismiss()
                    }
                }
            }
            .onAppear { priceText = Money.plainText(cents: product.priceCents) }
        }
    }

    private var categoryOptions: [String] {
        product.category.isEmpty || Catalog.categories.contains(product.category)
            ? Catalog.categories
            : Catalog.categories + [product.category]
    }
}

// MARK: Frist bearbeiten

struct CoverageEditView: View {
    let product: OwnedProduct
    let coverage: Coverage?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CoverageKind = .manufacturer
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var provider = ""
    @State private var notes = ""
    @State private var remindersEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(CoverageKind.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Beginn", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ende", selection: $endDate, in: startDate..., displayedComponents: .date)
                } footer: {
                    if let basis = coverage?.basis, !basis.isEmpty {
                        Text(basis)
                    }
                }
                Section("Dauer ab Beginn") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            if kind == .returnWindow {
                                ForEach([14, 30, 60, 100], id: \.self) { days in
                                    Button("\(days) Tage") {
                                        endDate = DeadlineRules.endDate(from: startDate, days: days, calendar: .current)
                                    }
                                }
                            } else {
                                ForEach([12, 24, 36, 60, 120], id: \.self) { months in
                                    Button(months % 12 == 0 ? "\(months / 12) J." : "\(months) Mt.") {
                                        endDate = DeadlineRules.endDate(from: startDate, months: months, calendar: .current)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section {
                    TextField(kind == .extended ? "Anbieter" : "Hersteller / Händler", text: $provider)
                    TextField("Notizen, z. B. Vertragsnummer", text: $notes, axis: .vertical)
                    Toggle("An diese Frist erinnern", isOn: $remindersEnabled)
                }
                if coverage?.isConfirmed == false {
                    Section {
                        Label("Mit «Sichern» bestätigst du diesen Vorschlag.", systemImage: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(coverage == nil ? "Neue Frist" : "Frist bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let coverage {
            kind = coverage.kind
            startDate = coverage.startDate
            endDate = coverage.endDate
            provider = coverage.provider
            notes = coverage.notes
            remindersEnabled = coverage.remindersEnabled
        } else {
            let start = product.receipt?.coverageStart ?? product.purchaseDate
            startDate = start
            endDate = DeadlineRules.endDate(from: start, months: 24, calendar: .current)
        }
    }

    private func save() {
        let target: Coverage
        if let coverage {
            target = coverage
        } else {
            target = Coverage(kind: kind, startDate: startDate, endDate: endDate)
            context.insert(target)
            target.product = product
        }
        target.kind = kind
        target.startDate = startDate
        target.endDate = max(endDate, startDate)
        target.provider = provider
        target.notes = notes
        target.remindersEnabled = remindersEnabled
        target.isConfirmed = true
        dismiss()
    }
}

// MARK: Reparatur

struct RepairEditView: View {
    let product: OwnedProduct
    let repair: Repair?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var summary = ""
    @State private var provider = ""
    @State private var costText = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Was wurde gemacht?", text: $summary, axis: .vertical)
                TextField("Werkstatt / Anbieter", text: $provider)
                HStack {
                    TextField("Kosten", text: $costText).keyboardType(.decimalPad)
                    Text(product.currency).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(repair == nil ? "Neue Reparatur" : "Reparatur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let repair else { return }
                date = repair.date
                summary = repair.summary
                provider = repair.provider
                costText = Money.plainText(cents: repair.costCents)
            }
        }
    }

    private func save() {
        let target: Repair
        if let repair {
            target = repair
        } else {
            target = Repair(date: date, summary: summary)
            context.insert(target)
            target.product = product
        }
        target.date = date
        target.summary = summary
        target.provider = provider
        target.costCents = Money.cents(fromText: costText)
        dismiss()
    }
}

// MARK: Rechnung

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderCenter.self) private var reminders

    @State private var totalText = ""
    @State private var previewURL: URL?
    @State private var evidence: EvidenceItem?
    @State private var showDeleteConfirm = false
    @State private var isAddingDocument = false
    @State private var wasDeleted = false

    var body: some View {
        Form {
            Section {
                if receipt.documentList.isEmpty {
                    Text("Zu diesem Kauf ist kein Beleg gespeichert.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(receipt.documentList) { document in
                                DocumentTile(document: document, canEdit: receipt.documentList.count > 1) {
                                    previewURL = document.temporaryFileURL()
                                } onDelete: {
                                    context.delete(document)
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
                AddDocumentMenu { file in
                    isAddingDocument = true
                    Task {
                        let document = await DocumentFactory.make(file: file, kind: .receipt, title: "Rechnung")
                        context.insert(document)
                        document.receipt = receipt
                        try? context.save()
                        isAddingDocument = false
                    }
                } label: {
                    if isAddingDocument {
                        HStack { ProgressView(); Text("Dokument wird verarbeitet …") }
                    } else {
                        Label("Beleg hinzufügen", systemImage: "plus")
                    }
                }
                .disabled(isAddingDocument)
            } header: {
                Text("Originalbeleg")
            }

            Section("Kauf") {
                evidenceField("Händler", line: receipt.merchantLine, value: receipt.merchant) {
                    TextField("Händler", text: $receipt.merchant)
                }
                evidenceField("Kaufdatum", line: receipt.dateLine, value: Fmt.date(receipt.purchaseDate)) {
                    DatePicker("Kaufdatum", selection: $receipt.purchaseDate, displayedComponents: .date)
                }
                evidenceField("Gesamtbetrag", line: receipt.totalLine, value: totalText) {
                    HStack {
                        Text("Gesamtbetrag")
                        Spacer()
                        TextField("0.00", text: $totalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text(receipt.currency).foregroundStyle(.secondary)
                    }
                }
                Toggle("Ware später erhalten (Lieferung)", isOn: Binding(
                    get: { receipt.deliveryDate != nil },
                    set: { receipt.deliveryDate = $0 ? receipt.purchaseDate : nil }
                ))
                if let delivery = receipt.deliveryDate {
                    DatePicker("Erhalten am", selection: Binding(get: { delivery }, set: { receipt.deliveryDate = $0 }),
                               displayedComponents: .date)
                }
                TextField("Bestell- oder Rechnungsnummer", text: $receipt.orderNumber)
                Picker("Kaufart", selection: $receipt.channelRaw) {
                    ForEach(PurchaseChannel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                CountryPicker(selection: $receipt.countryCode)
                TextField("Notizen", text: $receipt.notes, axis: .vertical)
            }

            Section {
                ForEach(receipt.productList) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                            if let price = product.priceCents {
                                Text(Money.format(cents: price, currency: receipt.currency))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Produkte auf dieser Rechnung")
            } footer: {
                Text("Änderungen an Kauf- oder Lieferdatum verschieben bestehende Fristen nicht automatisch – bereits bestätigte Angaben werden nie still überschrieben. Passe sie bei Bedarf in der Produktakte an.")
            }

            Section {
                Button("Rechnung mit allen Produkten löschen", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .navigationTitle("Rechnung")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { totalText = Money.plainText(cents: receipt.totalCents) }
        .onDisappear {
            guard !wasDeleted else { return }
            receipt.totalCents = Money.cents(fromText: totalText)
            try? context.save()
        }
        .sheet(item: $evidence) { item in
            EvidenceView(item: item)
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Rechnung wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                wasDeleted = true
                let context = self.context
                let reminders = self.reminders
                let receipt = self.receipt
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    context.delete(receipt)
                    try? context.save()
                    await reminders.refresh(context: context)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle \(receipt.productList.count) Produkte, ihre Fristen und Unterlagen werden gelöscht.")
        }
    }

    @ViewBuilder
    private func evidenceField<Content: View>(
        _ title: String, line: Int, value: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            content()
            if line >= 0, let document = receipt.documentList.first {
                Button {
                    evidence = document.evidence(title: title, value: value, lineIndex: line)
                } label: {
                    Image(systemName: "text.viewfinder")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(title) im Beleg zeigen")
            }
        }
    }
}
