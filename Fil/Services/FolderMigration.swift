import Foundation
import SwiftData

/// Folder maintenance helpers. On-device auto-clustering was removed: free users create folders
/// manually; Pro users can smart-organize via the Claude proxy. Existing fils simply start unfiled
/// (in the inbox) — the additive `Note.folder` migration already defaults them to nil.
@MainActor
enum FolderMigration {
    #if DEBUG
    /// DEBUG helper: drop all folders (the `.nullify` rule returns their fils to the inbox — fils are
    /// never deleted) so the manual/Pro flows can be re-tested from a clean slate.
    static func debugReset(context: ModelContext) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for folder in folders { context.delete(folder) }
        try? context.save()
    }
    #endif
}
