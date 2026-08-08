import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the single Bin Live Activity from a caller-supplied count + peek. Runs in-process (from the
/// app or a `LiveActivityIntent`), so updates are instant and need no server. The caller decides what
/// the count means — the app passes the true unfiled-fil set; an out-of-process capture passes an
/// optimistic snapshot. Ends the activity when the count hits zero.
enum FilBasketLiveActivityController {
    /// Start or update the Bin activity. A zero count ends it (nothing to show).
    static func apply(count: Int, recentTitles: [String]) async {
        #if canImport(ActivityKit)
        guard count > 0 else { await end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = FilBasketLiveActivityAttributes.ContentState(
            count: count,
            recentTitles: recentTitles,
            updatedAt: .now
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        if let existing = Activity<FilBasketLiveActivityAttributes>.activities.first {
            await existing.update(content)
        } else {
            do {
                _ = try Activity.request(
                    attributes: FilBasketLiveActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            } catch {
                return
            }
        }
        #endif
    }

    /// End the Bin activity if one is running.
    static func end() async {
        #if canImport(ActivityKit)
        for activity in Activity<FilBasketLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
