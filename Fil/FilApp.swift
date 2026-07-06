import SwiftUI
import SwiftData

@main
struct FilApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = true
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                // Text now scales with Dynamic Type; clamp the upper bound so the constrained
                // glass/blob layout stays usable at accessibility sizes. Revisit once the
                // fixed-height containers are made flexible (audit P2 #23).
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .modelContainer(modelContainer)
    }
}

private extension FilApp {
    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Note.self,
            NoteImage.self,
            KeywordAttachment.self,
            UserProfile.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard shouldResetStore(after: error) else {
                fatalError("Unresolved error loading container: \(error)")
            }

            do {
                try deleteStoreFiles(at: storeURL)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Unresolved error loading container after store reset: \(error)")
            }
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

    static func deleteStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let storeDirectory = storeURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: storeDirectory.path()) {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }

        let sidecarURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path() + "-shm"),
            URL(fileURLWithPath: storeURL.path() + "-wal")
        ]

        for url in sidecarURLs where fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
    }
}
