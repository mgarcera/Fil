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
            "Move to landfil?",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { presented in
            Button("Landfil", role: .destructive) { onConfirm(presented) }
            Button("Cancel", role: .cancel) {}
        } message: { presented in
            Text(message(presented))
        }
    }
}

/// Shared teardown for permanently removing a fil ("landfil"), so the home grid and the article view
/// don't drift. Deletes the fil's audio + attached video files. Callers still own the actual
/// `modelContext.delete` + save + any animation — this is only the side-effect cleanup both paths
/// share. (A pinned folder's Live Activity count re-syncs on the next background pass, so a landfil'd
/// fil doesn't need to poke the pin here.)
@MainActor
enum FilLandfil {
    static func cleanUpResources(for note: Note) {
        if let audioURL = AudioPlayerViewModel.audioFileURL(for: note.audioFilePath) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        // Delete any video files attached to the fil's filaments (they live in the documents dir).
        for attachment in note.attachments {
            for entry in attachment.entries where entry.kind == .video {
                if let url = AudioPlayerViewModel.audioFileURL(for: entry.text ?? "") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
