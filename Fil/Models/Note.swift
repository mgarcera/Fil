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
    var articleBody: String
    var audioFilePath: String
    var timestamp: Date
    var duration: TimeInterval
    var todos: [String]
    var completedTodos: [Bool]
    var calibrationNotes: [String]
    var keyword: String = ""
    var gradientStartHex: String = "#408CD9"
    var gradientEndHex: String = "#6659CC"
    var originalTitle: String?
    var originalTranscript: String?
    var threadedBacklinks: [ThreadedFilBacklink]
    var sourceURLString: String?
    var sourceTitle: String?
    @Attribute(.externalStorage) var sourceFaviconData: Data?
    @Relationship(deleteRule: .cascade, inverse: \KeywordAttachment.note)
    var attachments: [KeywordAttachment] = []
    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note)
    var imageFilImages: [NoteImage] = []
    @Attribute(.externalStorage) var imageData: Data?

    init(
        title: String = "",
        transcript: String = "",
        articleBody: String = "",
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
        self.articleBody = articleBody
        self.audioFilePath = audioFilePath
        self.timestamp = timestamp
        self.duration = duration
        self.todos = todos
        self.completedTodos = completedTodos.isEmpty ? Array(repeating: false, count: todos.count) : completedTodos
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

    var displayBadgeText: String {
        if isLinkFil {
            return sourceDomainBadge ?? "link"
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? keyword : trimmedTitle
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
