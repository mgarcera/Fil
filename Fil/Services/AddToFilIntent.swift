import AppIntents

/// The single capture entry point for Fil.
///
/// This is a `LiveActivityIntent`, so it runs in the background — no app launch —
/// when invoked from Siri, Spotlight, the Shortcuts app, or the Action Button.
/// It does the two lightweight, background-safe things a suspended app can do:
///
///   1. Appends the captured text to the durable staging basket (`FilBasketStore`).
///   2. Reflects the new basket count on the Dynamic Island / Lock Screen immediately,
///      in-process (no server), via `FilBasketLiveActivityController`.
///
/// Captures stay in the basket until the user promotes them into fils — a background intent
/// can't mint a fil anyway (that needs SwiftData's `modelContext` and `ArticleGenerationService`),
/// so "stage now, promote later" is both the product choice and the technical shape.
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

        // Stage into the durable basket, then reflect the new count on the island —
        // both in-process, so the Dynamic Island updates instantly with no server.
        FilBasketStore.shared.add(text: trimmed)
        await FilBasketLiveActivityController.refresh()

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
