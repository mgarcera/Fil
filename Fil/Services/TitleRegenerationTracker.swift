import Foundation
import Observation

/// Tracks which fils are currently regenerating their title/keyword, so any view showing
/// a fil (e.g. its card badge) can react — blur while it's thinking, then reveal the new
/// title. A shared `@Observable` singleton because the edit happens in one view (the
/// article) while the animation plays in another (the grid card); `@Transient` model
/// properties aren't reliably observed by SwiftUI, so this is the dependable channel.
@MainActor
@Observable
final class TitleRegenerationTracker {
    static let shared = TitleRegenerationTracker()
    private init() {}

    private(set) var regeneratingNoteIDs: Set<UUID> = []

    func begin(_ id: UUID) { regeneratingNoteIDs.insert(id) }
    func end(_ id: UUID) { regeneratingNoteIDs.remove(id) }
    func isRegenerating(_ id: UUID) -> Bool { regeneratingNoteIDs.contains(id) }
}
