//
//  ShakeToFile.swift
//  Fil
//
//  Shake detection for "file the Bin".
//

import SwiftUI
import UIKit

/// Shake is iOS's undo gesture, so taking it comes with rules.
///
/// Motion events start at the first responder and travel UP the responder chain, which is what
/// makes this safe: when a text field is focused, UIKit consumes the shake to offer Undo Typing
/// and it never reaches us. We only hear the shakes nobody else wanted — so the composer keeps
/// its undo and we get the gesture everywhere else, without inspecting focus ourselves.
///
/// The other half of the rule is that nothing may be destroyed by a gesture this easy to trigger
/// by accident. Shaking opens a review sheet; it does not move a single fil on its own.
///
/// Deliberately NOT an `extension UIWindow { override func motionEnded }`. Overriding a method in
/// an extension is undefined behaviour in Swift, and the whole app would inherit it — including
/// the share extension's text entry.
extension Notification.Name {
    static let filDidShake = Notification.Name("filDidShake")
}

private final class ShakeResponderController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Claim the chain only when nothing else wants it, so appearing never dismisses a keyboard.
        if view.window?.firstResponder == nil { becomeFirstResponder() }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        NotificationCenter.default.post(name: .filDidShake, object: nil)
    }
}

private struct ShakeResponder: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { ShakeResponderController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private extension UIWindow {
    /// The current first responder, found by asking rather than by tracking — used only to avoid
    /// stealing focus on appear.
    var firstResponder: UIResponder? {
        guard let root = rootViewController?.view else { return nil }
        return Self.search(root)
    }

    static func search(_ view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = search(sub) { return found }
        }
        return nil
    }
}

extension View {
    /// Run `action` when the device is shaken and no text field claimed the gesture first.
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeResponder().frame(width: 0, height: 0).accessibilityHidden(true))
            .onReceive(NotificationCenter.default.publisher(for: .filDidShake)) { _ in action() }
    }
}
