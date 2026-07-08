import Foundation
import SwiftData

/// Shared teardown for permanently removing a fil ("landfil"), so the home grid and the article view
/// don't drift. Clears the fil's lock-screen pin (snapshot + Live Activity) if it was the pinned one,
/// then deletes its audio file. Callers still own the actual `modelContext.delete` + save + any
/// animation — this is only the side-effect cleanup that both paths share.
@MainActor
enum FilLandfil {
    static func cleanUpResources(for note: Note) {
        if PinnedFilStore.shared.isPinned(note) {
            PinnedFilStore.shared.unpin()
            Task { await PinnedFilLiveActivityController.unpin() }
        }
        if let audioURL = AudioPlayerViewModel.audioFileURL(for: note.audioFilePath) {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }
}
