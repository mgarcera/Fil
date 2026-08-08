import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// The pinned-folder Live Activity — a single activity showing one folder's name, fil count, and a
/// short peek at its contents. Structurally mirrored by the widget-target copy so ActivityKit can
/// decode the shared content state.
struct PinnedFolderLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        var count: Int
        var blobs: [FilActivityBlob]
        var gradientStartHex: String
        var gradientEndHex: String
        var updatedAt: Date
    }

    var folderID: UUID
}

extension PinnedFolderLiveActivityAttributes.ContentState {
    init(snapshot: PinnedFolderSnapshot) {
        self.init(
            name: snapshot.name,
            count: snapshot.count,
            blobs: snapshot.blobs,
            gradientStartHex: snapshot.gradientStartHex,
            gradientEndHex: snapshot.gradientEndHex,
            updatedAt: snapshot.updatedAt
        )
    }
}
#endif
