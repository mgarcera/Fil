import Foundation
import SwiftData

/// The single point that reconciles Fil's Live Activities with the user's Settings choice and the
/// live data. Enforces "at most one activity running": whatever the setting selects is started/updated
/// and every other managed activity is ended. Call it on app-active, when the setting changes, and
/// whenever the Bin (unfiled fils) changes.
@MainActor
enum LockScreenActivityCoordinator {
    static func sync(modelContext: ModelContext) async {
        switch LockScreenActivity.current {
        case .off:
            BinActivitySnapshot.write(count: 0, titles: [])
            await FilBasketLiveActivityController.end()
            await PinnedFilLiveActivityController.unpin()

        case .bin:
            let bin = binState(modelContext: modelContext)
            BinActivitySnapshot.write(count: bin.count, titles: bin.titles)
            await PinnedFilLiveActivityController.unpin()   // never let the two coexist
            await FilBasketLiveActivityController.apply(count: bin.count, recentTitles: bin.titles)

        case .pinnedFolder:
            // Phase 2 wires the folder-pin activity here. For now keep the Bin activity down so the
            // switch still behaves (choosing "Folder" simply shows nothing yet).
            BinActivitySnapshot.write(count: 0, titles: [])
            await FilBasketLiveActivityController.end()
        }
    }

    /// The true Bin: unfiled fils (`folder == nil`), newest first, with a 3-item peek.
    private static func binState(modelContext: ModelContext) -> (count: Int, titles: [String]) {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.folder == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        let lowercase = UserDefaults.standard.bool(forKey: "prefersLowercase")
        let titles = notes.prefix(3).map { binTitle($0, lowercase: lowercase) }
        return (notes.count, titles)
    }

    /// A short island label for a fil — its badge text, else a snippet of the thought. Mirrors the
    /// home's `displayTitle` so the island reads the same as the Bin.
    private static func binTitle(_ note: Note, lowercase: Bool) -> String {
        let badge = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !badge.isEmpty ? badge : (body.isEmpty ? "fil" : String(body.prefix(40)))
        return lowercase ? title.lowercased() : title
    }
}
