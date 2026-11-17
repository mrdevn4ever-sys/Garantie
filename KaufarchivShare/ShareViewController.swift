import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share extension: receives images and PDFs from other apps (Mail, Files, Safari, Photos)
/// and places them in the shared inbox. The main app imports them on next launch.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model, onClose: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { await model.receive(items: extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable {
        case working
        case done(count: Int)
        case failed(String)
    }

    @Published var state: State = .working

    func receive(items: [NSExtensionItem]) async {
        let batch = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(6)
        var count = 0
        var index = 0
        for item in items {
            for provider in item.attachments ?? [] {
                index += 1
                if let (data, name) = await load(provider: provider, index: index) {
                    do {
                        try SharedInbox.store(data: data, filename: name, batch: batch)
                        count += 1
                    } catch {
                        state = .failed("Die Datei konnte nicht gespeichert werden.")
                        return
                    }
                }
            }
        }
        state = count > 0 ? .done(count: count) : .failed("Es wurde kein Bild und kein PDF gefunden.")
    }

    private func load(provider: NSItemProvider, index: Int) async -> (Data, String)? {
        let candidates: [UTType] = [.pdf, .heic, .jpeg, .png, .image]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let result = await loadFile(provider: provider, type: type, index: index) {
                return result
            }
        }
        return nil
    }

    private func loadFile(provider: NSItemProvider, type: UTType, index: Int) async -> (Data, String)? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
                let base = provider.suggestedName ?? url.deletingPathExtension().lastPathComponent
                let name = String(format: "%02d-", index) + base + "." + ext
                continuation.resume(returning: (data, name))
            }
        }
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch model.state {
                case .working:
                    ProgressView("Wird gesichert …")
                case let .done(count):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text(count == 1 ? "1 Datei bereit zum Erfassen" : "\(count) Dateien bereit zum Erfassen")
                        .font(.headline)
                    Text("Öffne Kaufarchiv, um Produkte auszuwählen und Fristen zu bestätigen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Fertig", action: onClose)
                        .buttonStyle(.borderedProminent)
                case let .failed(message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig", action: onClose)
                }
            }
            .navigationTitle("Kaufarchiv")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
