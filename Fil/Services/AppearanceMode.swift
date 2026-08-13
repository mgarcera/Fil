import SwiftUI

/// The user's appearance choice: follow the system (Auto), or force Light / Dark. Replaces the old
/// dark-mode Bool toggle. Stored as a raw string in AppStorage under `AppearanceMode.storageKey`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    static let storageKey = "appearanceMode"

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// The scheme to force on the app; `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
