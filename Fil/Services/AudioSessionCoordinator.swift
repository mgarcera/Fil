import AVFoundation
import Foundation

enum AudioSessionCoordinator {
    private static let queue = DispatchQueue(label: "Fil.AudioSessionCoordinator")

    static func configureAmbient() async -> Bool {
        #if os(iOS)
        await configure(category: .ambient, mode: .default, options: [])
        #else
        true
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
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(category, mode: mode, options: options)
        } catch {
            return false
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
