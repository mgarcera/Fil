import Foundation
import WidgetKit

/// The App Group snapshot of the pinned folder — the shape both the Live Activity and the
/// home-screen widget render. Kept small (name + count + a short peek of fil titles) so no fil
/// body ever leaves the app into the shared container.
struct PinnedFolderSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var count: Int
    var peek: [String]
    var gradientStartHex: String
    var gradientEndHex: String
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        count: Int,
        peek: [String],
        gradientStartHex: String = "#408CD9",
        gradientEndHex: String = "#6659CC",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.peek = peek
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.updatedAt = updatedAt
    }
}

/// Persists which folder is pinned to the Lock Screen / home-screen widget. Like `PinnedFilStore`
/// before it, the snapshot is a file (not UserDefaults) in the shared App Group container so a warm
/// widget process always reads the current pin rather than a cached stale one.
final class PinnedFolderStore {
    static let shared = PinnedFolderStore()

    static let appGroupIdentifier = "group.com.masongarcera.Fil"
    private static let fileName = "pinnedFolderSnapshot.json"

    private(set) var pinnedFolder: PinnedFolderSnapshot?

    init() {
        self.pinnedFolder = Self.load()
    }

    var pinnedFolderID: UUID? { pinnedFolder?.id }

    func isPinned(_ folderID: UUID) -> Bool { pinnedFolder?.id == folderID }

    /// Builds a fresh snapshot from the folder's current contents and persists it. Callers pass the
    /// peek titles (they own the `prefersLowercase` + newest-first ordering).
    @discardableResult
    func pin(id: UUID, name: String, count: Int, peek: [String], gradientStartHex: String, gradientEndHex: String) -> PinnedFolderSnapshot {
        let snapshot = PinnedFolderSnapshot(
            id: id,
            name: name,
            count: count,
            peek: peek,
            gradientStartHex: gradientStartHex,
            gradientEndHex: gradientEndHex
        )
        save(snapshot)
        return snapshot
    }

    func unpin() {
        pinnedFolder = nil
        if let url = Self.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        reloadWidget()
    }

    private func save(_ snapshot: PinnedFolderSnapshot) {
        pinnedFolder = snapshot
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
            .appendingPathComponent(fileName)
    }

    private static func load() -> PinnedFolderSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PinnedFolderSnapshot.self, from: data)
    }
}
