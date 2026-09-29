#if DEBUG
import SwiftUI

/// The type the paged-home study sets in, kept apart from `Theme` so the app's own typography is
/// untouched while this is a study.
///
/// **Two substitutions, asked for 2026-09-28.** Instrument Serif becomes **Newsreader**, which is
/// the face Sphere's site already uses, so Fil's display type moves toward the register this whole
/// redesign has been moving toward. Everything sans becomes **Helvetica Neue**.
///
/// **What "all sans serif" actually meant here.** `Theme.dmSans` is not DM Sans: it resolves to
/// `.system(.body, design: .default)`, which is SF, and the name is a leftover. `Theme.dmMono` is
/// SF Mono for the same reason. So the sans this replaces is SF plus the bundled Gabarito, and the
/// mono is left alone — Helvetica has no monospaced cut, and the study's counts and labels rely on
/// tabular figures.
///
/// **Dynamic Type survives.** `relativeTo: .body` on every custom face, matching what
/// `Theme.instrumentSerif` and `Theme.gabarito` already do; a bare `.custom(_:size:)` would pin the
/// size and quietly opt this surface out of accessibility sizing.
enum StudyType {
    /// Display. Four real cuts are registered rather than one synthesised — Newsreader's own
    /// SemiBold has drawn weight in the stems and keeps its counters open, where a synthesised
    /// bold thickens everything evenly and fills them in.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(serifFace(weight), size: size, relativeTo: .body)
    }

    private static func serifFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Newsreader-Bold"
        case .semibold:             "Newsreader-SemiBold"
        case .medium:               "Newsreader-Medium"
        default:                    "Newsreader-Regular"
        }
    }

    /// Everything else. Helvetica Neue ships on iOS, so nothing is bundled for it.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(faceName(weight), size: size, relativeTo: .body).weight(weight)
    }

    /// Helvetica Neue's own cuts. Asking for `.custom("Helvetica Neue")` and applying `.weight()`
    /// synthesises, which smears the letterforms; naming the real cut does not.
    private static func faceName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "HelveticaNeue-Bold"
        case .semibold:             "HelveticaNeue-Medium"
        case .medium:               "HelveticaNeue-Medium"
        case .light, .thin:         "HelveticaNeue-Light"
        default:                    "HelveticaNeue"
        }
    }
}
#endif
