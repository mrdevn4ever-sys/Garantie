import SwiftUI
import PDFKit
import KaufarchivCore

/// Shows a page with an optional highlighted area – used to show where a value was found.
struct HighlightedPageView: View {
    let image: UIImage
    var highlight: NormalizedRect?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedSize(for: image.size, in: geo.size)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fitted.width * scale, height: fitted.height * scale)
                    if let h = highlight {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.yellow.opacity(0.28))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.orange, lineWidth: 2))
                            .frame(width: max(h.width * fitted.width * scale, 12) + 8,
                                   height: max(h.height * fitted.height * scale, 10) + 8)
                            .offset(x: h.x * fitted.width * scale - 4, y: h.y * fitted.height * scale - 4)
                            .accessibilityLabel("Markierte Stelle")
                    }
                }
                .frame(width: max(fitted.width * scale, geo.size.width), height: max(fitted.height * scale, geo.size.height))
            }
            .gesture(MagnifyGesture()
                .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
                .onEnded { _ in lastScale = scale })
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
        }
    }

    private func fittedSize(for size: CGSize, in container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return container }
        let ratio = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }
}

/// Full-screen viewer for a stored document, with optional highlight.
struct DocumentViewer: View {
    let document: StoredDocument
    var highlight: SourceLocation?

    @Environment(\.dismiss) private var dismiss
    @State private var pages: [UIImage] = []
    @State private var currentPage = 0
    @State private var shareURL: URL?
    @State private var integrityOK: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ProgressView()
                } else {
                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, image in
                            HighlightedPageView(image: image, highlight: highlight?.page == index ? highlight?.rect : nil)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shareURL = try? DocumentStore.temporaryURL(for: document)
                    } label: {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if let highlight {
                        Text("Gefunden: „\(highlight.excerpt)“")
                            .font(.caption)
                            .lineLimit(2)
                    } else if let integrityOK {
                        Label(integrityOK ? "Original unverändert" : "Prüfsumme stimmt nicht",
                              systemImage: integrityOK ? "checkmark.seal" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(integrityOK ? Color.secondary : Color.red)
                    }
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .task {
                guard let data = document.originalData else { return }
                let isPDF = document.isPDF
                let images = await Task.detached { DocumentStore.pageImages(for: data, isPDF: isPDF, maxPixel: 2400) }.value
                pages = images
                if let page = highlight?.page, page < images.count { currentPage = page }
                integrityOK = DocumentStore.verify(document)
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Shows where a value came from in a stored purchase (receipts may have several pages/files).
struct PurchaseSourceViewer: View {
    let purchase: Purchase
    let source: SourceLocation

    var body: some View {
        if let match = purchase.locate(source: source) {
            DocumentViewer(document: match.0, highlight: match.1)
        } else {
            ContentUnavailableView("Beleg nicht verfügbar", systemImage: "doc.questionmark")
        }
    }
}

extension Purchase {
    /// Maps a global page number (across all receipt files) to the document and local page.
    func locate(source: SourceLocation) -> (StoredDocument, SourceLocation)? {
        var offset = 0
        for doc in receiptDocuments {
            if source.page < offset + doc.pageCount {
                var local = source
                local.page = source.page - offset
                return (doc, local)
            }
            offset += doc.pageCount
        }
        return nil
    }
}
