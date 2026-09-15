import Foundation
import SwiftData

/// Walks the whole library once and writes a `.filbox`.
///
/// Runs on its own actor with its own `ModelContext`, not on the main one. A library with a couple of
/// years of voice and photos in it is hundreds of MB of file copying, and the progress UI we promised
/// can only count if the thing it is counting isn't blocking the frame it draws in.
///
/// Two layers come out of the single walk. `fils.json` + `media/` is the re-importable copy;
/// `readable/` is plain Markdown for a person with no Fil installed. The second is nearly free once
/// every record is already in hand, which is the only reason it's worth writing.
@ModelActor
actor FilBoxExporter {

    struct Progress: Sendable {
        var completed: Int
        var total: Int
    }

    /// Writes the archive and returns its URL in a temp directory the caller is expected to hand
    /// straight to a share sheet.
    func export(onProgress: @Sendable (Progress) async -> Void) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbox-\(UUID().uuidString)", isDirectory: true)
        let mediaDirectory = staging.appendingPathComponent(FilBoxFormat.mediaDirectory, isDirectory: true)
        let readableDirectory = staging.appendingPathComponent(FilBoxFormat.readableDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readableDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let folders = try modelContext.fetch(FetchDescriptor<Folder>())
        let notes = try modelContext.fetch(
            FetchDescriptor<Note>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        )

        var writer = MediaWriter(directory: mediaDirectory)
        var readable = ReadableWriter(directory: readableDirectory)
        var exportedNotes: [FilBoxNote] = []
        exportedNotes.reserveCapacity(notes.count)

        await onProgress(Progress(completed: 0, total: notes.count))

        for (index, note) in notes.enumerated() {
            try Task.checkCancellation()
            exportedNotes.append(exportNote(note, media: &writer))
            readable.write(note)
            await onProgress(Progress(completed: index + 1, total: notes.count))
        }

        let exportedFolders = folders.map {
            FilBoxFolder(
                id: $0.id,
                name: $0.name,
                summary: $0.summary,
                gradientStartHex: $0.gradientStartHex,
                gradientEndHex: $0.gradientEndHex,
                createdAt: $0.createdAt,
                sortIndex: $0.sortIndex,
                summarySignature: $0.summarySignature,
                summaryParts: $0.summaryParts
            )
        }

        let manifest = FilBoxManifest(
            schemaVersion: FilBoxFormat.schemaVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            exportedAt: .now,
            filCount: exportedNotes.count,
            folderCount: exportedFolders.count,
            mediaBytes: writer.bytesWritten,
            missingMedia: writer.missing
        )

        try FilBoxFormat.encoder.encode(manifest)
            .write(to: staging.appendingPathComponent(FilBoxFormat.manifestName))
        try FilBoxFormat.encoder.encode(exportedNotes)
            .write(to: staging.appendingPathComponent(FilBoxFormat.filsName))
        try FilBoxFormat.encoder.encode(exportedFolders)
            .write(to: staging.appendingPathComponent(FilBoxFormat.foldersName))

        try Task.checkCancellation()
        return try zip(staging)
    }

    // MARK: - Records

    private func exportNote(_ note: Note, media: inout MediaWriter) -> FilBoxNote {
        FilBoxNote(
            uuid: note.uuid,
            title: note.title,
            transcript: note.transcript,
            timestamp: note.timestamp,
            duration: note.duration,
            keyword: note.keyword,
            gradientStartHex: note.gradientStartHex,
            gradientEndHex: note.gradientEndHex,
            sortIndex: note.sortIndex,
            todos: note.todos,
            completedTodos: note.completedTodos,
            todoIDs: note.todoIDs,
            calibrationNotes: note.calibrationNotes,
            originalTitle: note.originalTitle,
            originalTranscript: note.originalTranscript,
            sourceURLString: note.sourceURLString,
            sourceTitle: note.sourceTitle,
            sourceDescription: note.sourceDescription,
            folderID: note.folder?.id,
            backlinks: note.threadedBacklinks.map {
                FilBoxBacklink(id: $0.id, parentNoteID: $0.parentNoteID, parentKeyword: $0.parentKeyword)
            },
            attachments: note.attachments.flatMap { attachment in
                attachment.entries.map { exportEntry($0, keyword: attachment.keyword, media: &media) }
            },
            images: note.imageFilImages.sorted { $0.order < $1.order }.map { image in
                FilBoxImage(
                    id: image.id,
                    order: image.order,
                    mediaFile: media.writeBlob(image.data, named: image.id.uuidString)
                )
            },
            audioMediaFile: media.copyFromDocuments(note.audioFilePath),
            imageMediaFile: note.imageData.map { media.writeBlob($0, named: "\(note.uuid.uuidString)-image") },
            faviconMediaFile: note.sourceFaviconData.map {
                media.writeBlob($0, named: "\(note.uuid.uuidString)-favicon")
            }
        )
    }

    private func exportEntry(
        _ entry: AttachmentEntry,
        keyword: String,
        media: inout MediaWriter
    ) -> FilBoxAttachment {
        // Recordings, videos and generic files keep their bytes on disk with a documents-dir filename
        // in `text`; everything else carries its bytes inline. Both classes have to be walked or a
        // restored voice fil arrives silent.
        let payloadFile: String?
        switch entry.kind {
        case .recording, .video, .file:
            payloadFile = media.copyFromDocuments(entry.text)
        default:
            payloadFile = nil
        }

        return FilBoxAttachment(
            id: entry.id,
            keyword: keyword,
            kind: entry.kind.rawValue,
            text: entry.text,
            linkedNoteID: entry.linkedNoteID,
            noteTitle: entry.noteTitle,
            linkCaption: entry.linkCaption,
            pdfName: entry.pdfName,
            fileName: entry.fileName,
            imageMediaFile: entry.imageData.map { media.writeBlob($0, named: "\(entry.id.uuidString)-image") },
            pdfMediaFile: entry.pdfData.map { media.writeBlob($0, named: "\(entry.id.uuidString)-pdf") },
            faviconMediaFile: entry.faviconData.map {
                media.writeBlob($0, named: "\(entry.id.uuidString)-favicon")
            },
            payloadMediaFile: payloadFile
        )
    }

    // MARK: - Zip

    /// `NSFileCoordinator`'s `.forUploading` option zips a directory for us, which is the reason only
    /// the *reading* side needed hand-written code. The zip it hands back is valid only inside the
    /// accessor block, so it gets copied out before the block returns.
    private func zip(_ directory: URL) throws -> URL {
        let name = "fil-\(Self.stampFormatter.string(from: .now)).\(FilBoxFormat.fileExtension)"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: destination) }
            catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destination
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Media

/// Copies both storage classes into `media/` under names that are stable inside the archive, and
/// records anything a record pointed at that wasn't on disk.
nonisolated private struct MediaWriter {
    let directory: URL
    private(set) var bytesWritten = 0
    private(set) var missing: [String] = []
    private var seen: Set<String> = []

    init(directory: URL) { self.directory = directory }

    mutating func writeBlob(_ data: Data, named stem: String) -> String {
        let name = "\(stem).\(Self.fileExtension(for: data))"
        guard !seen.contains(name) else { return name }
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            seen.insert(name)
            bytesWritten += data.count
        } catch {
            missing.append(name)
        }
        return name
    }

    /// Returns the archive-relative name for a documents-directory file, or nil when the reference is
    /// empty or the file is gone. A fil whose recording went missing is still worth exporting.
    mutating func copyFromDocuments(_ storedPath: String?) -> String? {
        guard let storedPath, !storedPath.isEmpty else { return nil }
        guard let source = AudioPlayerViewModel.audioFileURL(for: storedPath) else {
            missing.append(storedPath)
            return nil
        }
        let name = source.lastPathComponent
        guard !seen.contains(name) else { return name }
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            seen.insert(name)
            bytesWritten += (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return name
        } catch {
            missing.append(name)
            return nil
        }
    }

    /// Sniffs the container so a restored photo keeps a sensible extension in the readable copy too.
    private static func fileExtension(for data: Data) -> String {
        guard data.count >= 12 else { return "bin" }
        let b = [UInt8](data.prefix(12))
        if b[0] == 0xFF, b[1] == 0xD8 { return "jpg" }
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
        if b[0] == 0x25, b[1] == 0x50, b[2] == 0x44, b[3] == 0x46 { return "pdf" }
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {
            let brand = String(decoding: data.subdata(in: 8..<12), as: UTF8.self)
            return brand.hasPrefix("heic") || brand.hasPrefix("mif1") ? "heic" : "mp4"
        }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
        return "bin"
    }
}

// MARK: - Readable layer

/// The plain-Markdown half: one file per fil, grouped by folder.
///
/// Filenames lead with the date and then the title, truncated. 32 of the author's own 112 fils have no
/// title at all, and one runs 215 characters, so a title alone can neither name every file nor fit in
/// one. The date carries the untitled ones and sorts the folder chronologically in any file browser,
/// which is what makes this layer readable rather than merely present.
nonisolated private struct ReadableWriter {
    let directory: URL
    private var used: Set<String> = []

    init(directory: URL) { self.directory = directory }

    mutating func write(_ note: Note) {
        let folderName = Self.sanitise(note.folder?.name ?? "unfiled", fallback: "unfiled")
        let folderURL = directory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let stamp = FilBoxExporter.stampFormatter.string(from: note.timestamp)
        let title = Self.sanitise(note.title, fallback: "")
        var stem = title.isEmpty ? stamp : "\(stamp) \(title)"
        if stem.count > 80 { stem = String(stem.prefix(80)).trimmingCharacters(in: .whitespaces) }

        var name = "\(folderName)/\(stem)"
        var attempt = 2
        while used.contains(name.lowercased()) {
            name = "\(folderName)/\(stem)-\(attempt)"
            attempt += 1
        }
        used.insert(name.lowercased())

        let fileURL = directory.appendingPathComponent("\(name).md", isDirectory: false)
        try? Self.markdown(for: note).data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private static func markdown(for note: Note) -> String {
        var lines: [String] = []
        lines.append("# \(note.title.isEmpty ? "Untitled" : note.title)")
        lines.append("")
        lines.append("*\(note.timestamp.formatted(date: .long, time: .shortened))*")
        if let folder = note.folder?.name { lines.append("*In \(folder)*") }
        lines.append("")
        if !note.transcript.isEmpty {
            lines.append(note.transcript)
            lines.append("")
        }
        if !note.todos.isEmpty {
            for (index, todo) in note.todos.enumerated() {
                let done = index < note.completedTodos.count && note.completedTodos[index]
                lines.append("- [\(done ? "x" : " ")] \(todo)")
            }
            lines.append("")
        }
        if let source = note.sourceURLString {
            lines.append("Source: \(source)")
            lines.append("")
        }
        for attachment in note.attachments where !attachment.entries.isEmpty {
            lines.append("## \(attachment.keyword)")
            for entry in attachment.entries {
                lines.append("- \(entry.kind.rawValue): \(entry.linkCaption ?? entry.noteTitle ?? entry.fileName ?? entry.pdfName ?? entry.text ?? "")")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Strips what a file browser can't take, then collapses the whitespace a title picked up from
    /// being someone's first line rather than a filename.
    private static func sanitise(_ raw: String, fallback: String) -> String {
        let stripped = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: " ")
        let collapsed = stripped.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
