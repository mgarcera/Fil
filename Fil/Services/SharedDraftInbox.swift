import Foundation

/// Cross-process hand-off for content shared into Fil from the Share Extension.
///
/// The extension writes shared text and images into the App Group container; the
/// main app drains the inbox on activation and turns each item into a fil. Kept
/// Foundation-only so it compiles cleanly into both the app and the extension target.
enum SharedDraftInbox {
    /// Must match the App Groups capability enabled on both the app and the extension.
    static let appGroupIdentifier = "group.com.masongarcera.Fil"

    /// One piece of content shared into Fil, with any accompanying images loaded.
    struct InboundDraft: Identifiable {
        let id: UUID
        let text: String
        let images: [Data]
        let createdAt: Date
    }

    // MARK: - Writing (extension side)

    /// Persists one shared item into the App Group inbox. Safe to call from an extension.
    static func append(text: String?, imageData: [Data]) {
        guard let directory = inboxDirectory() else { return }

        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedText.isEmpty || !imageData.isEmpty else { return }

        let id = UUID()
        var imageFileNames: [String] = []
        for (index, data) in imageData.enumerated() {
            let fileName = "\(id.uuidString)-\(index).img"
            do {
                try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
                imageFileNames.append(fileName)
            } catch {
                continue
            }
        }

        let record = StoredRecord(
            id: id,
            text: trimmedText,
            imageFileNames: imageFileNames,
            createdAt: Date()
        )
        guard let encoded = try? JSONEncoder().encode(record) else { return }
        try? encoded.write(to: directory.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
    }

    // MARK: - Reading (main app side)

    /// Returns all pending drafts (oldest first) and removes them from the inbox.
    static func drain() -> [InboundDraft] {
        guard let directory = inboxDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }

        var drafts: [InboundDraft] = []
        for recordURL in entries where recordURL.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: recordURL) }

            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? JSONDecoder().decode(StoredRecord.self, from: data) else {
                continue
            }

            var images: [Data] = []
            for fileName in record.imageFileNames {
                let imageURL = directory.appendingPathComponent(fileName)
                if let imageData = try? Data(contentsOf: imageURL) {
                    images.append(imageData)
                }
                try? FileManager.default.removeItem(at: imageURL)
            }

            drafts.append(
                InboundDraft(id: record.id, text: record.text, images: images, createdAt: record.createdAt)
            )
        }

        return drafts.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Storage

    private struct StoredRecord: Codable {
        let id: UUID
        let text: String
        let imageFileNames: [String]
        let createdAt: Date
    }

    private static func inboxDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let directory = container.appendingPathComponent("SharedInbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
