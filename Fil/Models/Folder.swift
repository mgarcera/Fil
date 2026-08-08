import Foundation
import SwiftData

/// A folder groups fils together. One fil lives in exactly one folder (or none — an unfiled fil
/// sits in the inbox, represented by `Note.folder == nil`, not by a real "inbox" folder).
@Model
final class Folder {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    /// A short 1–2 sentence caption of what the folder holds, written by Pro smart-organize.
    /// Empty for manually-created folders until a re-organize writes one.
    var summary: String = ""
    var gradientStartHex: String
    var gradientEndHex: String
    var createdAt: Date
    /// Manual sort position (drag-to-reorder on the home). Lower = higher in the list. Defaults to 0
    /// for folders made before this existed; normalized on first load.
    var sortIndex: Int = 0

    /// Fils filed into this folder. Deleting a folder nullifies membership — the fils survive and
    /// fall back to the inbox (unfiled) rather than being deleted.
    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note] = []

    init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        gradientStartHex: String = "#408CD9",
        gradientEndHex: String = "#6659CC",
        createdAt: Date = .now,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}
