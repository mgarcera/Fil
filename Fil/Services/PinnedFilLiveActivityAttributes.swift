import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct PinnedFilLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var previewText: String
        var keyword: String
        var gradientStartHex: String
        var gradientEndHex: String
        var updatedAt: Date
    }

    var noteID: UUID
}

extension PinnedFilLiveActivityAttributes.ContentState {
    init(snapshot: PinnedFilSnapshot) {
        self.init(
            title: snapshot.title,
            previewText: snapshot.previewText,
            keyword: snapshot.keyword,
            gradientStartHex: snapshot.gradientStartHex,
            gradientEndHex: snapshot.gradientEndHex,
            updatedAt: snapshot.updatedAt
        )
    }
}
#endif
