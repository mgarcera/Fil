import Foundation

/// One staged capture waiting in the basket. Not yet a fil — it becomes one only
/// when the user promotes it. Text-only for now; image drops carry their caption.
struct FilBasketItem: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    /// A short, single-line label for the island and triage list.
    var displayTitle: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "note" : String(trimmed.prefix(40))
    }
}

/// The out-of-app capture buffer. Captures made while Fil is suspended — the Action Button intent,
/// the Share Extension — land here (they have no SwiftData `modelContext`), and the app drains them
/// into real unfiled fils on the next launch (see `ContentView.drainCaptureBuffer`). Stored as JSON
/// in the shared App Group container so every process can reach it.
final class FilBasketStore {
    static let shared = FilBasketStore()

    static let appGroupIdentifier = "group.com.masongarcera.Fil"
    private static let fileName = "filBasket.json"

    private(set) var items: [FilBasketItem]

    init() {
        self.items = Self.load()
    }

    var count: Int { items.count }

    /// The most recent titles, newest first — the manifest the island renders.
    func recentTitles(limit: Int = 3) -> [String] {
        items.suffix(limit).reversed().map(\.displayTitle)
    }

    @discardableResult
    func add(text: String) -> FilBasketItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = FilBasketItem(text: trimmed)
        items.append(item)
        save()
        return item
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Returns everything staged and empties the buffer — the app calls this on launch to promote
    /// out-of-app captures into real unfiled fils.
    func drain() -> [FilBasketItem] {
        let drained = items
        guard !drained.isEmpty else { return [] }
        items.removeAll()
        save()
        return drained
    }

    private func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(items) else { return }
        // Protect at rest, but stay readable after first unlock so a background capture
        // (e.g. Action Button on the Lock Screen) can still write the basket.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    private static func load() -> [FilBasketItem] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([FilBasketItem].self, from: data)) ?? []
    }
}
