import Foundation
import WidgetKit

struct PinnedFilSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var previewText: String
    var keyword: String
    var gradientStartHex: String
    var gradientEndHex: String
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        previewText: String,
        keyword: String,
        gradientStartHex: String = "#408CD9",
        gradientEndHex: String = "#6659CC",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.previewText = previewText
        self.keyword = keyword
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.updatedAt = updatedAt
    }
}

final class PinnedFilStore {
    static let shared = PinnedFilStore()

    static let appGroupIdentifier = "group.com.masongarcera.Fil"
    /// Name of the JSON payload in the shared App Group container. A file is used
    /// instead of UserDefaults because a warm widget-extension process caches its
    /// App Group UserDefaults instance and can serve a stale snapshot after the
    /// app writes a new pin; reading a file from disk is always current.
    private static let pinnedFilFileName = "pinnedFilSnapshot.json"

    private(set) var pinnedFil: PinnedFilSnapshot?

    init() {
        self.pinnedFil = Self.loadPinnedFil()
    }

    @discardableResult
    func pin(_ note: Note) -> PinnedFilSnapshot {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)

        let snapshot = PinnedFilSnapshot(
            id: note.uuid,
            title: title.isEmpty ? (fallbackTitle.isEmpty ? "fil" : fallbackTitle) : title,
            previewText: Self.truncatedPreview(from: transcript),
            keyword: note.displayBadgeText,
            gradientStartHex: note.gradientStartHex,
            gradientEndHex: note.gradientEndHex
        )
        save(snapshot)
        return snapshot
    }

    /// The widget renders only a few lines, so only a short excerpt is ever needed. Truncating
    /// here keeps the full note transcript out of the shared App Group container, which other
    /// on-device processes with the group entitlement could otherwise read.
    private static func truncatedPreview(from transcript: String, limit: Int = 200) -> String {
        guard transcript.count > limit else { return transcript }
        return String(transcript.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    func unpin() {
        pinnedFil = nil
        if let url = Self.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        reloadWidget()
    }

    func isPinned(_ note: Note) -> Bool {
        pinnedFil?.id == note.uuid
    }

    private func save(_ snapshot: PinnedFilSnapshot) {
        pinnedFil = snapshot

        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        reloadWidget()
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(pinnedFilFileName)
    }

    private static func loadPinnedFil() -> PinnedFilSnapshot? {
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(PinnedFilSnapshot.self, from: data)
        }

        // One-time migration from the previous UserDefaults-backed storage.
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "pinnedFilSnapshot"),
              let snapshot = try? JSONDecoder().decode(PinnedFilSnapshot.self, from: data) else {
            return nil
        }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
        }
        return snapshot
    }
}
