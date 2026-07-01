import Foundation

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

    private let defaults: UserDefaults
    private let pinnedFilKey = "pinnedFilSnapshot"

    private(set) var pinnedFil: PinnedFilSnapshot?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pinnedFil = Self.loadPinnedFil(from: defaults, key: pinnedFilKey)
    }

    @discardableResult
    func pin(_ note: Note) -> PinnedFilSnapshot {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)

        let snapshot = PinnedFilSnapshot(
            id: note.uuid,
            title: title.isEmpty ? (fallbackTitle.isEmpty ? "fil" : fallbackTitle) : title,
            previewText: transcript,
            keyword: note.displayBadgeText,
            gradientStartHex: note.gradientStartHex,
            gradientEndHex: note.gradientEndHex
        )
        save(snapshot)
        return snapshot
    }

    func unpin() {
        pinnedFil = nil
        defaults.removeObject(forKey: pinnedFilKey)
    }

    func isPinned(_ note: Note) -> Bool {
        pinnedFil?.id == note.uuid
    }

    private func save(_ snapshot: PinnedFilSnapshot) {
        pinnedFil = snapshot

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: pinnedFilKey)
    }

    private static func loadPinnedFil(from defaults: UserDefaults, key: String) -> PinnedFilSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PinnedFilSnapshot.self, from: data)
    }
}
