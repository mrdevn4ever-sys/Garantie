import SwiftUI
import SwiftData
import QuickLook
import KaufarchivCore

// MARK: Reklamation starten (aus der Übersicht)

struct ClaimStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OwnedProduct.createdAt, order: .reverse) private var products: [OwnedProduct]
    @State private var query = ""

    private var candidates: [OwnedProduct] {
        products.filter { $0.status == .active && $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(candidates) { product in
                    NavigationLink {
                        ClaimEditorForm(product: product) { dismiss() }
                    } label: {
                        ProductRow(product: product)
                    }
                }
            }
            .navigationTitle("Was ist kaputt?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Produkt suchen, z. B. Kaffeemaschine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

/// Reklamation für ein bereits gewähltes Produkt (aus der Produktakte).
struct ClaimEditorView: View {
    let product: OwnedProduct
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClaimEditorForm(product: product) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
        }
    }
}

struct ClaimEditorForm: View {
    let product: OwnedProduct
    var onDone: () -> Void

    @Environment(\.modelContext) private var context

    @State private var issue = ""
    @State private var remedy: ClaimRemedy = .open
    @State private var contact = ""
    @State private var photos: [ImportedFile] = []
    @State private var isSaving = false
    @State private var created: Claim?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(.headline)
                    Text("\(product.receipt?.displayMerchant ?? "Ohne Rechnung") · gekauft am \(Fmt.date(product.purchaseDate))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                coverageStatus
            }
            Section("Was ist das Problem?") {
                TextField("Beschreibe den Mangel: Was funktioniert nicht, seit wann, was hast du schon versucht?",
                          text: $issue, axis: .vertical)
                    .lineLimit(4...10)
            }
            Section("Was wünschst du dir?") {
                Picker("Lösung", selection: $remedy) {
                    ForEach(ClaimRemedy.allCases) { Text($0.label).tag($0) }
                }
                TextField("Kontakt des Händlers (E-Mail, optional)", text: $contact)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    HStack {
                        Image(systemName: "photo")
                        Text(photo.filename).lineLimit(1)
                        Spacer()
                        Button {
                            photos.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                AddDocumentMenu { file in
                    photos.append(file)
                } label: {
                    Label("Foto oder Dokument ergänzen", systemImage: "plus")
                }
            } header: {
                Text("Fotos vom Mangel")
            } footer: {
                Text("Rechnung und vorhandene Unterlagen des Produkts (\(product.allDocuments.count)) werden automatisch beigelegt.")
            }
        }
        .navigationTitle("Reklamation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Weiter") { save() }
                        .disabled(issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationDestination(item: $created) { claim in
            ClaimDetailView(claim: claim, onDone: onDone)
        }
    }

    @ViewBuilder
    private var coverageStatus: some View {
        if let best = product.bestActiveCoverage() {
            Label("\(best.kind.label) bis \(Fmt.date(best.endDate))\(best.isConfirmed ? "" : " (unbestätigter Vorschlag)")",
                  systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.green)
        } else if product.coverageList.isEmpty {
            Label("Für dieses Produkt sind keine Fristen erfasst.", systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Label("Die erfassten Fristen sind abgelaufen. Eine Anfrage auf Kulanz kann sich trotzdem lohnen.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let claim = Claim(issue: issue.trimmingCharacters(in: .whitespacesAndNewlines))
            claim.remedy = remedy
            claim.contact = contact.trimmingCharacters(in: .whitespaces)
            context.insert(claim)
            claim.product = product

            let event = ClaimEvent(text: "Mangel erfasst")
            context.insert(event)
            event.claim = claim

            for photo in photos {
                let isImage = !DocumentRenderer.isPDF(data: photo.data, typeIdentifier: photo.typeIdentifier)
                let document = await DocumentFactory.make(file: photo, kind: isImage ? .photo : .other, title: isImage ? "Foto vom Mangel" : "")
                context.insert(document)
                document.claim = claim
            }
            try? context.save()
            isSaving = false
            created = claim
        }
    }
}

// MARK: Reklamation verfolgen

struct ClaimDetailView: View {
    @Bindable var claim: Claim
    var onDone: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage(Prefs.senderName) private var senderName = ""

    @State private var newEvent = ""
    @State private var previewURL: URL?
    @State private var dossierURL: URL?
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var isAddingDocument = false

    private var isGone: Bool { claim.isDeleted || claim.modelContext == nil }

    var body: some View {
        Group {
            if isGone {
                ContentUnavailableView("Reklamation gelöscht", systemImage: "trash")
            } else {
                content
            }
        }
        .onAppear {
            if isGone { dismiss() }
        }
    }

    private var attachmentCount: Int {
        claim.documentList.count + (claim.product?.allDocuments.count ?? 0)
    }

    private var claimContext: ClaimContext {
        DossierBuilder.context(for: claim, senderName: senderName, attachmentCount: attachmentCount)
    }

    private var messageBody: String { ClaimComposer.body(claimContext) }
    private var messageSubject: String { ClaimComposer.subject(claimContext) }

    private var content: some View {
        Form {
            Section {
                LabeledContent("Produkt", value: claim.product?.displayName ?? "–")
                Picker("Status", selection: $claim.statusRaw) {
                    ForEach(ClaimStatus.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: claim.statusRaw) { old, new in
                    let from = ClaimStatus(rawValue: old)?.label ?? old
                    let to = ClaimStatus(rawValue: new)?.label ?? new
                    addEvent("Status: \(from) → \(to)")
                }
                TextField("Kontakt des Händlers (E-Mail)", text: $claim.contact)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Vorgangsnummer des Händlers", text: $claim.reference)
                    .autocorrectionDisabled()
            }

            Section("Mangel") {
                TextField("Beschreibung", text: $claim.issue, axis: .vertical)
                    .lineLimit(3...10)
                Picker("Gewünschte Lösung", selection: $claim.remedyRaw) {
                    ForEach(ClaimRemedy.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }

            Section {
                if !claim.documentList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(claim.documentList) { document in
                                DocumentTile(document: document, canEdit: true) {
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
                        let isImage = !DocumentRenderer.isPDF(data: file.data, typeIdentifier: file.typeIdentifier)
                        let document = await DocumentFactory.make(file: file, kind: isImage ? .photo : .correspondence)
                        context.insert(document)
                        document.claim = claim
                        try? context.save()
                        isAddingDocument = false
                    }
                } label: {
                    if isAddingDocument {
                        HStack { ProgressView(); Text("Wird verarbeitet …") }
                    } else {
                        Label("Foto oder Antwort des Händlers ergänzen", systemImage: "plus")
                    }
                }
                .disabled(isAddingDocument)
            } header: {
                Text("Fotos und Korrespondenz")
            }

            Section {
                TextField("Dein Name für die Grussformel", text: $senderName)
                    .textContentType(.name)
                Text(messageBody)
                    .font(.footnote)
                    .textSelection(.enabled)
                Button(copied ? "Kopiert" : "Text kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = messageBody
                    copied = true
                }
                Button("In Mail öffnen", systemImage: "envelope") { openMail() }
                ShareLink(item: messageBody, subject: Text(messageSubject)) {
                    Label("Text teilen", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Nachrichtenentwurf")
            } footer: {
                Text("Der Entwurf ist eine Formulierungshilfe und keine Rechtsberatung. Bitte vor dem Senden prüfen.")
            }

            Section {
                Button {
                    buildDossier()
                } label: {
                    HStack {
                        Label("Dossier als PDF erstellen", systemImage: "doc.richtext")
                        Spacer()
                        if !purchases.isPro { ProBadge() }
                    }
                }
                if let dossierURL {
                    Button("Dossier ansehen", systemImage: "eye") { previewURL = dossierURL }
                    ShareLink(item: dossierURL) {
                        Label("Dossier teilen oder senden", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Reklamationsdossier")
            } footer: {
                Text("Ein PDF mit Produktdaten, Mangelbeschreibung, Verlauf, Fotos und allen \(attachmentCount) Unterlagen – zum Anhängen an deine Nachricht.")
            }

            Section("Verlauf") {
                ForEach(claim.eventList) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.text)
                        Text(Fmt.dateTime(event.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Löschen", role: .destructive) {
                            context.delete(event)
                            try? context.save()
                        }
                    }
                }
                HStack {
                    TextField("Neuer Eintrag, z. B. «Gerät eingeschickt»", text: $newEvent)
                    Button {
                        addEvent(newEvent)
                        newEvent = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(newEvent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button("Reklamation löschen", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .navigationTitle("Reklamation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(onDone != nil)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        try? context.save()
                        onDone()
                    }
                }
            }
        }
        .onDisappear { try? context.save() }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Das Reklamationsdossier fasst alle Unterlagen in einem PDF zusammen und ist Teil von Kaufarchiv Pro. Nachrichtenentwurf und Originalbelege bleiben kostenlos.")
        }
        .alert("Dossier konnte nicht erstellt werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Reklamation wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteClaim() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Verlauf und Fotos dieser Reklamation werden gelöscht. Das Produkt bleibt erhalten.")
        }
    }

    private func addEvent(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let event = ClaimEvent(text: trimmed)
        context.insert(event)
        event.claim = claim
        try? context.save()
    }

    private func buildDossier() {
        guard purchases.isPro else {
            showPaywall = true
            return
        }
        do {
            try? context.save()
            let url = try DossierBuilder.build(claim: claim)
            dossierURL = url
            previewURL = url
            addEvent("Dossier erstellt")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = claim.contact.contains("@") ? claim.contact : ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: messageSubject),
            URLQueryItem(name: "body", value: messageBody)
        ]
        if let url = components.url {
            openURL(url) { accepted in
                if !accepted { errorMessage = "Auf diesem Gerät ist keine Mail-App eingerichtet. Kopiere stattdessen den Text." }
            }
        }
    }

    private func deleteClaim() {
        let context = self.context
        let claim = self.claim
        if let onDone { onDone() } else { dismiss() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            context.delete(claim)
            try? context.save()
        }
    }
}
