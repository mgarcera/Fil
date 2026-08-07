import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// The basket Live Activity — a single, always-one activity that shows how many captures
/// are waiting and a peek at the most recent. Kept separate from `PinnedFilLiveActivityAttributes`
/// so capture never disturbs a user-pinned fil.
struct FilBasketLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var recentTitles: [String]
        var updatedAt: Date
    }
}
#endif
