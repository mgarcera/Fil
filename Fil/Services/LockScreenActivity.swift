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

/// A tiny App Group mirror of the Bin so an out-of-process capture (the Action Button intent or the
/// Share Extension) can render an optimistic count on the island without reaching into SwiftData.
/// The app rewrites it from the true unfiled-fil set on every `LockScreenActivityCoordinator.sync`.
enum BinActivitySnapshot {
    private static let countKey = "binActivity.count"
    private static let titlesKey = "binActivity.titles"

    static func write(count: Int, titles: [String]) {
        UserDefaults.filAppGroup.set(count, forKey: countKey)
        UserDefaults.filAppGroup.set(titles, forKey: titlesKey)
    }

    static var count: Int { UserDefaults.filAppGroup.integer(forKey: countKey) }
    static var titles: [String] { UserDefaults.filAppGroup.stringArray(forKey: titlesKey) ?? [] }
}

extension UserDefaults {
    /// The shared App Group defaults (falls back to `.standard` if the container is unavailable).
    static let filAppGroup = UserDefaults(suiteName: FilBasketStore.appGroupIdentifier) ?? .standard
}
