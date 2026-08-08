import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the single pinned-folder Live Activity from a `PinnedFolderSnapshot`. In-process, so
/// updates are instant and need no server. Ends any prior activity for a different folder.
enum PinnedFolderLiveActivityController {
    static func pin(_ snapshot: PinnedFolderSnapshot) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = PinnedFolderLiveActivityAttributes.ContentState(snapshot: snapshot)
        let content = ActivityContent(
            state: state,
            staleDate: nil,
            relevanceScore: 100
        )

        let matching = Activity<PinnedFolderLiveActivityAttributes>.activities.first {
            $0.attributes.folderID == snapshot.id
        }
        if let matching {
            await matching.update(content)
            return
        }

        await endAll()

        do {
            _ = try Activity.request(
                attributes: PinnedFolderLiveActivityAttributes(folderID: snapshot.id),
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
        await endAll()
        #endif
    }

    #if canImport(ActivityKit)
    private static func endAll() async {
        for activity in Activity<PinnedFolderLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}
