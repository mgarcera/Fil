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
            await PinnedFolderLiveActivityController.unpin()

        case .bin:
            let bin = binState(modelContext: modelContext)
            BinActivitySnapshot.write(count: bin.count, titles: bin.titles)
            await PinnedFolderLiveActivityController.unpin()   // never let the two coexist
            await FilBasketLiveActivityController.apply(count: bin.count, recentTitles: bin.titles)

        case .pinnedFolder:
            BinActivitySnapshot.write(count: 0, titles: [])
            await FilBasketLiveActivityController.end()
            if let snapshot = refreshedFolderSnapshot(modelContext: modelContext) {
                await PinnedFolderLiveActivityController.pin(snapshot)
            } else {
                await PinnedFolderLiveActivityController.unpin()
            }
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
        let titles = notes.prefix(3).map { $0.islandTitle(lowercase: lowercase) }
        return (notes.count, titles)
    }

    /// Rebuilds the pinned folder's snapshot from its live contents (count + peek can drift as fils
    /// are added/filed/landfil'd) and persists it. Returns nil (and clears the pin) if the folder is
    /// gone or nothing is pinned.
    private static func refreshedFolderSnapshot(modelContext: ModelContext) -> PinnedFolderSnapshot? {
        guard let id = PinnedFolderStore.shared.pinnedFolderID else { return nil }
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
        guard let folder = try? modelContext.fetch(descriptor).first else {
            PinnedFolderStore.shared.unpin()
            return nil
        }
        let lowercase = UserDefaults.standard.bool(forKey: "prefersLowercase")
        let newest = folder.notes.sorted { $0.timestamp > $1.timestamp }
        let peek = newest.prefix(4).map { $0.islandTitle(lowercase: lowercase) }
        let name = lowercase ? folder.name.lowercased() : folder.name
        return PinnedFolderStore.shared.pin(
            id: folder.id,
            name: name,
            count: folder.notes.count,
            peek: Array(peek),
            gradientStartHex: folder.gradientStartHex,
            gradientEndHex: folder.gradientEndHex
        )
    }
}
