import Foundation
import SwiftData

struct ThreadedFilBacklink: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var parentNoteID: String
    var parentKeyword: String

    init(parentNoteID: UUID, parentKeyword: String) {
        self.parentNoteID = parentNoteID.uuidString
        self.parentKeyword = parentKeyword
    }
}

@Model
final class Note {
    @Attribute(.unique) var uuid: UUID = UUID()
    var title: String
    var transcript: String
    var audioFilePath: String
    var timestamp: Date
    var duration: TimeInterval
    var todos: [String]
    var completedTodos: [Bool]
    /// Stable identity per to-do (parallel to `todos`) for correct list animations. Kept in sync by
    /// `addTodo` / `removeTodo` / `normalizeCompletedTodos`; generated for legacy notes on demand.
    var todoIDs: [UUID] = []
    var calibrationNotes: [String]
    var keyword: String = ""
    var gradientStartHex: String = "#408CD9"
    var gradientEndHex: String = "#6659CC"
    var originalTitle: String?
    var originalTranscript: String?
    var threadedBacklinks: [ThreadedFilBacklink]
    /// The folder this fil is filed into; nil = unfiled (the inbox). One folder per fil.
    var folder: Folder?
    /// Manual position within its folder's type section (drag-to-reorder). Ties break by timestamp,
    /// so un-reordered folders keep the newest-first default. Scoped per folder (one folder per fil).
    var sortIndex: Int = 0
    var sourceURLString: String?
    var sourceTitle: String?
    /// A link page's og:description / meta description, fetched in the background — shown in the link
    /// sheet below the title. Optional (additive): older fils and pages without one leave it nil.
    var sourceDescription: String? = nil
    @Attribute(.externalStorage) var sourceFaviconData: Data?
    @Relationship(deleteRule: .cascade, inverse: \KeywordAttachment.note)
    var attachments: [KeywordAttachment] = []
    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note)
    var imageFilImages: [NoteImage] = []
    @Attribute(.externalStorage) var imageData: Data?

    init(
        title: String = "",
        transcript: String = "",
        audioFilePath: String = "",
        timestamp: Date = .now,
        duration: TimeInterval = 0,
        todos: [String] = [],
        completedTodos: [Bool] = [],
        calibrationNotes: [String] = [],
        keyword: String = "",
        gradientStartHex: String = "",
        gradientEndHex: String = "",
        originalTitle: String? = nil,
        originalTranscript: String? = nil,
        threadedBacklinks: [ThreadedFilBacklink] = [],
        sourceURLString: String? = nil,
        sourceTitle: String? = nil,
        sourceFaviconData: Data? = nil,
        imageData: Data? = nil
    ) {
        self.title = title
        self.transcript = transcript
        self.audioFilePath = audioFilePath
        self.timestamp = timestamp
        self.duration = duration
        self.todos = todos
        self.completedTodos = completedTodos.isEmpty ? Array(repeating: false, count: todos.count) : completedTodos
        self.todoIDs = todos.map { _ in UUID() }
        self.calibrationNotes = calibrationNotes
        self.keyword = keyword
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.originalTitle = originalTitle
        self.originalTranscript = originalTranscript
        self.threadedBacklinks = threadedBacklinks
        self.sourceURLString = sourceURLString
        self.sourceTitle = sourceTitle
        self.sourceFaviconData = sourceFaviconData
        self.imageData = imageData
    }

    /// Appends a manually-created to-do, keeping `completedTodos` in sync. Ignores blank
    /// text and exact (case-insensitive) duplicates so the same action isn't added twice.
    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        normalizeCompletedTodos()
        guard !todos.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        todos.append(trimmed)
        completedTodos.append(false)
        todoIDs.append(UUID())
    }

    /// Removes the to-do at `index`, keeping `completedTodos` in sync.
    func removeTodo(at index: Int) {
        normalizeCompletedTodos()
        guard todos.indices.contains(index) else { return }
        todos.remove(at: index)
        if completedTodos.indices.contains(index) {
            completedTodos.remove(at: index)
        }
        if todoIDs.indices.contains(index) {
            todoIDs.remove(at: index)
        }
    }

    /// Keeps `completedTodos` and `todoIDs` the same length as `todos` (padding / truncating) so the
    /// parallel arrays never drift. Missing `todoIDs` are generated here (e.g. for notes created
    /// before to-do IDs existed).
    func normalizeCompletedTodos() {
        if completedTodos.count < todos.count {
            completedTodos.append(contentsOf: Array(repeating: false, count: todos.count - completedTodos.count))
        } else if completedTodos.count > todos.count {
            completedTodos = Array(completedTodos.prefix(todos.count))
        }

        if todoIDs.count < todos.count {
            todoIDs.append(contentsOf: (0..<(todos.count - todoIDs.count)).map { _ in UUID() })
        } else if todoIDs.count > todos.count {
            todoIDs = Array(todoIDs.prefix(todos.count))
        }
    }

    var isImageFil: Bool {
        !imageFilImages.isEmpty
    }

    var sortedImageFilImages: [NoteImage] {
        imageFilImages.sorted { $0.order < $1.order }
    }

    var isLinkFil: Bool {
        sourceURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var sourceURL: URL? {
        guard let sourceURLString else { return nil }
        return URL(string: sourceURLString)
    }

    var sourceDomain: String? {
        guard let host = sourceURL?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The title for text & voice fils: the first non-empty line of the transcript (Apple-Notes style —
    /// the note is its own title, so nothing to author or regenerate). Photos reuse it over their caption.
    var titleLine: String {
        for raw in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return line }
        }
        return ""
    }

    /// The body shown beneath the title line: the transcript with its first non-empty line removed, so
    /// the first line isn't repeated under itself.
    var bodyAfterTitle: String {
        let lines = transcript.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return "" }
        return lines[(first + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayBadgeText: String {
        if isLinkFil {
            return sourceDomainBadge ?? "link"
        }
        // Notes, voice, and photos all title from the first line of their text (transcript / caption).
        let line = titleLine
        if !line.isEmpty { return line }
        if isImageFil { return "photo" }
        // Empty transcript fallback (legacy fils / edge cases).
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? (keyword.isEmpty ? "fil" : keyword) : trimmedTitle
    }

    private var sourceDomainBadge: String? {
        guard let sourceDomain else { return nil }
        let commonSuffixes: Set<String> = ["com", "org", "net", "io", "co", "edu", "gov", "app", "dev", "ai"]
        let components = sourceDomain
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !commonSuffixes.contains($0) }

        return components.last?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

extension Note {
    /// The fil as a gradient blob for Lock Screen surfaces (gradient + shape seed only, no text).
    var activityBlob: FilActivityBlob {
        FilActivityBlob(startHex: gradientStartHex, endHex: gradientEndHex, seed: blobShapeSeed)
    }

    /// A link fil's display title: its fetched page title, else the user's title, else the domain.
    /// Shared by the reader (ArticleView) and the Full Screen player.
    var linkDisplayTitle: String {
        let source = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty { return source }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (sourceDomain ?? "Link") : t
    }

    /// Toggle a to-do's completion: normalize the parallel arrays, flip it at `index`, and persist.
    /// Returns false (no-op) when the index is out of range. Sound / haptic / animation stay at the
    /// call site since they differ per surface (some animate, some play a sound, some don't).
    @discardableResult
    func toggleCompletedTodo(at index: Int) -> Bool {
        normalizeCompletedTodos()
        guard completedTodos.indices.contains(index) else { return false }
        completedTodos[index].toggle()
        try? modelContext?.save()
        return true
    }
}

extension TimeInterval {
    /// `m:ss` — minutes and zero-padded seconds. Used for voice-fil durations and the player scrubber.
    var clockLabel: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
