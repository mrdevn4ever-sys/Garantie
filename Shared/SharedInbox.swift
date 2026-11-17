import Foundation

/// Files shared from other apps are dropped into the App Group container by the share
/// extension and picked up by the main app the next time it becomes active.
enum SharedInbox {
    static let appGroupID = "group.ch.kaufarchiv.app"

    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let url = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies a file into the inbox. Each shared batch gets its own folder so multi-page
    /// receipts stay together.
    @discardableResult
    static func store(data: Data, filename: String, batch: String) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let folder = directory.appendingPathComponent(batch, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        let target = folder.appendingPathComponent(safeName)
        try data.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }

    /// Batches waiting to be imported, oldest first.
    static func pendingBatches() -> [URL] {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }
    }

    static func files(in batch: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: batch, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(batch: URL) {
        try? FileManager.default.removeItem(at: batch)
    }
}
