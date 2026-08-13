import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// The basket Live Activity — a single, always-one activity that shows how many captures
/// are waiting and a peek at the most recent. Kept separate from `PinnedFolderLiveActivityAttributes`
/// so capture never disturbs a user-pinned fil.
nonisolated struct FilBasketLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var blobs: [FilActivityBlob]
        var updatedAt: Date
    }
}
#endif
