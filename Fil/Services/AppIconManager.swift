import UIKit
import OSLog

/// Switches the home-screen app icon between the default and the six Fil Extra styles.
///
/// # How the alternates are wired (read this before adding a seventh)
///
/// Two ways exist to ship alternate icons. Fil uses the **asset catalog** one:
///
/// 1. **Asset catalog (chosen).** Each alternate is its own `*.appiconset` inside
///    `Fil/Assets.xcassets`, and the target sets `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`.
///    Every icon set other than `ASSETCATALOG_COMPILER_APPICON_NAME` (`AppIcon`) is then compiled
///    into `Assets.car` and registered as an alternate automatically: actool writes the
///    `CFBundleIcons` → `CFBundleAlternateIcons` dictionary into the built Info.plist for us.
///    Verified in the Debug build — the product's Info.plist contains all six entries, each a
///    `CFBundleIconName` pointing at its asset. Nothing about alternates is hand-written in
///    `Fil/Info.plist`, and nothing needs to be.
///
/// 2. **Loose PNGs (not chosen).** The old way: drop `Letterpress@2x.png` etc. at the bundle root
///    and hand-author `CFBundleAlternateIcons` with `CFBundleIconFiles` arrays in Info.plist. It
///    means maintaining per-scale PNGs by hand, keeping a plist in sync with a folder of files, and
///    losing dark/tinted icon variants entirely, which the asset catalog gives us for free the day
///    we want them.
///
/// The catalog route was picked because it makes adding an icon a one-folder change: create
/// `AppIcon-Foo.appiconset`, add it to `choices` below, done. No plist edit, no scale ladder.
///
/// **Adding an alternate:** the string passed to `setAlternateIconName` is the *asset set name*
/// (e.g. `AppIcon-Riso`), not a filename. Keep the two in step or the call fails at runtime with
/// "The requested alternate icon is not found".
///
/// # The system alert
///
/// iOS shows its own "You have changed the icon for Fil" alert on every successful change. There is
/// no supported way to suppress it (the private-selector trick that circulates would risk review).
/// Do not build UI that assumes the change is silent.
@MainActor
@Observable
final class AppIconManager {
    static let shared = AppIconManager()

    /// One selectable icon. `assetName == nil` is the default icon, which is always available.
    struct Choice: Identifiable, Hashable {
        let title: String
        /// The `*.appiconset` name in Assets.xcassets, or nil for the default icon.
        let assetName: String?
        var id: String { assetName ?? "default" }
    }

    // TODO: PLACEHOLDER ART. All six alternates are currently a copy of the default icon
    // (`AppIcon.appiconset/fillogo.png`), so the picker is wired end to end but every option looks
    // identical. Replace these six with real 1024x1024 opaque PNGs (no alpha, no rounded corners,
    // sRGB) at exactly these paths, keeping the filenames:
    //
    //   Fil/Assets.xcassets/AppIcon-Letterpress.appiconset/fil-icon-letterpress.png
    //   Fil/Assets.xcassets/AppIcon-Riso.appiconset/fil-icon-riso.png
    //   Fil/Assets.xcassets/AppIcon-Neon.appiconset/fil-icon-neon.png
    //   Fil/Assets.xcassets/AppIcon-Clay.appiconset/fil-icon-clay.png
    //   Fil/Assets.xcassets/AppIcon-Glass.appiconset/fil-icon-glass.png
    //   Fil/Assets.xcassets/AppIcon-Felt.appiconset/fil-icon-felt.png
    //
    // Each set's Contents.json already points at its filename, so dropping the art in is the only
    // step. Optional afterwards: add dark + tinted variants to each Contents.json the way
    // AppIcon.appiconset does.
    /// Every icon Fil offers, in the order Settings shows them. Names are final.
    static let choices: [Choice] = [
        Choice(title: "Default", assetName: nil),
        Choice(title: "Letterpress", assetName: "AppIcon-Letterpress"),
        Choice(title: "Riso", assetName: "AppIcon-Riso"),
        Choice(title: "Neon", assetName: "AppIcon-Neon"),
        Choice(title: "Clay", assetName: "AppIcon-Clay"),
        Choice(title: "Glass", assetName: "AppIcon-Glass"),
        Choice(title: "Felt", assetName: "AppIcon-Felt"),
    ]

    /// The asset name of the icon in use, or nil when the default is showing. Observable, so the
    /// picker's checkmark follows a change made anywhere.
    private(set) var currentIconName: String?

    /// False on the (few) configurations that can't change icons at all — the picker hides itself
    /// rather than offering taps that silently do nothing.
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil",
                             category: "appicon")

    private init() {
        currentIconName = UIApplication.shared.alternateIconName
    }

    /// Whether `choice` is the icon currently on the Home Screen.
    func isCurrent(_ choice: Choice) -> Bool { choice.assetName == currentIconName }

    /// Switch to `assetName`, or back to the default when it's nil.
    ///
    /// Returns true when the icon actually changed. iOS puts up its own confirmation alert on
    /// success (see the type comment) and the call fails while the app is backgrounded, so this is
    /// only ever called straight from a tap.
    @discardableResult
    func setIcon(_ assetName: String?) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else {
            log.notice("alternate icons unsupported on this device")
            return false
        }
        guard assetName != UIApplication.shared.alternateIconName else {
            currentIconName = assetName
            return false
        }
        do {
            try await UIApplication.shared.setAlternateIconName(assetName)
            currentIconName = UIApplication.shared.alternateIconName
            return true
        } catch {
            // Most often a name that doesn't match an icon set, or a call made from the background.
            // Leave `currentIconName` reflecting reality so the checkmark doesn't lie.
            log.error("alternate icon '\(assetName ?? "default", privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            currentIconName = UIApplication.shared.alternateIconName
            return false
        }
    }

    /// The artwork for a choice, for the picker's thumbnails.
    ///
    /// Alternate icons live only inside `Assets.car` (unlike the primary icon, which the build also
    /// flattens to `AppIcon60x60@2x.png` at the bundle root), so `UIImage(named:)` against the asset
    /// set name is the way in. The fallbacks keep the row from rendering an empty square if a
    /// lookup ever misses.
    func previewImage(for choice: Choice) -> UIImage? {
        if let assetName = choice.assetName {
            return UIImage(named: assetName) ?? primaryIconImage
        }
        return UIImage(named: "AppIcon") ?? primaryIconImage
    }

    /// The primary icon read out of the built Info.plist's `CFBundlePrimaryIcon` → `CFBundleIconFiles`.
    private var primaryIconImage: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let last = files.last
        else { return nil }
        return UIImage(named: last)
    }
}
