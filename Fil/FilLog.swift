import Foundation
import OSLog
import SwiftData

/// App-wide loggers. Grouped by category so failures are filterable in Console / the device log.
enum FilLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.smidgecraft.Fil"
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Smart-search tracing: the cloud payload, the model's picks, the keyword fallback, and the
    /// empty-state suggestion, logged to the "search" category. Flip to `true` to watch surfacing
    /// decisions in Console while iterating; keep `false` in shipping builds. Guarding each call with
    /// `if FilLog.searchTracing` keeps the string interpolation from running when it's off.
    static let searchTracing = false
    static let search = Logger(subsystem: subsystem, category: "search")
}

extension ModelContext {
    /// Saves pending changes, logging any failure instead of silently swallowing it with `try?`.
    /// A no-op when there's nothing to save.
    func saveOrLog(_ context: String = #function, file: String = #fileID) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            FilLog.data.error(
                "SwiftData save failed in \(context, privacy: .public) [\(file, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
