import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the single basket Live Activity from the current `FilBasketStore` contents.
/// Runs in-process (from the app or a `LiveActivityIntent`), so updates are instant and
/// need no server. Ends the activity when the basket empties.
enum FilBasketLiveActivityController {
    @MainActor
    static func refresh() async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let existing = Activity<FilBasketLiveActivityAttributes>.activities.first
        let store = FilBasketStore.shared

        guard store.count > 0 else {
            if let existing { await existing.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let state = FilBasketLiveActivityAttributes.ContentState(
            count: store.count,
            recentTitles: store.recentTitles(),
            updatedAt: .now
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        if let existing {
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
}
