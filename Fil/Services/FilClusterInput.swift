import Foundation

/// The value DTO for a fil handed to cloud surfacing (`ClaudeSurfacingService`) — search, summarize,
/// organize, and folder snippets. `Note` objects stay on the main actor; only these Sendable inputs
/// cross into the surfacing actor. (Named "cluster" for historical reasons; the on-device clustering
/// engine that once consumed it has been removed — Pro surfacing is Claude-only now.)
struct FilClusterInput: Sendable {
    let id: UUID
    let text: String     // transcript (or title/keyword)
    let keyword: String  // the fil's display label
    /// Compact "(when, type, to-dos)" tag for temporal / type / to-do queries. Empty when unused.
    var metadata: String = ""
}
