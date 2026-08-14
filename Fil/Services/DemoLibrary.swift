import Foundation
import OSLog
import SwiftData

/// Deterministic demo content for screenshots.
///
/// Launch the app with `-FilScreenshotMode` and it wipes the store and reseeds it from
/// `DemoLibrary.json`, so every capture run produces the same library. Without the argument this
/// is completely inert — nothing here runs in normal use, and App Review can't pass launch
/// arguments.
///
/// Why the UUIDs in the JSON are pinned: a fil's blob shape is an FNV-1a hash of its
/// `uuid.uuidString` (see `NoteCardView.blobShapeSeed`), so a fresh UUID means a different shape.
/// Pinning them keeps screenshots stable across runs and across machines.
///
/// Voice and photo fils are seeded from files bundled in `Fil/Resources`: `audio` is copied into
/// the documents dir where the player resolves it, and `images` load straight into `NoteImage`s.
@MainActor
enum DemoLibrary {
    static let launchArgument = "-FilScreenshotMode"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// What a capture run should be showing when the shot is taken.
    ///
    /// Most screens are reachable through the production deep link. The player and the
    /// screensaver are not — and widening `HomeDeepLink` with routes that exist only for
    /// screenshots would put screenshot concerns into a production enum the Lock Screen
    /// widget and Control Center also use. So those two get their own cases here, and
    /// `ContentView` drives the state it already owns for them.
    enum Stage: Equatable {
        case deepLink(HomeDeepLink)
        /// Open the folder, then the fil inside it. Two ids because the full-screen player has no
        /// route of its own: it is reached by tapping a fil *within* a folder interior, which is
        /// also the state this frame is meant to show. Playback starts on its own, since a paused
        /// player has nothing moving in it and this frame is recorded rather than stilled.
        case player(folder: UUID, note: UUID)
        /// Raise a screensaver immediately, by mode raw value.
        case canvas(String)
        /// Move the Lock Screen pin from folder to folder on a timer, so a capture shows the act
        /// of pinning rather than a pinned state. Possible because pinning is stored state, not a
        /// gesture — nothing here simulates a tap.
        case pinning
    }

    /// Which screen a capture run should open on, e.g. `-FilScreenshotScreen folder:Yosemite`.
    ///
    /// Routed in-process rather than through `simctl openurl`, because opening a `fil://` URL from
    /// outside the app makes iOS show an "Open in Fil?" confirmation — which can't be dismissed
    /// unattended and lands in the middle of the screenshot.
    ///
    /// Values: `bin`, `compose`, `voice`, `folder:<name>`, `player`, `canvas`, `canvas:<mode>`.
    /// Anything else (or absent) stays home.
    static func initialStage(folderIDsByName: [String: UUID]) -> Stage? {
        guard isEnabled else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = args.firstIndex(of: "-FilScreenshotScreen"),
            args.indices.contains(flagIndex + 1)
        else { return nil }

        let value = args[flagIndex + 1]
        switch value {
        case "bin": return .deepLink(.bin)
        case "compose": return .deepLink(.compose)
        case "voice": return .deepLink(.voice)
        case "pinning": return .pinning
        case "player":
            guard
                let spec = seededVoiceFil(),
                let folderName = spec.folder,
                let folderID = folderIDsByName[folderName]
            else {
                FilLog.data.error("DemoLibrary: 'player' needs a seeded fil that has audio and sits in a folder")
                return nil
            }
            return .player(folder: folderID, note: spec.uuid)
        default:
            if value == "canvas" || value.hasPrefix("canvas:") {
                // Bare `canvas` takes the mode from the seed file so the screen is content,
                // not a script argument. `canvas:<mode>` overrides for a one-off.
                let override = value.hasPrefix("canvas:") ? String(value.dropFirst("canvas:".count)) : nil
                return .canvas(override ?? decodedPayload()?.state?.screensaverMode ?? "liquid")
            }
            guard value.hasPrefix("folder:") else { return nil }
            let name = String(value.dropFirst("folder:".count))
            guard let id = folderIDsByName[name] else {
                FilLog.data.error("DemoLibrary: no seeded folder named '\(name, privacy: .public)'")
                return nil
            }
            return .deepLink(.folder(id))
        }
    }

    /// Folder name → id, from the seed file. Lets the screen argument name a folder rather than
    /// carry a UUID around.
    static func seededFolderIDsByName() -> [String: UUID] {
        guard let payload = decodedPayload() else { return [:] }
        return Dictionary(uniqueKeysWithValues: payload.folders.map { ($0.name, $0.id) })
    }

    /// The first fil in the seed file that has audio. `player` opens this one, so which fil the
    /// player screen shows is a property of the content rather than of the capture script.
    private static func seededVoiceFil() -> FilSpec? {
        decodedPayload()?.fils.first(where: { $0.audio != nil })
    }

    /// The fil a `player` capture should open, read by the folder interior that holds it.
    /// Nil in every other case, including normal use.
    static var screenshotPlayerNoteID: UUID? {
        guard case .player(_, let noteID)? = initialStage(folderIDsByName: seededFolderIDsByName())
        else { return nil }
        return noteID
    }

    /// Whether this run is the pinning capture, read by the folders view that owns `togglePin`.
    static var isPinningCapture: Bool {
        if case .pinning? = initialStage(folderIDsByName: seededFolderIDsByName()) { return true }
        return false
    }

    /// How long each folder holds the pin during a pinning capture.
    static let pinningDwell: Duration = .milliseconds(1600)

    private static func decodedPayload() -> Payload? {
        guard
            let url = Bundle.main.url(forResource: "DemoLibrary", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Wipes the store and reseeds it from the bundled JSON. No-op unless the launch argument is set.
    static func seedIfRequested(into context: ModelContext) {
        guard isEnabled else { return }

        guard
            let url = Bundle.main.url(forResource: "DemoLibrary", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            FilLog.data.error("DemoLibrary: DemoLibrary.json missing from the bundle")
            return
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            FilLog.data.error("DemoLibrary: could not decode DemoLibrary.json: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Start from empty so a rerun can't stack duplicates on top of the last run.
        try? context.delete(model: Note.self)
        try? context.delete(model: Folder.self)

        var foldersByName: [String: Folder] = [:]
        var notesByFolderName: [String: [Note]] = [:]
        for spec in payload.folders {
            let folder = Folder(
                id: spec.id,
                name: spec.name,
                summary: spec.summary ?? "",
                gradientStartHex: spec.gradientStartHex,
                gradientEndHex: spec.gradientEndHex,
                createdAt: .now,
                sortIndex: spec.sortIndex ?? 0
            )
            folder.summaryParts = spec.summaryParts ?? []
            context.insert(folder)
            foldersByName[spec.name] = folder
        }

        for spec in payload.fils {
            let note = Note(
                title: spec.title ?? "",
                transcript: spec.transcript,
                timestamp: Date.now.addingTimeInterval(-spec.daysAgo * 86_400),
                todos: spec.todos ?? [],
                completedTodos: spec.completedTodos ?? [],
                gradientStartHex: spec.gradientStartHex,
                gradientEndHex: spec.gradientEndHex,
                sourceURLString: spec.sourceURLString,
                sourceTitle: spec.sourceTitle
            )
            // Pinned so the blob shape is stable — see the note above.
            note.uuid = spec.uuid
            note.sortIndex = spec.sortIndex ?? 0
            attachAudio(spec, to: note)
            attachImages(spec, to: note)
            if let name = spec.folder {
                note.folder = foldersByName[name]
                notesByFolderName[name, default: []].append(note)
            }
            context.insert(note)
        }

        // Keep the first-run welcome reveal out of the shots: it fires on the user's first fil,
        // and a seeded library shouldn't trigger it.
        UserDefaults.standard.set(true, forKey: "didSeedWelcomeFil")
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "firstUserFilAt")

        applyState(payload.state, foldersByName: foldersByName, notesByFolderName: notesByFolderName)

        context.saveOrLog()
        FilLog.data.info(
            "DemoLibrary: seeded \(payload.folders.count, privacy: .public) folders, \(payload.fils.count, privacy: .public) fils"
        )
    }

    /// Copies a bundled recording into the documents dir, where `AudioPlayerViewModel` resolves
    /// bare filenames — the same move the welcome fil makes for its tutorial video. Without the
    /// real file on disk the player renders a dead transport, which is why voice fils couldn't be
    /// seeded before.
    private static func attachAudio(_ spec: FilSpec, to note: Note) {
        guard let name = spec.audio else { return }
        let resource = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let bundled = Bundle.main.url(forResource: resource, withExtension: ext) else {
            FilLog.data.error("DemoLibrary: audio '\(name, privacy: .public)' not in the bundle")
            return
        }

        let dest = AudioPlayerViewModel.recordingsDirectory.appendingPathComponent(name)
        let destPath = dest.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: destPath) {
            try? FileManager.default.copyItem(at: bundled, to: dest)
            FileProtection.protectAtRest(dest)
        }
        guard FileManager.default.fileExists(atPath: destPath) else { return }

        note.audioFilePath = name
        note.duration = spec.duration ?? 0
    }

    /// Loads bundled images straight into the fil as `NoteImage`s, which is what makes it read as
    /// a photo fil rather than a text one.
    private static func attachImages(_ spec: FilSpec, to note: Note) {
        guard let names = spec.images, !names.isEmpty else { return }
        note.imageFilImages = names.enumerated().compactMap { index, name in
            let resource = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            guard
                let url = Bundle.main.url(forResource: resource, withExtension: ext),
                let data = try? Data(contentsOf: url)
            else {
                FilLog.data.error("DemoLibrary: image '\(name, privacy: .public)' not in the bundle")
                return nil
            }
            return NoteImage(data: data, order: index, note: note)
        }
    }

    /// App state that isn't stored in SwiftData — which folder is pinned to the Lock Screen, and
    /// the appearance override. Kept in the same JSON so the data file is the only thing anyone
    /// has to edit to change what a screenshot shows.
    private static func applyState(
        _ state: StateSpec?,
        foldersByName: [String: Folder],
        notesByFolderName: [String: [Note]]
    ) {
        if let appearance = state?.appearance, AppearanceMode(rawValue: appearance) != nil {
            UserDefaults.standard.set(appearance, forKey: AppearanceMode.storageKey)
        }

        guard let name = state?.pinnedFolder, let folder = foldersByName[name] else { return }

        // Newest first, capped to match LockScreenActivityCoordinator's blob peek. Built from the
        // notes we just inserted rather than folder.notes, which isn't materialised before a save.
        let blobs = (notesByFolderName[name] ?? [])
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(8)
            .map(\.activityBlob)

        PinnedFolderStore.shared.pin(
            id: folder.id,
            name: folder.name,
            count: notesByFolderName[name]?.count ?? 0,
            blobs: Array(blobs),
            gradientStartHex: folder.gradientStartHex,
            gradientEndHex: folder.gradientEndHex
        )
        UserDefaults.filAppGroup.set(
            LockScreenActivity.pinnedFolder.rawValue,
            forKey: LockScreenActivity.storageKey
        )
    }

    // MARK: - Wire format

    private struct Payload: Decodable {
        let folders: [FolderSpec]
        let fils: [FilSpec]
        let state: StateSpec?
    }

    private struct StateSpec: Decodable {
        /// Folder name to pin to the Lock Screen. Omit for the un-pinned hint state.
        let pinnedFolder: String?
        /// "auto", "light", or "dark".
        let appearance: String?
        /// Which screensaver the `canvas` capture raises: "liquid", "wave", "auroraLeaves",
        /// or "auroraRibbons". Defaults to liquid.
        let screensaverMode: String?
    }

    private struct FolderSpec: Decodable {
        let id: UUID
        let name: String
        let summary: String?
        let gradientStartHex: String
        let gradientEndHex: String
        let sortIndex: Int?
        /// Short fragments rendered as the pinned-folder stamps. Independent of `summary`, which
        /// is the caption in the folder list — so a folder can have stamps without a caption.
        let summaryParts: [String]?
    }

    private struct FilSpec: Decodable {
        let uuid: UUID
        let title: String?
        let transcript: String
        /// Folder name, matched against `folders[].name`. Omit to leave the fil in the Bin.
        let folder: String?
        let daysAgo: Double
        let gradientStartHex: String
        let gradientEndHex: String
        let todos: [String]?
        let completedTodos: [Bool]?
        /// Bundled filename, e.g. "demo-voice.m4a". Copied into the documents dir on seed.
        let audio: String?
        /// Seconds. Only meaningful alongside `audio`.
        let duration: Double?
        /// Bundled image filenames, in order. Makes the fil render as a photo fil.
        let images: [String]?
        let sourceURLString: String?
        let sourceTitle: String?
        let sortIndex: Int?
    }
}
