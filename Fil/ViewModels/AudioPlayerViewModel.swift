import AVFoundation
import SwiftUI

@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    /// Live output amplitude (0…1) while playing, from the player's meters — drives the fil blob pulse.
    var level: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(path: String) {
        guard let url = Self.audioFileURL(for: path) else { return }
        do {
            // Note: no `prepareToPlay()` here. It activates the audio session, and
            // `load` runs on the main thread (from the view's `onAppear`), which
            // triggers the AVAudioSession "UI unresponsiveness" fault. `duration` is
            // available straight after init, and playback activates the session
            // off the main thread via `configurePlayback()` before `play()`.
            player = try AVAudioPlayer(contentsOf: url)
            player?.isMeteringEnabled = true
            duration = player?.duration ?? 0
        } catch {
            player = nil
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let time = fraction * player.duration
        player.currentTime = time
        currentTime = time
    }

    private func play() {
        Task { @MainActor in
            guard await AudioSessionCoordinator.configurePlayback() else { return }

            player?.play()
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        level = 0
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        level = 0
        stopTimer()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            // Live meter → linear amplitude (0…1): amplitude = 10^(dB/20).
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            self.level = Double(max(0, min(1, pow(10, power / 20))))
            if !player.isPlaying {
                self.isPlaying = false
                self.level = 0
                self.stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    static func audioFileURL(for storedPath: String) -> URL? {
        guard !storedPath.isEmpty else { return nil }

        let fileManager = FileManager.default
        // Use the decoded filesystem path: fileExists(atPath:) wants a real path, not a
        // percent-encoded one, so filenames with spaces (e.g. "a vid.mp4") resolve correctly.
        if storedPath.hasPrefix("/") {
            let absoluteURL = URL(fileURLWithPath: storedPath)
            return fileManager.fileExists(atPath: absoluteURL.path(percentEncoded: false)) ? absoluteURL : nil
        }

        let localURL = recordingsDirectory.appendingPathComponent(storedPath)
        return fileManager.fileExists(atPath: localURL.path(percentEncoded: false)) ? localURL : nil
    }

    static func hasAudioFile(for storedPath: String) -> Bool {
        audioFileURL(for: storedPath) != nil
    }

    static var recordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
