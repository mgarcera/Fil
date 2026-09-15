import Foundation

/// The on-disk shape of a `.filbox` backup, shared by the exporter and the importer.
///
/// Two layers with two jobs. `fils.json` + `media/` is **insurance**: exact fidelity, re-importable,
/// faces intact. `readable/` is **ownership**: plain Markdown anyone can open in ten years without
/// Fil existing. The exporter walks every record once and writes both.
///
/// **The rule the whole format rests on:** a fil's face is a pure function of its `uuid` plus its two
/// gradient hexes (`blobShapeSeed` is an FNV-1a hash of `uuid.uuidString`). An importer that mints
/// fresh IDs to dodge conflicts brings every thought back wearing a different face, which breaks the
/// one promise the product makes. So `uuid` travels verbatim, and that same rule is what makes
/// merge-by-id safe.
nonisolated enum FilBoxFormat {
    /// Bumped only when a change would make an older Fil misread a newer archive. Additive fields
    /// (new optionals) do not bump it: they decode as nil in an older build, which is exactly the
    /// "newer Fil opens an older .filbox" case the spec calls supported.
    static let schemaVersion = 1

    static let fileExtension = "filbox"
    static let manifestName = "manifest.json"
    static let filsName = "fils.json"
    static let foldersName = "folders.json"
    static let mediaDirectory = "media"
    static let readableDirectory = "readable"

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Manifest

nonisolated struct FilBoxManifest: Codable {
    var schemaVersion: Int
    var appVersion: String
    var exportedAt: Date
    var filCount: Int
    var folderCount: Int
    var mediaBytes: Int
    /// Files a record pointed at that were not on disk at export time. Recorded rather than fatal:
    /// a fil whose recording went missing is still worth carrying.
    var missingMedia: [String] = []
}

// MARK: - Records

/// A fil, flattened. Relationships travel as IDs, never as nested objects, so the importer can
/// insert in any order and resolve afterwards.
nonisolated struct FilBoxNote: Codable {
    var uuid: UUID
    var title: String
    var transcript: String
    var timestamp: Date
    var duration: TimeInterval
    var keyword: String
    var gradientStartHex: String
    var gradientEndHex: String
    var sortIndex: Int

    var todos: [String]
    var completedTodos: [Bool]
    var todoIDs: [UUID]
    var calibrationNotes: [String]

    var originalTitle: String?
    var originalTranscript: String?
    var sourceURLString: String?
    var sourceTitle: String?
    var sourceDescription: String?

    var folderID: UUID?
    var backlinks: [FilBoxBacklink]
    var attachments: [FilBoxAttachment]
    var images: [FilBoxImage]

    /// Filename inside `media/`, not a device path. Documents-directory paths are not stable across
    /// installs, so every media reference is rewritten on both sides of the trip.
    var audioMediaFile: String?
    var imageMediaFile: String?
    var faviconMediaFile: String?
}

nonisolated struct FilBoxBacklink: Codable {
    var id: UUID
    var parentNoteID: String
    var parentKeyword: String
}

nonisolated struct FilBoxFolder: Codable {
    var id: UUID
    var name: String
    var summary: String
    var gradientStartHex: String
    var gradientEndHex: String
    var createdAt: Date
    var sortIndex: Int
    var summarySignature: String
    var summaryParts: [String]
}

nonisolated struct FilBoxImage: Codable {
    var id: UUID
    var order: Int
    var mediaFile: String
}

/// One entry under a keyword. `kind` mirrors `AttachmentEntry.Kind` as a raw string so an unknown
/// future kind can be skipped rather than failing the whole import.
nonisolated struct FilBoxAttachment: Codable {
    var id: UUID
    var keyword: String
    var kind: String
    var text: String?
    var linkedNoteID: String?
    var noteTitle: String?
    var linkCaption: String?
    var pdfName: String?
    var fileName: String?

    var imageMediaFile: String?
    var pdfMediaFile: String?
    var faviconMediaFile: String?
    /// For `.recording`, `.video` and `.file`, whose bytes live on disk rather than inline.
    var payloadMediaFile: String?
}

// MARK: - Result

/// What an import actually did, phrased for the sentence shown to the user:
/// "added 47 fils and 3 folders. 210 were already here."
nonisolated struct FilBoxImportResult {
    var addedFils = 0
    var skippedFils = 0
    var addedFolders = 0
    var reusedFolders = 0
    var missingMedia: [String] = []

    var summarySentence: String {
        var parts: [String] = []
        switch (addedFils, addedFolders) {
        case (0, 0): parts.append("nothing new to add")
        case (let f, 0): parts.append("added \(f) \(f == 1 ? "fil" : "fils")")
        case (0, let d): parts.append("added \(d) \(d == 1 ? "folder" : "folders")")
        case (let f, let d):
            parts.append("added \(f) \(f == 1 ? "fil" : "fils") and \(d) \(d == 1 ? "folder" : "folders")")
        }
        if skippedFils > 0 { parts.append("\(skippedFils) were already here") }
        if !missingMedia.isEmpty { parts.append("\(missingMedia.count) attachments were missing from the backup") }
        return parts.joined(separator: ". ") + "."
    }
}

nonisolated enum FilBoxError: LocalizedError {
    case notAnArchive
    case manifestMissing
    case futureSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "That file isn't a Fil backup."
        case .manifestMissing:
            return "That backup is missing its manifest, so Fil can't read it."
        case .futureSchema(let found, let supported):
            return "That backup was made by a newer version of Fil (format \(found); this app reads \(supported)). Update Fil and try again."
        }
    }
}
