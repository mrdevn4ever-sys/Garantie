import UIKit
import UniformTypeIdentifiers

/// Teilen-Erweiterung: nimmt PDFs und Bilder aus anderen Apps entgegen und legt sie unverändert im Eingang ab.
/// Sie liest keinen Inhalt aus, öffnet keine Links und verändert keine Daten der Haupt-App.
final class ShareViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "Beleg wird an Kaufarchiv übergeben …"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
        spinner.startAnimating()

        Task { @MainActor in
            await handleSharedItems()
        }
    }

    @MainActor
    private func handleSharedItems() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        var saved = 0
        var lastError: String?
        for provider in providers {
            do {
                guard let (data, name) = try await load(provider) else { continue }
                try InboxStore.add(data: data, filename: name, requireShared: true)
                saved += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        spinner.stopAnimating()
        if saved > 0 {
            label.text = saved == 1
                ? "Im Eingang gesichert.\nÖffne Kaufarchiv, um den Beleg zu erfassen."
                : "\(saved) Belege im Eingang gesichert.\nÖffne Kaufarchiv, um sie zu erfassen."
        } else {
            label.text = lastError ?? "Es wurde kein PDF oder Bild gefunden, das übernommen werden kann."
        }
        try? await Task.sleep(nanoseconds: saved > 0 ? 1_400_000_000 : 2_600_000_000)
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Lädt PDF- oder Bilddaten samt Dateinamen. Andere Inhalte (Text, Links) werden bewusst ignoriert.
    private func load(_ provider: NSItemProvider) async throws -> (Data, String)? {
        let type: UTType
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            type = .pdf
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            type = .image
        } else {
            return nil
        }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? InboxStore.InboxError.unavailable)
                }
            }
        }
        let fallbackExtension = type == .pdf ? "pdf" : imageExtension(for: provider)
        var name = provider.suggestedName ?? "Beleg"
        if (name as NSString).pathExtension.isEmpty { name += ".\(fallbackExtension)" }
        return (data, name)
    }

    private func imageExtension(for provider: NSItemProvider) -> String {
        for identifier in provider.registeredTypeIdentifiers {
            if let type = UTType(identifier), type.conforms(to: .image), let ext = type.preferredFilenameExtension {
                return ext
            }
        }
        return "jpg"
    }
}
