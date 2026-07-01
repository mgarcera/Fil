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
        guard let clickPlayer else { return }

        configureAmbientSession()
        clickPlayer.currentTime = 0
        clickPlayer.play()
    }

    func playTabSound() {
        guard let tabPlayer else { return }

        configureAmbientSession()
        tabPlayer.currentTime = 0
        tabPlayer.play()
    }

    func playTransformRefilSound() {
        guard let transformPlayer else { return }

        configureAmbientSession()
        transformPlayer.currentTime = 0
        transformPlayer.play()
    }

    func playGridSound() {
        guard let gridPlayer else { return }

        configureAmbientSession()
        gridPlayer.currentTime = 0
        gridPlayer.play()
    }

    func playTapToWriteSound() {
        guard let tapToWritePlayer else { return }

        configureAmbientSession()
        tapToWritePlayer.currentTime = 0
        tapToWritePlayer.play()
    }

    func playLandfilSound() {
        guard let landfilPlayer else { return }

        configureAmbientSession()
        landfilPlayer.currentTime = 0
        landfilPlayer.play()
    }

    func playArticleMadeSound() {
        guard let articleMadePlayer else { return }

        configureAmbientSession()
        articleMadePlayer.currentTime = 0
        articleMadePlayer.play()
    }

    func startMeshDuringProcessSound() {
        guard let meshDuringProcessPlayer else { return }

        configureAmbientSession()
        guard !meshDuringProcessPlayer.isPlaying else { return }
        meshDuringProcessPlayer.currentTime = 0
        meshDuringProcessPlayer.numberOfLoops = 0
        meshDuringProcessPlayer.volume = 0
        meshDuringProcessPlayer.play()
        meshDuringProcessPlayer.setVolume(0.34, fadeDuration: 0.25)
    }

    func stopMeshDuringProcessSound() {
        guard let meshDuringProcessPlayer, meshDuringProcessPlayer.isPlaying else { return }

        meshDuringProcessPlayer.setVolume(0, fadeDuration: 0.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, let meshDuringProcessPlayer = self.meshDuringProcessPlayer else { return }
            guard meshDuringProcessPlayer.volume == 0 else { return }
            meshDuringProcessPlayer.stop()
            meshDuringProcessPlayer.currentTime = 0
        }
    }

    func playLightModeSound() {
        guard let lightModePlayer else { return }

        configureAmbientSession()
        lightModePlayer.currentTime = 0
        lightModePlayer.play()
    }

    func playTodoSound() {
        guard let todoSoundPlayer else { return }

        configureAmbientSession()
        todoSoundPlayer.currentTime = 0
        todoSoundPlayer.play()
    }

    func playTodoArticleToggleSound() {
        guard let todoArticleTogglePlayer else { return }

        configureAmbientSession()
        todoArticleTogglePlayer.currentTime = 0
        todoArticleTogglePlayer.play()
    }

    func playSettingsSound() {
        guard let settingsPlayer else { return }

        configureAmbientSession()
        settingsPlayer.currentTime = 0
        settingsPlayer.play()
    }

    func playCollapsingSound() {
        guard let collapsingPlayer else { return }

        configureAmbientSession()
        collapsingPlayer.currentTime = 0
        collapsingPlayer.play()
    }

    func playCollapsePartTwoSound() {
        guard let collapsingPartTwoPlayer else { return }

        configureAmbientSession()
        collapsingPartTwoPlayer.currentTime = 0
        collapsingPartTwoPlayer.play()
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
