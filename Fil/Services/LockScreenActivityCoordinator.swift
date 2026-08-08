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
            BinActivitySnapshot.write(count: 0)
            await FilBasketLiveActivityController.end()
            await PinnedFolderLiveActivityController.unpin()

        case .bin:
            let bin = binState(modelContext: modelContext)
            BinActivitySnapshot.write(count: bin.count)
            await PinnedFolderLiveActivityController.unpin()   // never let the two coexist
            await FilBasketLiveActivityController.apply(count: bin.count, blobs: bin.blobs)

        case .pinnedFolder:
            BinActivitySnapshot.write(count: 0)
            await FilBasketLiveActivityController.end()
            if let snapshot = refreshedFolderSnapshot(modelContext: modelContext) {
                await PinnedFolderLiveActivityController.pin(snapshot)
            } else {
                await PinnedFolderLiveActivityController.unpin()
            }
        }
    }

    /// How many fil blobs a Lock Screen surface carries (keeps the activity payload small).
    private static let blobPeekCap = 8

    /// The true Bin: unfiled fils (`folder == nil`), newest first, with a capped blob peek.
    private static func binState(modelContext: ModelContext) -> (count: Int, blobs: [FilActivityBlob]) {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.folder == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        let blobs = notes.prefix(blobPeekCap).map { $0.activityBlob }
        return (notes.count, Array(blobs))
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
        let blobs = newest.prefix(blobPeekCap).map { $0.activityBlob }
        let name = lowercase ? folder.name.lowercased() : folder.name
        return PinnedFolderStore.shared.pin(
            id: folder.id,
            name: name,
            count: folder.notes.count,
            blobs: Array(blobs),
            gradientStartHex: folder.gradientStartHex,
            gradientEndHex: folder.gradientEndHex
        )
    }
}
