import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One source of truth for the app's haptics, keyed by SEMANTIC ROLE (not raw style) so feedback stays
/// consistent everywhere. Styles decided in the 2026-08-11 haptic-alignment pass:
///   selection = .light · navigate/open/page = .soft · move/file/drop = .medium · reorder/toggle = .light
///   destructive (on confirm) = .warning · create/success = .success
/// Call the role, never the raw generator. Runs on the main thread from any context; no-op off UIKit.
enum Haptics {
    /// Select / deselect a fil.
    static func selection() { impact(.light) }
    /// Open a reader/folder, advance/page between fils.
    static func navigate() { impact(.soft) }
    /// Move / file into a folder, or a drag-drop commit.
    static func move() { impact(.medium) }
    /// Reorder within a list.
    static func reorder() { impact(.light) }
    /// Flip a state: to-do complete, pin.
    static func toggle() { impact(.light) }
    /// A confirmed destructive action (landfil / delete).
    static func destructive() { notify(.warning) }
    /// A creation succeeded: fil sent, folder made, article made.
    static func success() { notify(.success) }

    #if canImport(UIKit)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        onMain { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(type) }
    }
    private static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    #else
    // No haptics off UIKit; roles are no-ops. Untyped params so call sites don't reference UIKit enums.
    private static func impact(_ style: HapticImpact) {}
    private static func notify(_ type: HapticNotify) {}
    #endif
}

#if !canImport(UIKit)
/// Placeholder role tokens so the semantic call sites compile on non-UIKit platforms.
enum HapticImpact { case light, soft, medium, heavy, rigid }
enum HapticNotify { case success, warning, error }
#endif
