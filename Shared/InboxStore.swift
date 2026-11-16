import Foundation

/// Ein Beleg, der übernommen, aber noch nicht geprüft und gespeichert wurde.
struct InboxItem: Identifiable, Hashable {
    var id: String { url.lastPathComponent }
    let url: URL
    let displayName: String
    let addedAt: Date
    let byteCount: Int
}

/// Gemeinsamer Eingang von App und Teilen-Erweiterung.
/// Die Erweiterung legt nur Dateien ab; Erkennung und Datenbankänderungen macht ausschliesslich die Haupt-App.
enum InboxStore {
    /// Muss mit den App-Group-Einträgen beider Entitlements übereinstimmen.
    static let appGroupID = "group.ch.kaufarchiv.app"
    static let maxFileBytes = 50 * 1024 * 1024

    enum InboxError: LocalizedError {
        case tooLarge
        case unavailable

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Die Datei ist grösser als 50 MB und kann nicht übernommen werden."
            case .unavailable: return "Der Eingang von Kaufarchiv ist nicht erreichbar."
            }
        }
    }

    /// `true`, wenn der gemeinsame App-Group-Ordner zur Verfügung steht (Voraussetzung für die Teilen-Erweiterung).
    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static func folder(requireShared: Bool = false) throws -> URL {
        let manager = FileManager.default
        let base: URL
        if let group = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            base = group
        } else if requireShared {
            throw InboxError.unavailable
        } else {
            base = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
        let folder = base.appendingPathComponent("Eingang", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Legt eine Datei im Eingang ab. Der Dateiname beginnt mit einer eindeutigen Kennung, der Rest bleibt lesbar.
    @discardableResult
    static func add(data: Data, filename: String, requireShared: Bool = false) throws -> URL {
        guard data.count <= maxFileBytes else { throw InboxError.tooLarge }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        var name = filename.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Beleg" }
        let url = try folder(requireShared: requireShared)
            .appendingPathComponent("\(UUID().uuidString.prefix(8))_\(name)")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func items() -> [InboxItem] {
        guard let folder = try? folder(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]
              ) else { return [] }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let raw = url.lastPathComponent
            let name = raw.firstIndex(of: "_").map { String(raw[raw.index(after: $0)...]) } ?? raw
            return InboxItem(
                url: url,
                displayName: name,
                addedAt: values?.creationDate ?? Date(),
                byteCount: values?.fileSize ?? 0
            )
        }
        .sorted { $0.addedAt > $1.addedAt }
    }

    static func remove(_ item: InboxItem) {
        try? FileManager.default.removeItem(at: item.url)
    }
}
