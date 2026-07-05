import AVFoundation
import Foundation

final class SoundscapeManager {
    static let shared = SoundscapeManager()

    private var clickPlayer: AVAudioPlayer?
    private var tabPlayer: AVAudioPlayer?
    private var transformPlayer: AVAudioPlayer?
    private var gridPlayer: AVAudioPlayer?
    private var tapToWritePlayer: AVAudioPlayer?
    private var landfilPlayer: AVAudioPlayer?
    private var articleMadePlayer: AVAudioPlayer?
    private var meshDuringProcessPlayer: AVAudioPlayer?
    private var lightModePlayer: AVAudioPlayer?
    private var todoSoundPlayer: AVAudioPlayer?
    private var todoArticleTogglePlayer: AVAudioPlayer?
    private var settingsPlayer: AVAudioPlayer?
    private var collapsingPlayer: AVAudioPlayer?
    private var collapsingPartTwoPlayer: AVAudioPlayer?

    private init() {
        clickPlayer = makePlayer(named: "click", fileExtension: "mp3", volume: 0.75)
        tabPlayer = makePlayer(named: "tabsound", fileExtension: "mp3", volume: 0.28)
        transformPlayer = makePlayer(named: "transformrefil", fileExtension: "mp3", volume: 0.52)
        gridPlayer = makePlayer(named: "grid", fileExtension: "mp3", volume: 0.52)
        tapToWritePlayer = makePlayer(named: "taptowrite", fileExtension: "mp3", volume: 0.48)
        landfilPlayer = makePlayer(named: "landfil", fileExtension: "mp3", volume: 0.58)
        articleMadePlayer = makePlayer(named: "articlemade", fileExtension: "mp3", volume: 0.62)
        meshDuringProcessPlayer = makePlayer(named: "meshduringprocess", fileExtension: "mp3", volume: 0.34)
        lightModePlayer = makePlayer(named: "lightmode", fileExtension: "mp3", volume: 0.42)
        todoSoundPlayer = makePlayer(named: "todosound", fileExtension: "mp3", volume: 0.46)
        todoArticleTogglePlayer = makePlayer(named: "todoarticletoggle", fileExtension: "mp3", volume: 0.4)
        settingsPlayer = makePlayer(named: "settings", fileExtension: "mp3", volume: 0.44)
        collapsingPlayer = makePlayer(named: "collapsing", fileExtension: "mp3", volume: 0.5)
        collapsingPartTwoPlayer = makePlayer(named: "collapsingparttwo", fileExtension: "mp3", volume: 0.5)

        configureAmbientSession()
    }

    func playOpenFilClick() {
        play(clickPlayer)
    }

    func playTabSound() {
        play(tabPlayer)
    }

    func playTransformRefilSound() {
        play(transformPlayer)
    }

    func playGridSound() {
        play(gridPlayer)
    }

    func playTapToWriteSound() {
        play(tapToWritePlayer)
    }

    func playLandfilSound() {
        play(landfilPlayer)
    }

    func playArticleMadeSound() {
        play(articleMadePlayer)
    }

    func startMeshDuringProcessSound() {
        guard let meshDuringProcessPlayer else { return }

        AudioSessionCoordinator.performMixingAmbient {
            guard !meshDuringProcessPlayer.isPlaying else { return }
            meshDuringProcessPlayer.currentTime = 0
            meshDuringProcessPlayer.numberOfLoops = 0
            meshDuringProcessPlayer.volume = 0
            meshDuringProcessPlayer.play()
            meshDuringProcessPlayer.setVolume(0.34, fadeDuration: 0.25)
        }
    }

    func stopMeshDuringProcessSound() {
        guard let meshDuringProcessPlayer else { return }

        AudioSessionCoordinator.perform {
            guard meshDuringProcessPlayer.isPlaying else { return }
            meshDuringProcessPlayer.setVolume(0, fadeDuration: 0.2)
        }
        AudioSessionCoordinator.perform(after: 0.22) {
            guard meshDuringProcessPlayer.volume == 0 else { return }
            meshDuringProcessPlayer.stop()
            meshDuringProcessPlayer.currentTime = 0
        }
    }

    func playLightModeSound() {
        play(lightModePlayer)
    }

    func playTodoSound() {
        play(todoSoundPlayer)
    }

    func playTodoArticleToggleSound() {
        play(todoArticleTogglePlayer)
    }

    func playSettingsSound() {
        play(settingsPlayer)
    }

    func playCollapsingSound() {
        play(collapsingPlayer)
    }

    func playCollapsePartTwoSound() {
        play(collapsingPartTwoPlayer)
    }

    /// Plays a one-shot effect entirely on the audio queue. `AVAudioPlayer.play()`
    /// implicitly activates the shared session, so keeping it off the main thread
    /// is what avoids the audio-session UI-unresponsiveness fault.
    /// Global mute, controlled by the Sound toggle in Settings. Defaults to on when the
    /// key has never been set (`bool(forKey:)` returns false for a missing key, so the
    /// absence check preserves "sound on" for existing users).
    private var isSoundEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "soundEnabled") == nil || defaults.bool(forKey: "soundEnabled")
    }

    private func play(_ player: AVAudioPlayer?) {
        guard isSoundEnabled, let player else { return }

        AudioSessionCoordinator.performMixingAmbient {
            player.currentTime = 0
            player.play()
        }
    }

    private func makePlayer(named name: String, fileExtension: String, volume: Float) -> AVAudioPlayer? {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: fileExtension),
            Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Audio"),
            Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources/Audio")
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = volume
                return player
            }
        }

        return nil
    }

    private func configureAmbientSession() {
        // Re-assert the mixing `.ambient` category synchronously before each effect so
        // sounds never pause the user's music — even after the recorder has switched the
        // shared session to an interrupting category. Cheap, and avoids a startup race.
        AudioSessionCoordinator.ensureMixingAmbient()
    }
}
