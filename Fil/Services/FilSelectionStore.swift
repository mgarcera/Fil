import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Holds the fils the user has swipe-selected inside folders, for the Droppy-style selection basket.
/// A singleton so the swipe (in a folder card) and the basket (an app-level overlay) share one source
/// of truth. It keeps a `ModelContext` reference so it can resolve fils + perform bulk moves/landfils
/// without living inside a SwiftData view.
@MainActor
@Observable
final class FilSelectionStore {
    static let shared = FilSelectionStore()
    private init() {}

    /// Selected fil ids, in the order they were added.
    private(set) var selectedIDs: [UUID] = []
    /// Set once by ContentView so the basket can fetch + mutate outside a SwiftData view.
    @ObservationIgnored var context: ModelContext?

    var isEmpty: Bool { selectedIDs.isEmpty }
    var count: Int { selectedIDs.count }
    func contains(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func toggle(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) }
        else { selectedIDs.append(id) }
    }
    func remove(_ id: UUID) { selectedIDs.removeAll { $0 == id } }
    func clear() { selectedIDs.removeAll() }

    /// Resolve the selected fils (order preserved). Empty if the context isn't wired yet.
    func selectedNotes() -> [Note] {
        guard let context else { return [] }
        let all = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let byID = Dictionary(all.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        return selectedIDs.compactMap { byID[$0] }
    }

    func folders() -> [Folder] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func moveSelected(to folder: Folder?) {
        for note in selectedNotes() { note.folder = folder }
        try? context?.save()
        clear()
    }

    func landfilSelected() {
        for note in selectedNotes() {
            FilLandfil.cleanUpResources(for: note)
            context?.delete(note)
        }
        try? context?.save()
        clear()
    }
}

/// Swipe a fil card LEFT (right-to-left) to toggle it into the selection basket — the opposite
/// direction from the edge swipe-back-a-page, so they don't collide. Commits on release past a
/// threshold (never live per-frame), mirroring a "select" tap (swipe-shortcut pattern).
struct SwipeToSelect: ViewModifier {
    let noteID: UUID
    private let store = FilSelectionStore.shared
    @State private var dx: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .overlay(alignment: .topTrailing) {
                if store.contains(noteID) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(8)
                }
            }
            .opacity(store.contains(noteID) ? 0.6 : 1)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) {
                            dx = max(value.translation.width, -70)
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -46 && abs(value.translation.width) > abs(value.translation.height) {
                            store.toggle(noteID)
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dx = 0 }
                    }
            )
    }
}

extension View {
    func swipeToSelect(_ id: UUID) -> some View { modifier(SwipeToSelect(noteID: id)) }
}

/// Identifiable trigger so the basket's bulk-landfil can reuse the app's shared landfilConfirmation.
private struct BulkLandfilRequest: Identifiable { let id = UUID() }

/// The Droppy-style selection basket: a bottom-anchored pile of the selected fils that collapses to a
/// stack, taps to expand into a scroll, swipes a row away to deselect, and carries bulk actions.
/// Hosted as an in-app overlay by ContentView (reads the shared FilSelectionStore).
struct SelectionBasket: View {
    private let store = FilSelectionStore.shared
    @State private var expanded = false
    @State private var pendingBulkLandfil: BulkLandfilRequest?

    var body: some View {
        if !store.isEmpty {
            basket
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var basket: some View {
        let notes = store.selectedNotes()
        return VStack(spacing: 12) {
            // Action bar.
            HStack(spacing: 14) {
                Text("\(notes.count) selected")
                    .font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText)
                Spacer()
                Menu {
                    ForEach(store.folders()) { folder in
                        Button(folder.name) { withAnimation(.snappy) { store.moveSelected(to: folder) } }
                    }
                } label: {
                    Image(systemName: "folder").font(.system(size: 17, weight: .semibold))
                }
                .disabled(store.folders().isEmpty)
                Button { pendingBulkLandfil = BulkLandfilRequest() } label: {
                    Image(systemName: "trash").font(.system(size: 17, weight: .semibold))
                }
                // Minimize (only when maximized) — collapses back to the blob pile.
                if expanded {
                    Button { withAnimation(.snappy) { expanded = false } } label: {
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                }
                Button { withAnimation(.snappy) { store.clear() } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .foregroundStyle(Theme.primaryText)

            if expanded {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(notes, id: \.uuid) { note in row(note) }
                    }
                }
                .frame(maxHeight: 260)
            } else {
                blobPile(notes)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { expanded = true } }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.primaryText.opacity(0.08), lineWidth: 1))
        .animation(.snappy, value: expanded)
        .landfilConfirmation(item: $pendingBulkLandfil, message: { _ in
            "These fils will be deleted. This cannot be undone."
        }, onConfirm: { _ in withAnimation(.snappy) { store.landfilSelected() } })
    }

    /// Minimized: only the fil blobs, an overlapping peeking pile (no text).
    private func blobPile(_ notes: [Note]) -> some View {
        HStack(spacing: -12) {
            ForEach(Array(notes.prefix(8).enumerated()), id: \.element.uuid) { i, note in
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .zIndex(Double(-i))
            }
            if notes.count > 8 {
                Text("+\(notes.count - 8)")
                    .font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 16)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40)
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 10) {
            NoteBlobShape(seed: note.blobShapeSeed)
                .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                .frame(width: 24, height: 24)
            Text(basketTitle(note)).font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.primaryText).lineLimit(1)
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { store.remove(note.uuid) } } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func basketTitle(_ note: Note) -> String {
        if note.isLinkFil || note.isImageFil || !note.audioFilePath.isEmpty {
            let t = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "fil" : t
        }
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "note" : body
    }
}
