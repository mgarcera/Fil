import AVFoundation
import Foundation

enum AudioSessionCoordinator {
    private static let queue = DispatchQueue(label: "Fil.AudioSessionCoordinator")

    /// The category last applied to the shared session. Only ever read/written on
    /// `queue`, so access is serialized. Lets us skip redundant `setCategory`
    /// calls (the common case for back-to-back UI sounds).
    nonisolated(unsafe) private static var currentCategory: AVAudioSession.Category?

    static func configureAmbient() async -> Bool {
        #if os(iOS)
        await configure(category: .ambient, mode: .default, options: [.mixWithOthers])
        #else
        true
        #endif
    }

    /// Re-asserts the mixing `.ambient` category before UI sound effects so they
    /// never interrupt the user's music — the recorder's `.playAndRecord` category
    /// interrupts, so we switch back to `.ambient` whenever an effect plays.
    ///
    /// This is deliberately fire-and-forget on a background queue: `AVAudioSession`
    /// mutation on the main thread can hang the UI. Because it's idempotent (a no-op
    /// when already `.ambient`), the steady-state path does no work at all, so a
    /// sound effect that plays right after never waits on — or races — this call.
    static func ensureMixingAmbient() {
        #if os(iOS)
        queue.async {
            guard currentCategory != .ambient else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                currentCategory = .ambient
            } catch {
                // Leave currentCategory unchanged so the next effect retries.
            }
        }
        #endif
    }

    /// Runs audio work — typically `AVAudioPlayer.play()` — on the serial audio
    /// queue after asserting the mixing `.ambient` category. `play()` implicitly
    /// activates the shared session, and activating on the main thread is exactly
    /// what triggers the "can lead to UI unresponsiveness" fault; running it here
    /// keeps the category change, the activation, and playback all off the main
    /// thread. The serial queue also serializes all `AVAudioPlayer` access.
    static func performMixingAmbient(_ work: @escaping () -> Void) {
        #if os(iOS)
        queue.async {
            if currentCategory != .ambient {
                try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                currentCategory = .ambient
            }
            work()
        }
        #else
        work()
        #endif
    }

    /// Runs audio work (e.g. stopping/fading a player) on the serial audio queue
    /// without changing the category, so every `AVAudioPlayer` touch stays on one
    /// thread. Pass a `delay` to schedule it in the future.
    static func perform(after delay: TimeInterval = 0, _ work: @escaping () -> Void) {
        #if os(iOS)
        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            queue.async(execute: work)
        }
        #else
        work()
        #endif
    }

    static func configurePlayback() async -> Bool {
        #if os(iOS)
        await configure(category: .playback, mode: .default, options: [.mixWithOthers])
        #else
        true
        #endif
    }

    static func configurePlayAndRecord() async -> Bool {
        #if os(iOS)
        await configure(category: .playAndRecord, mode: .default, options: [])
        #else
        true
        #endif
    }

    private static func configure(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) async -> Bool {
        // Run both the category change and activation off the main thread — either
        // can block, and the OS flags them as potential UI hangs on the main thread.
        await withCheckedContinuation { continuation in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(category, mode: mode, options: options)
                    try session.setActive(true)
                    currentCategory = category
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
