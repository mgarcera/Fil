import SwiftUI
import SwiftData
import CoreText

@main
struct FilApp: App {
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.auto.rawValue
    private let modelContainer: ModelContainer

    init() {
        Self.registerBundledFonts()
        modelContainer = Self.makeModelContainer()
        Self.protectStoreFiles()
    }

    /// Encrypt the SwiftData store (and its -wal/-shm sidecars) at rest.
    static func protectStoreFiles() {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            FileProtection.protectAtRest(directory.appendingPathComponent(name + suffix))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .dark).colorScheme)
                // Text now scales with Dynamic Type; clamp the upper bound so the constrained
                // glass/blob layout stays usable at accessibility sizes. Revisit once the
                // fixed-height containers are made flexible (audit P2 #23).
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                // Begin observing subscription state (Fil Pro entitlement + transaction updates).
                .task { StoreManager.shared.start() }
        }
        .modelContainer(modelContainer)
    }
}

/// The app's root. New users land straight in the app; the action-first onboarding
/// (first fil → congratulation → "from mason" seed fil) lives in ContentView.
/// See docs/onboarding/onboarding-design.md.
struct RootView: View {
    var body: some View {
        ContentView()
    }
}

private extension FilApp {
    /// Register bundled custom fonts (e.g. Instrument Serif) so `Font.custom` can find them,
    /// without needing a UIAppFonts Info.plist entry.
    static func registerBundledFonts() {
        let names = [
            "InstrumentSerif-Regular",
            "Fredoka-Light", "Fredoka-Regular", "Fredoka-Medium", "Fredoka-SemiBold", "Fredoka-Bold",
            "Caveat-Regular", "Caveat-Medium", "Caveat-SemiBold", "Caveat-Bold"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Note.self,
            Folder.self,
            NoteImage.self,
            KeywordAttachment.self,
            UserProfile.self
        ])
        // The store lives in Application Support, which isn't guaranteed to exist — create it first,
        // otherwise the first addPersistentStore fails with NSCocoaErrorDomain 512 ("Failed to create
        // file") and dumps a large diagnostic before CoreData recovers.
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // First recovery: if this looks like a migration/corruption failure, move the old
            // store aside (never silently delete) and try once more with a fresh store.
            if shouldResetStore(after: error) {
                do {
                    try moveStoreAside(at: storeURL)
                    return try ModelContainer(for: schema, configurations: [configuration])
                } catch {
                    // Fall through to the in-memory fallback below.
                }
            }

            // Last resort: launch on an in-memory store so the app still opens instead of
            // crashing. Data won't persist this session, but the user isn't locked out and the
            // on-disk store (moved aside above, if any) is preserved for recovery.
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let memoryContainer = try? ModelContainer(for: schema, configurations: [inMemory]) {
                return memoryContainer
            }

            fatalError("Unresolved error creating in-memory fallback container: \(error)")
        }
    }

    static var storeURL: URL {
        let applicationSupportURL = URL.applicationSupportDirectory
        let storeDirectoryURL = applicationSupportURL.appending(path: "default.store", directoryHint: .notDirectory)
        return storeDirectoryURL
    }

    static func shouldResetStore(after error: Error) -> Bool {
        let nsError = error as NSError
        let description = String(describing: error)

        if nsError.domain == NSCocoaErrorDomain,
           [134110, 134111].contains(nsError.code) {
            let hasDuplicateUUIDConstraintFailure =
                description.contains("ZNOTE.ZUUID")
                || description.contains("UNIQUE constraint failed: ZNOTE.ZUUID")
            let hasMigrationConstraintViolation =
                description.contains("constraint violation during attempted migration")
                || description.contains("migration")

            return hasDuplicateUUIDConstraintFailure && hasMigrationConstraintViolation
        }

        let hasModelContainerLoadIssue =
            description.contains("loadIssueModelContainer")
            || description.contains("SwiftDataError")
        let hasSchemaMismatch =
            description.contains("migration")
            || description.contains("schema")
            || description.contains("model")
            || description.contains("store")

        if hasModelContainerLoadIssue && hasSchemaMismatch {
            return true
        }

        return false
    }

    /// Moves the existing store (and its `-wal`/`-shm` sidecars) aside to a timestamped backup
    /// rather than deleting it, so a corrupt or unmigratable store is preserved for possible
    /// recovery instead of being silently destroyed.
    static func moveStoreAside(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let suffix = ".corrupt-\(Int(Date.now.timeIntervalSince1970))"

        let sidecarURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path() + "-shm"),
            URL(fileURLWithPath: storeURL.path() + "-wal")
        ]

        for url in sidecarURLs where fileManager.fileExists(atPath: url.path()) {
            let destination = URL(fileURLWithPath: url.path() + suffix)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: url, to: destination)
        }
    }
}
