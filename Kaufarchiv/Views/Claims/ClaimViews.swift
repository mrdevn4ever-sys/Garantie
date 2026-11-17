import SwiftUI
import SwiftData
import PhotosUI
import MessageUI
import UniformTypeIdentifiers
import KaufarchivCore

struct ClaimRow: View {
    let claim: Claim

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: claim.status.symbolName)
                .foregroundStyle(claim.status.isOpen ? Color.orange : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.product?.name ?? "Produkt")
                Text("\(claim.status.title) · \(Formatters.date(claim.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Wizard

/// Guided claim: describe defect → add photos → review documents → message + dossier.
struct ClaimWizardView: View {
    let product: Product

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @AppStorage(SettingsKey.customerName) private var customerName = ""

    enum Step: Int { case describe, photos, review }

    @State private var step: Step = .describe
    @State private var description = ""
    @State private var noticedOn = Date()
    @State private var remedy: ClaimRemedy = .repair
    @State private var coverageKind: CoverageKind?
    @State private var recipient = ""
    @State private var photos: [IncomingFile] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var createdClaim: Claim?
    @State private var showPaywall = false
    @State private var error: String?

    private var activeCoverages: [Coverage] { product.coverageList.filter { $0.status.isActive } }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .describe: describeStep
                case .photos: photoStep
                case .review: reviewStep
                }
            }
            .navigationTitle("Defekt melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if step != .describe {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zurück") { step = Step(rawValue: step.rawValue - 1) ?? .describe }
                    }
                }
            }
            .onAppear {
                coverageKind = coverageKind ?? activeCoverages.first(where: { $0.kind == .statutory || $0.kind == .manufacturer })?.kind ?? activeCoverages.first?.kind
                if recipient.isEmpty { recipient = product.purchase?.merchant ?? "" }
            }
            .navigationDestination(item: $createdClaim) { claim in
                ClaimDetailView(claim: claim, onClose: { dismiss() })
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: "Reklamationsdossiers sind Teil von Kaufarchiv Pro. Dein Nachrichtenentwurf und alle Unterlagen bleiben auch ohne Pro verfügbar.")
            }
            .alert("Fehler", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var describeStep: some View {
        Form {
            Section {
                HStack {
                    ProductIcon(product: product, size: 40)
                    VStack(alignment: .leading) {
                        Text(product.name).font(.headline)
                        if !product.serialNumber.isEmpty {
                            Text("S/N \(product.serialNumber)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                TextField("Was funktioniert nicht? Seit wann? Wie oft?", text: $description, axis: .vertical)
                    .lineLimit(4...12)
                DatePicker("Festgestellt am", selection: $noticedOn, in: min(product.purchaseDate, Date())...Date(), displayedComponents: .date)
            } header: {
                Text("Mangel beschreiben")
            } footer: {
                Text("Beschreibe sachlich und konkret. Melde Mängel möglichst sofort nach der Entdeckung.")
            }
            Section("Grundlage") {
                if activeCoverages.isEmpty {
                    Label("Keine laufende Frist erfasst. Du kannst trotzdem beim Händler oder Hersteller nachfragen.", systemImage: "info.circle")
                        .font(.subheadline)
                }
                Picker("Anspruch aus", selection: $coverageKind) {
                    Text("Nicht angeben").tag(CoverageKind?.none)
                    ForEach(activeCoverages) { coverage in
                        Text("\(coverage.kind.title) (\(coverage.status.label))").tag(CoverageKind?.some(coverage.kind))
                    }
                }
                Picker("Gewünschte Lösung", selection: $remedy) {
                    ForEach(ClaimRemedy.allCases) { Text($0.title).tag($0) }
                }
                TextField("Empfänger (Händler/Hersteller)", text: $recipient)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Weiter zu den Fotos", enabled: description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5) {
                step = .photos
            }
        }
    }

    private var photoStep: some View {
        List {
            Section {
                if photos.isEmpty {
                    Text("Fotos oder ein kurzes Bildschirmfoto der Fehlermeldung helfen bei der Bearbeitung.")
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(photos) { file in
                            if let image = DocumentStore.downsample(data: file.data, maxPixel: 300) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            photos.removeAll { $0.id == file.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .padding(4)
                                    }
                            }
                        }
                    }
                }
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("Fotos des Mangels")
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: photos.isEmpty ? "Ohne Fotos weiter" : "Weiter") { step = .review }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let file = IncomingFile.image(image, name: "Mangel-\(photos.count + 1)") { photos.append(file) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let type = item.supportedContentTypes.first ?? .jpeg
                        photos.append(IncomingFile(data: data, filename: "Mangel-\(photos.count + 1).\(type.preferredFilenameExtension ?? "jpg")", type: type))
                    }
                }
                photoItems = []
            }
        }
    }

    private var reviewStep: some View {
        List {
            Section("Diese Unterlagen werden zusammengestellt") {
                ForEach(product.purchase?.receiptDocuments ?? []) { doc in
                    Label(doc.title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if product.purchase?.receiptDocuments.isEmpty ?? true {
                    Label("Kein Beleg vorhanden", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                ForEach(product.documentList.filter { $0.kind == .warrantyTerms }) { doc in
                    Label(doc.title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if !product.serialNumber.isEmpty {
                    Label("Seriennummer \(product.serialNumber)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Keine Seriennummer erfasst", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Label(photos.count == 1 ? "1 Foto" : "\(photos.count) Fotos", systemImage: photos.isEmpty ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(photos.isEmpty ? Color.secondary : Color.green)
                Label("Verlauf mit \(product.eventList.count) Einträgen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Section {
                Text(previewBody)
                    .font(.footnote)
                    .textSelection(.enabled)
            } header: {
                Text("Nachrichtenentwurf")
            } footer: {
                Text("Du kannst den Text im nächsten Schritt anpassen.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            NextButton(title: "Reklamation anlegen", action: create)
        }
    }

    private var context_: ClaimContext {
        ClaimContext(productName: product.name, brand: product.brand, model: product.modelName, serialNumber: product.serialNumber,
                     merchant: product.purchase?.merchant, purchaseDate: product.purchaseDate,
                     price: product.price.map { Formatters.money($0, currency: product.purchase?.currency ?? "CHF") },
                     orderNumber: product.purchase?.orderNumber, defectDescription: description, defectNoticedOn: noticedOn,
                     requestedRemedy: remedy, coverage: coverageKind,
                     coverageEnd: product.coverageList.first { $0.kind == coverageKind }?.endDate,
                     customerName: customerName,
                     attachments: attachmentNames)
    }

    private var attachmentNames: [String] {
        var names = ["Kaufbeleg"]
        if !photos.isEmpty { names.append(photos.count == 1 ? "1 Foto des Mangels" : "\(photos.count) Fotos des Mangels") }
        if product.documentList.contains(where: { $0.kind == .warrantyTerms }) { names.append("Garantiebedingungen") }
        return names
    }

    private var previewBody: String { ClaimTemplate.body(context_) }

    private func create() {
        do {
            let claim = Claim(product: product)
            claim.defectDescription = description
            claim.defectNoticedOn = noticedOn
            claim.remedy = remedy
            claim.coverageKind = coverageKind
            claim.recipient = recipient
            claim.messageSubject = ClaimTemplate.subject(context_)
            claim.messageBody = previewBody
            context.insert(claim)
            claim.product = product
            for file in photos {
                let doc = try DocumentStore.makeDocument(from: file, kind: .photo, title: "Foto des Mangels", in: context)
                doc.claim = claim
            }
            let update = ClaimUpdate(text: "Reklamation angelegt")
            context.insert(update)
            update.claim = claim
            let event = ProductEvent(kind: .claim, title: "Reklamation angelegt", details: description)
            context.insert(event)
            event.product = product
            if store.isPro {
                _ = try DossierService.attachDossier(to: claim, context: context)
            }
            try context.save()
            createdClaim = claim
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct ClaimDetailView: View {
    @Bindable var claim: Claim
    var onClose: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ReminderService.self) private var reminders

    @State private var shareItems: [Any]?
    @State private var showMail = false
    @State private var mailAttachments: [(Data, String, String)] = []
    @State private var newUpdate = ""
    @State private var viewing: StoredDocument?
    @State private var working = false
    @State private var info: String?

    var body: some View {
        List {
            Section {
                if let product = claim.product {
                    NavigationLink(value: product) { ProductRow(product: product) }
                }
                Picker("Status", selection: Binding(get: { claim.status }, set: { setStatus($0) })) {
                    ForEach(ClaimStatus.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                InfoRow(label: "Festgestellt am", value: Formatters.date(claim.defectNoticedOn))
                InfoRow(label: "Gewünschte Lösung", value: claim.remedy.title)
                InfoRow(label: "Empfänger", value: claim.recipient)
            }

            Section("Versenden") {
                Button {
                    Task { await send() }
                } label: {
                    Label(MFMailComposeViewController.canSendMail() ? "Per E-Mail senden" : "Nachricht und Unterlagen teilen", systemImage: "paperplane")
                }
                .disabled(working)
                Button {
                    UIPasteboard.general.string = claim.messageSubject + "\n\n" + claim.messageBody
                    info = "Text kopiert. Du kannst ihn in ein Kontaktformular einfügen."
                } label: {
                    Label("Text kopieren", systemImage: "doc.on.doc")
                }
                if store.isPro {
                    Button {
                        regenerateDossier()
                    } label: {
                        Label(claim.dossier == nil ? "Dossier erstellen" : "Dossier aktualisieren", systemImage: "doc.richtext")
                    }
                    if let dossier = claim.dossier {
                        Button { viewing = dossier } label: { Label("Dossier ansehen", systemImage: "eye") }
                    }
                } else {
                    Button {
                        router.requestPro(reason: "Mit Pro erstellt Kaufarchiv ein übersichtliches PDF-Dossier mit Rechnung, Seriennummer, Fotos und Verlauf.")
                    } label: {
                        Label("PDF-Dossier (Pro)", systemImage: "lock")
                    }
                }
            }

            Section("Nachricht") {
                TextField("Betreff", text: $claim.messageSubject, axis: .vertical)
                    .font(.subheadline.weight(.semibold))
                TextEditor(text: $claim.messageBody)
                    .frame(minHeight: 220)
                    .font(.footnote)
            }

            Section("Beschreibung") {
                TextField("Beschreibung", text: $claim.defectDescription, axis: .vertical)
            }

            if !claim.photos.isEmpty {
                Section("Fotos") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(claim.photos) { photo in
                                Button { viewing = photo } label: { DocumentThumbnail(document: photo, size: 70) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section("Verlauf") {
                HStack {
                    TextField("z. B. Fall-Nr. 4711, Gerät abgegeben", text: $newUpdate)
                    Button("Hinzufügen") { addUpdate() }
                        .disabled(newUpdate.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(claim.updateList) { update in
                    VStack(alignment: .leading) {
                        Text(update.text)
                        Text(Formatters.date(update.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !claim.status.isOpen {
                Section("Ergebnis") {
                    TextField("z. B. Gerät ersetzt, Gutschrift erhalten", text: $claim.resolution, axis: .vertical)
                }
            }
        }
        .navigationTitle("Reklamation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { try? context.save(); onClose() } }
            }
        }
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
        .sheet(item: $viewing) { DocumentViewer(document: $0) }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            ShareSheet(items: shareItems ?? [])
        }
        .sheet(isPresented: $showMail) {
            MailComposer(recipients: [], subject: claim.messageSubject, body: claim.messageBody, attachments: mailAttachments) { sent in
                showMail = false
                if sent { setStatus(.sent) }
            }
            .ignoresSafeArea()
        }
        .alert("Hinweis", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(info ?? "") }
        .onDisappear { try? context.save() }
    }

    private func setStatus(_ status: ClaimStatus) {
        guard status != claim.status else { return }
        claim.status = status
        let update = ClaimUpdate(text: "Status: \(status.title)")
        context.insert(update)
        update.claim = claim
        if let product = claim.product {
            switch status {
            case .sent, .inProgress:
                if product.status == .inUse, status == .inProgress { product.status = .inRepair }
            case .resolved, .rejected:
                if product.status == .inRepair { product.status = .inUse }
            case .draft:
                break
            }
        }
        try? context.save()
        if status == .sent {
            // Follow up if the merchant does not answer within 10 days.
            let date = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
            Task {
                await reminders.scheduleFollowUp(id: claim.id.uuidString, title: "Antwort zur Reklamation?",
                                                 body: "\(claim.product?.name ?? "Produkt"): Hast du eine Rückmeldung erhalten?", at: date)
            }
        }
    }

    private func addUpdate() {
        let update = ClaimUpdate(text: newUpdate.trimmingCharacters(in: .whitespaces))
        context.insert(update)
        update.claim = claim
        newUpdate = ""
        try? context.save()
    }

    private func regenerateDossier() {
        do {
            _ = try DossierService.attachDossier(to: claim, context: context)
            info = "Das Dossier wurde aktualisiert."
        } catch {
            info = error.localizedDescription
        }
    }

    /// Collects message, receipts, photos and (with Pro) the dossier.
    private func attachments() -> [(Data, String, String)] {
        var result: [(Data, String, String)] = []
        if store.isPro, let dossier = claim.dossier, let data = dossier.originalData {
            result.append((data, "application/pdf", dossier.originalFilename))
        } else {
            for doc in claim.product?.purchase?.receiptDocuments ?? [] {
                if let data = doc.originalData {
                    result.append((data, UTTypeMime.mime(for: doc.contentType), doc.originalFilename.isEmpty ? "Beleg.\(doc.isPDF ? "pdf" : "jpg")" : doc.originalFilename))
                }
            }
            for (index, photo) in claim.photos.enumerated() {
                if let data = photo.originalData {
                    result.append((data, UTTypeMime.mime(for: photo.contentType), photo.originalFilename.isEmpty ? "Foto-\(index + 1).jpg" : photo.originalFilename))
                }
            }
        }
        return result
    }

    private func send() async {
        working = true
        defer { working = false }
        let files = attachments()
        if MFMailComposeViewController.canSendMail() {
            mailAttachments = files
            showMail = true
        } else {
            var items: [Any] = [claim.messageSubject + "\n\n" + claim.messageBody]
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(claim.id.uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (data, _, name) in files {
                let url = folder.appendingPathComponent(name)
                if (try? data.write(to: url)) != nil { items.append(url) }
            }
            shareItems = items
        }
    }
}

enum UTTypeMime {
    static func mime(for identifier: String) -> String {
        UTType(identifier)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// Mail composer with attachments.
struct MailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [(Data, String, String)]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        for (data, mime, name) in attachments {
            controller.addAttachmentData(data, mimeType: mime, fileName: name)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
        }
    }
}
