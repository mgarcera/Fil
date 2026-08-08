import SwiftUI
import SwiftData

/// Identifiable trigger so bulk-landfil can reuse the app's shared landfilConfirmation.
private struct BulkLandfilRequest: Identifiable { let id = UUID() }

/// One shared glass container at the bottom of the home holding BOTH the manual selection and the
/// Bin (unfiled fils) as stacked sections — so they never overlap and read as one component.
/// Selection: tap a blob to deselect; folder-menu moves all, trash landfils all (confirmed), ✕ clears.
/// Bin: drag a blob onto a folder to file it, or tap to open.
struct HomeBasket: View {
    /// Opens the tapped fil in a swipeable pager over its section's fils (tapped, container).
    var onOpen: (Note, [Note]) -> Void = { _, _ in }
    /// The Bin section shows only on the folders home (hidden inside a folder interior).
    var showBin: Bool = true

    private let selection = FilSelectionStore.shared
    @Query(filter: #Predicate<Note> { $0.folder == nil }, sort: \Note.timestamp, order: .reverse)
    private var unfiled: [Note]
    @State private var pendingBulkLandfil: BulkLandfilRequest?

    private var selected: [Note] { selection.selectedNotes() }
    private var hasSelection: Bool { !selection.isEmpty }
    private var hasBin: Bool { showBin && !unfiled.isEmpty }

    var body: some View {
        // Sections only — no glass/material of its own; the shared home dock provides the container.
        if hasSelection || hasBin {
            VStack(spacing: 12) {
                if hasSelection { selectionSection }
                if hasSelection && hasBin { Divider().overlay(Theme.divider) }
                if hasBin { binSection }
            }
            .animation(.snappy(duration: 0.3), value: hasSelection)
            .animation(.snappy(duration: 0.3), value: unfiled.count)
            .landfilConfirmation(item: $pendingBulkLandfil, message: { _ in
                "These fils will be deleted. This cannot be undone."
            }, onConfirm: { _ in withAnimation(.snappy) { selection.landfilSelected() } })
        }
    }

    // MARK: - Selection section

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("\(selected.count) selected")
                    .font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText)
                Spacer()
                Menu {
                    ForEach(selection.folders()) { folder in
                        Button(folder.name) { withAnimation(.snappy) { selection.moveSelected(to: folder) } }
                    }
                } label: { iconLabel("folder") }
                .disabled(selection.folders().isEmpty)
                Button { pendingBulkLandfil = BulkLandfilRequest() } label: { iconLabel("trash") }
                Button { withAnimation(.snappy) { selection.clear() } } label: { iconLabel("xmark") }
            }
            .foregroundStyle(Theme.primaryText)

            blobRow(selected) { note in
                onOpen(note, selected)                           // tap opens a pager over the selection
            } decorate: { view, note in
                view.draggable("card:\(note.uuid.uuidString)")   // drag onto a folder to file it
            }
        }
    }

    // MARK: - Bin section

    private var binSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Text("Bin").font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText)
                Text("\(unfiled.count)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
                Spacer()
            }
            blobRow(unfiled) { note in
                onOpen(note, unfiled)                // tap opens a pager over the Bin
            } decorate: { view, note in
                view.draggable("card:\(note.uuid.uuidString)")   // drag onto a folder to file
            }
        }
    }

    // MARK: - Shared pieces

    /// A 56pt icon button label (matches the composer's).
    private func iconLabel(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 56, height: 56)
            .contentShape(Circle())
    }

    /// A horizontal scroll of fil blobs; `onTap` per blob, with an optional per-blob `decorate`
    /// (e.g. `.draggable`).
    private func blobRow<Decorated: View>(
        _ notes: [Note],
        onTap: @escaping (Note) -> Void,
        @ViewBuilder decorate: @escaping (AnyView, Note) -> Decorated
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(notes, id: \.uuid) { note in
                    let base = AnyView(
                        blob(note, size: 40)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(note) }
                    )
                    decorate(base, note)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 44)
    }

    @ViewBuilder private func blob(_ note: Note, size: CGFloat) -> some View {
        Group {
            if note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty {
                NoteCardView(note: note, cardHeight: size)
            } else {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
            }
        }
        .frame(width: size, height: size)
    }
}
