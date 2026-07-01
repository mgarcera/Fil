import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum PinnedFilLiveActivityController {
    static func pin(_ snapshot: PinnedFilSnapshot) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let matchingActivity = Activity<PinnedFilLiveActivityAttributes>.activities.first {
            $0.attributes.noteID == snapshot.id
        }
        let state = PinnedFilLiveActivityAttributes.ContentState(snapshot: snapshot)
        let content = ActivityContent(
            state: state,
            staleDate: Calendar.current.date(byAdding: .hour, value: 8, to: .now),
            relevanceScore: 100
        )

        if let matchingActivity {
            await matchingActivity.update(content)
            return
        }

        await endAll(dismissalPolicy: .immediate)

        do {
            _ = try Activity.request(
                attributes: PinnedFilLiveActivityAttributes(noteID: snapshot.id),
                content: content,
                pushType: nil
            )
        } catch {
            return
        }
        #endif
    }

    static func unpin() async {
        #if canImport(ActivityKit)
        await endAll(dismissalPolicy: .immediate)
        #endif
    }

    #if canImport(ActivityKit)
    private static func endAll(dismissalPolicy: ActivityUIDismissalPolicy) async {
        for activity in Activity<PinnedFilLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }
    }
    #endif
}
