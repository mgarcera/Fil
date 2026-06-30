import Foundation

struct TemporaryFilDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var previewText: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

final class TemporaryFilDraftStore {
    static let shared = TemporaryFilDraftStore()

    private let defaults: UserDefaults
    private let draftKey = "temporaryFilDraft"

    private(set) var draft: TemporaryFilDraft?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.draft = Self.loadDraft(from: defaults, key: draftKey)
    }

    func hold(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if var existingDraft = draft {
            existingDraft.text = [existingDraft.text, trimmed]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            existingDraft.updatedAt = .now
            save(existingDraft)
        } else {
            save(TemporaryFilDraft(text: trimmed))
        }
    }

    func replace(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }

        save(TemporaryFilDraft(id: draft?.id ?? UUID(), text: trimmed, createdAt: draft?.createdAt ?? .now))
    }

    func clear() {
        draft = nil
        defaults.removeObject(forKey: draftKey)
    }

    private func save(_ draft: TemporaryFilDraft) {
        self.draft = draft

        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: draftKey)
    }

    private static func loadDraft(from defaults: UserDefaults, key: String) -> TemporaryFilDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TemporaryFilDraft.self, from: data)
    }
}
