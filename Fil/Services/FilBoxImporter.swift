import Foundation
import SwiftData

/// Reads a `.filbox` back into the live library.
///
/// **Merge, never replace.** A fil already present by `uuid` is left exactly as it is; only what is
/// missing gets inserted. That makes importing an old backup into a working library safe, makes
/// importing the same file twice a no-op, and means the user never has to reason about which copy
/// wins before tapping the button.
///
/// **IDs travel verbatim.** `uuid` on a fil, `id` on a folder and on each image. The naive importer
/// mints fresh IDs to dodge conflicts, and every thought comes back wearing a different face, because
/// the blob shape is seeded from `uuid`. Preserving the ID is both the fidelity requirement and the
/// dedupe key: one rule, two jobs.
@MainActor
enum FilBoxImporter {

    static func run(url: URL, context: ModelContext) throws -> FilBoxImportResult {
        // Files arriving from the share sheet or Files live outside the sandbox until asked for.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let archive = try FilBoxArchive(url: url)

        guard let manifest = try archive.decode(FilBoxManifest.self, at: FilBoxFormat.manifestName) else {
            throw FilBoxError.manifestMissing
        }
        // Refuse a future format outright rather than importing the half we happen to understand. A
        // partial import of an unknown schema is worse than no import: it looks like it worked.
        guard manifest.schemaVersion <= FilBoxFormat.schemaVersion else {
            throw FilBoxError.futureSchema(found: manifest.schemaVersion, supported: FilBoxFormat.schemaVersion)
        }

        let folders = (try archive.decode([FilBoxFolder].self, at: FilBoxFormat.foldersName)) ?? []
        let fils = (try archive.decode([FilBoxNote].self, at: FilBoxFormat.filsName)) ?? []

        var result = FilBoxImportResult()
        let folderIndex = try mergeFolders(folders, context: context, result: &result)
        try mergeFils(fils, archive: archive, folders: folderIndex, context: context, result: &result)

        try context.save()
        return result
    }

    // MARK: - Folders

    private static func mergeFolders(
        _ incoming: [FilBoxFolder],
        context: ModelContext,
        result: inout FilBoxImportResult
    ) throws -> [UUID: Folder] {
        var index: [UUID: Folder] = [:]
        for existing in try context.fetch(FetchDescriptor<Folder>()) {
            index[existing.id] = existing
        }

        for dto in incoming {
            if index[dto.id] != nil {
                result.reusedFolders += 1
                continue
            }
            let folder = Folder(
                id: dto.id,
                name: dto.name,
                summary: dto.summary,
                gradientStartHex: dto.gradientStartHex,
                gradientEndHex: dto.gradientEndHex,
                createdAt: dto.createdAt,
                sortIndex: dto.sortIndex
            )
            // Not on the initialiser; a folder's caption and its signature are derived state that the
            // summariser writes later, but they are worth carrying so an import doesn't re-summarise.
            folder.summarySignature = dto.summarySignature
            folder.summaryParts = dto.summaryParts

            context.insert(folder)
            index[dto.id] = folder
            result.addedFolders += 1
        }
        return index
    }

    // MARK: - Fils

    private static func mergeFils(
        _ incoming: [FilBoxNote],
        archive: FilBoxArchive,
        folders: [UUID: Folder],
        context: ModelContext,
        result: inout FilBoxImportResult
    ) throws {
        var existing = Set(try context.fetch(FetchDescriptor<Note>()).map(\.uuid))

        for dto in incoming {
            guard !existing.contains(dto.uuid) else {
                result.skippedFils += 1
                continue
            }

            let note = Note(
                title: dto.title,
                transcript: dto.transcript,
                audioFilePath: "",
                timestamp: dto.timestamp,
                duration: dto.duration,
                todos: dto.todos,
                completedTodos: dto.completedTodos,
                calibrationNotes: dto.calibrationNotes,
                keyword: dto.keyword,
                gradientStartHex: dto.gradientStartHex,
                gradientEndHex: dto.gradientEndHex,
                originalTitle: dto.originalTitle,
                originalTranscript: dto.originalTranscript,
                threadedBacklinks: dto.backlinks.map(restoredBacklink),
                sourceURLString: dto.sourceURLString,
                sourceTitle: dto.sourceTitle,
                sourceFaviconData: dto.faviconMediaFile.flatMap { archive.data(for: mediaPath($0)) },
                imageData: dto.imageMediaFile.flatMap { archive.data(for: mediaPath($0)) }
            )

            // The initialiser mints fresh values for these, which is right for a new fil and wrong for
            // a restored one. uuid in particular: a new uuid is a new face.
            note.uuid = dto.uuid
            note.sortIndex = dto.sortIndex
            note.sourceDescription = dto.sourceDescription
            if dto.todoIDs.count == dto.todos.count { note.todoIDs = dto.todoIDs }

            if let audioFile = dto.audioMediaFile {
                if let written = writeMedia(named: audioFile, from: archive) {
                    note.audioFilePath = written
                } else {
                    result.missingMedia.append(audioFile)
                }
            }

            if let folderID = dto.folderID { note.folder = folders[folderID] }

            context.insert(note)
            existing.insert(dto.uuid)
            result.addedFils += 1

            attachImages(dto.images, to: note, archive: archive, context: context, result: &result)
            attachKeywords(dto.attachments, to: note, archive: archive, context: context, result: &result)
        }
    }

    /// `ThreadedFilBacklink`'s initialiser takes a `UUID` and stringifies it, and mints a fresh `id`.
    /// Both are right when a backlink is being made and wrong when one is being restored, so the two
    /// identity fields are written back afterwards. `parentNoteID` is assigned as the stored string
    /// rather than round-tripped through `UUID`, so a legacy non-UUID value survives unchanged.
    private static func restoredBacklink(_ dto: FilBoxBacklink) -> ThreadedFilBacklink {
        var link = ThreadedFilBacklink(parentNoteID: UUID(), parentKeyword: dto.parentKeyword)
        link.id = dto.id
        link.parentNoteID = dto.parentNoteID
        return link
    }

    private static func attachImages(
        _ images: [FilBoxImage],
        to note: Note,
        archive: FilBoxArchive,
        context: ModelContext,
        result: inout FilBoxImportResult
    ) {
        for dto in images.sorted(by: { $0.order < $1.order }) {
            guard let bytes = archive.data(for: mediaPath(dto.mediaFile)) else {
                result.missingMedia.append(dto.mediaFile)
                continue
            }
            let image = NoteImage(data: bytes, order: dto.order, note: note)
            image.id = dto.id
            context.insert(image)
        }
    }

    /// Entries are grouped back under their keyword, since `KeywordAttachment` is one row per keyword
    /// holding a Codable array rather than one row per entry.
    private static func attachKeywords(
        _ attachments: [FilBoxAttachment],
        to note: Note,
        archive: FilBoxArchive,
        context: ModelContext,
        result: inout FilBoxImportResult
    ) {
        let grouped = Dictionary(grouping: attachments, by: \.keyword)
        for (keyword, dtos) in grouped {
            var entries: [AttachmentEntry] = []
            for dto in dtos {
                // An unfamiliar kind means an archive from a newer Fil that slipped the schema check.
                // Skip the entry, keep the fil: a silent partial beats a failed import.
                guard let kind = AttachmentEntry.Kind(rawValue: dto.kind) else { continue }

                var entry = AttachmentEntry(kind: kind)
                entry.id = dto.id
                entry.text = dto.text
                entry.linkedNoteID = dto.linkedNoteID
                entry.noteTitle = dto.noteTitle
                entry.linkCaption = dto.linkCaption
                entry.pdfName = dto.pdfName
                entry.fileName = dto.fileName
                entry.imageData = dto.imageMediaFile.flatMap { archive.data(for: mediaPath($0)) }
                entry.pdfData = dto.pdfMediaFile.flatMap { archive.data(for: mediaPath($0)) }
                entry.faviconData = dto.faviconMediaFile.flatMap { archive.data(for: mediaPath($0)) }

                // Recordings, videos and generic files keep their bytes on disk and a filename in
                // `text`, so the payload has to land in the documents directory and `text` be rewritten
                // to wherever it landed.
                if let payload = dto.payloadMediaFile {
                    if let written = writeMedia(named: payload, from: archive) {
                        entry.text = written
                    } else {
                        result.missingMedia.append(payload)
                    }
                }
                entries.append(entry)
            }
            guard !entries.isEmpty else { continue }

            let attachment = KeywordAttachment(keyword: keyword, note: note)
            attachment.entries = entries
            context.insert(attachment)
        }
    }

    // MARK: - Media

    private static func mediaPath(_ name: String) -> String {
        "\(FilBoxFormat.mediaDirectory)/\(name)"
    }

    /// Writes one media file into the documents directory and returns the bare filename to store.
    /// A documents path is not stable across installs, which is why the archive carries names and the
    /// importer re-points every reference at the new location.
    private static func writeMedia(named name: String, from archive: FilBoxArchive) -> String? {
        guard let bytes = archive.data(for: mediaPath(name)) else { return nil }

        let directory = AudioPlayerViewModel.recordingsDirectory
        var destination = directory.appendingPathComponent(name)

        // Two backups can carry different files under the same name. Suffix rather than overwrite:
        // clobbering a file the live library still points at would break a fil that was already here.
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            let ext = destination.pathExtension
            let stem = destination.deletingPathExtension().lastPathComponent
            let unique = ext.isEmpty ? "\(stem)-\(UUID().uuidString)" : "\(stem)-\(UUID().uuidString).\(ext)"
            destination = directory.appendingPathComponent(unique)
        }

        do {
            try bytes.write(to: destination, options: .atomic)
            return destination.lastPathComponent
        } catch {
            return nil
        }
    }
}
