import Foundation

/// Which Live Activity, if any, Fil keeps on the Lock Screen / Dynamic Island. The user chooses
/// this in Settings; at most one runs at a time (enforced by `LockScreenActivityCoordinator`).
enum LockScreenActivity: String, CaseIterable, Identifiable {
    /// No Live Activity.
    case off
    /// The Bin — a live count of unfiled fils plus a peek at the most recent (Phase 1).
    case bin
    /// A pinned folder — its name, fil count, and a peek at its contents (Phase 2).
    case pinnedFolder

    var id: String { rawValue }

    /// Backing key. Stored in the App Group suite so out-of-process captures (the Action Button
    /// intent, the Share Extension) honor the same choice the app sees.
    static let storageKey = "lockScreenActivity"

    /// The current choice, resolved from the App Group suite (default `.off`).
    static var current: LockScreenActivity {
        let raw = UserDefaults.filAppGroup.string(forKey: storageKey) ?? ""
        return LockScreenActivity(rawValue: raw) ?? .off
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .bin: "Bin"
        case .pinnedFolder: "Folder"
        }
    }
}

/// One fil rendered as a gradient blob on a Lock Screen surface. Carries only the gradient + shape
/// seed — never any fil text — so the widget can draw the real blob without the body leaving the app.
nonisolated struct FilActivityBlob: Codable, Hashable {
    var startHex: String
    var endHex: String
    var seed: Double
}

/// A tiny App Group mirror of the Bin count so an out-of-process capture (the Action Button intent or
/// the Share Extension) can render an optimistic count on the island without reaching into SwiftData.
/// The app rewrites it from the true unfiled-fil set on every `LockScreenActivityCoordinator.sync`.
enum BinActivitySnapshot {
    private static let countKey = "binActivity.count"

    static func write(count: Int) {
        UserDefaults.filAppGroup.set(count, forKey: countKey)
    }

    static var count: Int { UserDefaults.filAppGroup.integer(forKey: countKey) }
}

extension UserDefaults {
    /// The shared App Group defaults (falls back to `.standard` if the container is unavailable).
    static let filAppGroup = UserDefaults(suiteName: FilBasketStore.appGroupIdentifier) ?? .standard
}
