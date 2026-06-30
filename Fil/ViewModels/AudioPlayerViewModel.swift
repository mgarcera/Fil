import AVFoundation
import SwiftUI

@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(path: String) {
        guard let url = Self.audioFileURL(for: path) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
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
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
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
            if !player.isPlaying {
                self.isPlaying = false
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
        if storedPath.hasPrefix("/") {
            let absoluteURL = URL(fileURLWithPath: storedPath)
            return fileManager.fileExists(atPath: absoluteURL.path()) ? absoluteURL : nil
        }

        let localURL = recordingsDirectory.appendingPathComponent(storedPath)
        return fileManager.fileExists(atPath: localURL.path()) ? localURL : nil
    }

    static func hasAudioFile(for storedPath: String) -> Bool {
        audioFileURL(for: storedPath) != nil
    }

    static var recordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
