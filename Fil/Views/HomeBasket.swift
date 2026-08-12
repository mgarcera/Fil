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
                        // Long-press selects; a quick tap opens the reader. `.exclusively` makes them
                        // mutually exclusive: a held press satisfies the long-press (tap never fires, so
                        // it doesn't also open); a quick tap fails the long-press and falls through to
                        // open. Select's own haptic lives in FilSelectionStore.toggle.
                        .gesture(
                            LongPressGesture(minimumDuration: 0.2)
                                .onEnded { _ in withAnimation(.snappy) { selection.toggle(note.uuid) } }
                                .exclusively(
                                    before: TapGesture()
                                        .onEnded {
                                            Haptics.navigate()
                                            onOpen(note, shown)
                                        }
                                )
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            // The enclosing horizontal ScrollView otherwise delays content touches ~0.15s (to detect a
            // scroll), which floors the long-press recognizer so minimumDuration below that does nothing.
            .background(ScrollTouchDelayDisabler())
        }
        .frame(height: 68)
    }

    /// A 44pt fil blob. Every fil type renders as its gooey blob here (the real media shows in the
    /// player), so the selection outline is always the blob shape — adaptive (black light / white dark).
    private func filBlob(_ note: Note) -> some View {
        let isSel = selection.contains(note.uuid)
        let size: CGFloat = 44
        let shape = NoteBlobShape(seed: note.blobShapeSeed)
        return shape
            .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
            .overlay { if isSel { shape.stroke(Color.primary, lineWidth: 2.5).padding(-4) } }
            .frame(width: size, height: size)
            .scaleEffect(isSel ? 1.06 : 1)
    }
}

#if canImport(UIKit)
/// Walks up to the enclosing UIScrollView and turns off `delaysContentTouches`, so taps/long-presses
/// on content inside a horizontal scroll register immediately instead of waiting out the scroll
/// disambiguation window. Drop it in the scroll's content via `.background(ScrollTouchDelayDisabler())`.
private struct ScrollTouchDelayDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        DispatchQueue.main.async { [weak probe] in
            var view = probe?.superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    scroll.delaysContentTouches = false
                    break
                }
                view = current.superview
            }
        }
        return probe
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
/// No-op off UIKit (there's no UIScrollView touch-delay to disable).
private struct ScrollTouchDelayDisabler: View { var body: some View { Color.clear } }
#endif
