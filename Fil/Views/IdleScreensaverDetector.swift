import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// Watches for in-app inactivity and fires `onIdle` after `idleDelay` seconds without
/// any touch. iOS has no first-party idle callback, so we attach a passive gesture
/// recognizer to the key window that observes every touch without consuming it, and
/// reset a timer on each. Only runs while `isActive` is true.
struct IdleScreensaverDetector: UIViewRepresentable {
    var isActive: Bool
    var idleDelay: TimeInterval
    var onIdle: () -> Void

    func makeUIView(context: Context) -> IdleObservingView {
        IdleObservingView()
    }

    func updateUIView(_ view: IdleObservingView, context: Context) {
        view.idleDelay = idleDelay
        view.onIdle = onIdle
        view.setActive(isActive)
    }
}

/// Backing view: installs the recognizer on its window and owns the idle timer.
final class IdleObservingView: UIView, UIGestureRecognizerDelegate {
    var idleDelay: TimeInterval = 60
    var onIdle: () -> Void = {}

    private var isActive = false
    private var timer: Timer?
    private weak var recognizer: ActivityRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachRecognizerIfNeeded()
    }

    private func attachRecognizerIfNeeded() {
        guard recognizer == nil, let window else { return }
        let recognizer = ActivityRecognizer()
        recognizer.delegate = self
        // Passive: never consume, delay, or cancel touches — just observe them.
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.onActivity = { [weak self] in self?.resetTimer() }
        window.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            resetTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func resetTimer() {
        guard isActive else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: idleDelay, repeats: false) { [weak self] _ in
            self?.onIdle()
        }
    }

    // Observe alongside every other gesture without blocking any of them.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A recognizer that reports touch activity but never recognizes, so it stays out of
/// the responder chain's way while still seeing every touch on the window.
private final class ActivityRecognizer: UIGestureRecognizer {
    var onActivity: () -> Void = {}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { onActivity() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { onActivity() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { onActivity() }
}
#endif
