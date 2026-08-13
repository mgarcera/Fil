import AppIntents

/// The single capture entry point for Fil.
///
/// This is a `LiveActivityIntent`, so it runs in the background — no app launch —
/// when invoked from Siri, Spotlight, the Shortcuts app, or the Action Button.
/// It does the two lightweight, background-safe things a suspended app can do:
///
///   1. Appends the captured text to the out-of-app capture buffer (`FilBasketStore`).
///   2. Reflects an optimistic Bin count on the Dynamic Island / Lock Screen immediately,
///      in-process (no server), via `FilBasketLiveActivityController`.
///
/// A background intent can't mint a real fil (that needs SwiftData's `modelContext`), so it stages
/// here; the app drains the buffer into real unfiled fils
/// on the next launch. The island count is `snapshot + pending`, since the true Bin (unfiled fils)
/// isn't readable out of process — the next app-active sync corrects it from SwiftData.
struct AddToFilIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add to Fil"
    static let description = IntentDescription("Drop a thought straight into your fil basket.")

    /// Supplied by Shortcuts / Dictate Text / the Action Button. When invoked with no value
    /// (e.g. a bare Siri phrase), the system prompts with this dialog and captures the reply.
    @Parameter(title: "Text", requestValueDialog: "What do you want to fil?")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result() }

        // Stage into the capture buffer for the app to promote on next launch.
        FilBasketStore.shared.add(text: trimmed)

        // Reflect it on the island now, but only if the user keeps the Bin activity on. The count is
        // the last app-synced Bin snapshot plus what's pending in the buffer; blobs stay empty until
        // the next app-active sync rebuilds them from the real fils.
        if LockScreenActivity.current == .bin {
            let pending = FilBasketStore.shared.count
            await FilBasketLiveActivityController.apply(
                count: BinActivitySnapshot.count + pending,
                blobs: []
            )
        }

        return .result()
    }
}

/// Surfaces `AddToFilIntent` to Siri, Spotlight, and the Shortcuts app with zero setup,
/// and makes it assignable to the Action Button. Ships working out of the box.
struct FilAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToFilIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Fil this in \(.applicationName)",
                "New fil in \(.applicationName)"
            ],
            shortTitle: "Add to Fil",
            systemImageName: "plus.circle"
        )
    }
}
