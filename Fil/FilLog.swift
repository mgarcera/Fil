import Foundation
import OSLog
import SwiftData

/// App-wide loggers. Grouped by category so failures are filterable in Console / the device log.
enum FilLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil"
    static let data = Logger(subsystem: subsystem, category: "data")
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
