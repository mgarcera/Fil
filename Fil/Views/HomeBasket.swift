import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The consolidated dock's browsing surface: a single blob row for the tab chosen by the floating
/// `DockChipsRow` switcher (Bin vs Selected). Tap a blob to open, long-press to select. Move/copy/
/// delete live in the floating chips row and act on the shared selection.
struct HomeBasket: View {
    /// Opens the tapped fil in a swipeable pager over the shown set (fil, container).
    var onOpen: (Note, [Note]) -> Void = { _, _ in }
    /// The Bin tab shows only on the folders home (hidden inside a folder interior).
    var showBin: Bool = true
    /// Which set to show — owned by CanvasHome, shared with the floating switcher chip.
    @Binding var tab: DockTab

    private let selection = FilSelectionStore.shared
    @Query(filter: #Predicate<Note> { $0.folder == nil }, sort: \Note.timestamp, order: .reverse)
    private var unfiled: [Note]

    private var selected: [Note] { selection.selectedNotes() }
    private var hasSelection: Bool { !selection.isEmpty }
    private var hasBin: Bool { showBin && !unfiled.isEmpty }
    private var isVisible: Bool { hasBin || hasSelection }
    private var effectiveTab: DockTab { resolveDockTab(tab, hasBin: hasBin, hasSelection: hasSelection) }
    private var shown: [Note] { effectiveTab == .selected ? selected : unfiled }

    var body: some View {
        // Sections only — no glass/material of its own; the shared home dock provides the container.
        if isVisible {
            VStack(alignment: .leading, spacing: 12) {
                blobRow
                // Separates the basket from the composer below it in the shared dock.
                Divider().overlay(Theme.divider).padding(.top, 2)
            }
            .animation(.snappy(duration: 0.3), value: hasSelection)
            .animation(.snappy(duration: 0.3), value: unfiled.count)
        }
    }

    // MARK: - Blob row

    private var blobRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(shown, id: \.uuid) { note in
                    filBlob(note)
                        // Tap selects (keeps the current tab — a Bin selection stays on Bin); a quick
                        // long-press opens the reader (with a light haptic). Drag omitted for now.
                        .onTapGesture { withAnimation(.snappy) { selection.toggle(note.uuid) } }
                        .onLongPressGesture(minimumDuration: 0.2) {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            onOpen(note, shown)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .frame(height: 68)
    }

    /// A 44pt fil blob (or card for photo/voice fils). Selected fils get an adaptive outline
    /// (black in light mode, white in dark) hugging their own shape.
    private func filBlob(_ note: Note) -> some View {
        let isSel = selection.contains(note.uuid)
        let size: CGFloat = 44
        return blobBody(note, size: size, selected: isSel)
            .frame(width: size, height: size)
            .scaleEffect(isSel ? 1.06 : 1)
    }

    @ViewBuilder
    private func blobBody(_ note: Note, size: CGFloat, selected: Bool) -> some View {
        if isCard(note) {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            NoteCardView(note: note, cardHeight: size)
                .clipShape(shape)
                .overlay { if selected { shape.stroke(Color.primary, lineWidth: 2.5).padding(-4) } }
        } else {
            let shape = NoteBlobShape(seed: note.blobShapeSeed)
            shape
                .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                .overlay { if selected { shape.stroke(Color.primary, lineWidth: 2.5).padding(-4) } }
        }
    }

    /// Photo and voice fils render as cards (they show real media); link and note fils render as the
    /// gooey blob so their selection outline hugs the blob shape like a regular fil.
    private func isCard(_ note: Note) -> Bool {
        note.isImageFil || !note.audioFilePath.isEmpty
    }
}
