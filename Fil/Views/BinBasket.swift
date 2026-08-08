import SwiftUI
import SwiftData

/// The Bin: a Droppy-style floating basket at the bottom of the home holding the unfiled fils
/// (folder == nil) — the deck's replacement. Collapsed it's a pile of blobs; tap to expand into a
/// list. File a fil by dragging it onto a folder, or swipe it left to add it to the selection basket
/// (then move from there). Tap a fil to open it.
struct BinBasket: View {
    /// Opens a fil (wired by ContentView to its article sheet).
    var onOpen: (UUID) -> Void = { _ in }

    @Query(filter: #Predicate<Note> { $0.folder == nil }, sort: \Note.timestamp, order: .reverse)
    private var unfiled: [Note]
    @State private var expanded = false

    var body: some View {
        if !unfiled.isEmpty {
            basket
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var basket: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Text("Bin").font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText)
                Text("\(unfiled.count)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
                Spacer()
                if expanded {
                    Button { withAnimation(.snappy) { expanded = false } } label: {
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            if expanded {
                ScrollView {
                    VStack(spacing: 8) { ForEach(unfiled, id: \.uuid) { note in row(note) } }
                }
                .frame(maxHeight: 260)
            } else {
                blobPile
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { expanded = true } }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.primaryText.opacity(0.08), lineWidth: 1))
        .animation(.snappy, value: expanded)
    }

    /// Minimized: an overlapping pile of the fils' blobs (no text).
    private var blobPile: some View {
        HStack(spacing: -12) {
            ForEach(Array(unfiled.prefix(8).enumerated()), id: \.element.uuid) { index, note in
                blob(note, size: 36)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .zIndex(Double(-index))
                    .draggable("card:\(note.uuid.uuidString)")
            }
            if unfiled.count > 8 {
                Text("+\(unfiled.count - 8)")
                    .font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 16)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40)
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 10) {
            blob(note, size: 24)
            Text(binTitle(note)).font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(note.uuid) }
        .draggable("card:\(note.uuid.uuidString)")   // drag onto a folder to file
        .swipeToSelect(note.uuid)                    // swipe left to add to the selection basket
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

    private func binTitle(_ note: Note) -> String {
        if note.isLinkFil || note.isImageFil || !note.audioFilePath.isEmpty {
            let t = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "fil" : t
        }
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "note" : body
    }
}
