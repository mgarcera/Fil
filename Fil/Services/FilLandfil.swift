import Foundation
import SwiftData
import SwiftUI

extension View {
    /// The app's standard "move to landfil?" confirmation alert (the regular delete overlay), keyed
    /// on an optional item so it presents when the item is set and clears when dismissed. Shared so
    /// every landfil confirmation — fils and to-dos, in the to-dos sheet and the article view — reads
    /// and behaves identically.
    func landfilConfirmation<Item: Identifiable>(
        item: Binding<Item?>,
        message: @escaping (Item) -> String,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        alert(
            "move to landfil?",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { presented in
            Button("landfil", role: .destructive) { onConfirm(presented) }
            Button("Cancel", role: .cancel) {}
        } message: { presented in
            Text(message(presented))
        }
    }
}

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
