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
        for note in selectedNotes() { note.folder = folder; note.sortIndex = 0 }   // order is per-folder
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

    /// Copy the selected fils to the clipboard as Markdown (thought + link + to-do checkboxes).
    /// Non-destructive — the selection stays intact.
    func copySelectedAsMarkdown() {
        let md = selectedNotes().map(Self.markdown(for:)).joined(separator: "\n\n---\n\n")
        guard !md.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = md
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// One fil as a Markdown block: optional `## title`, link URL, thought body, and to-dos as
    /// GitHub-style checkboxes. Photos/voice are noted since their content isn't text.
    private static func markdown(for note: Note) -> String {
        var blocks: [String] = []
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty { blocks.append("## \(title)") }
        if note.isLinkFil, let url = note.sourceURL?.absoluteString { blocks.append(url) }
        if !body.isEmpty { blocks.append(body) }

        let checkboxes = note.todos.indices.compactMap { index -> String? in
            let text = note.todos[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let done = note.completedTodos.indices.contains(index) && note.completedTodos[index]
            return "- [\(done ? "x" : " ")] \(text)"
        }
        if !checkboxes.isEmpty { blocks.append(checkboxes.joined(separator: "\n")) }

        if note.isImageFil { blocks.append("_(photo)_") }
        if !note.audioFilePath.isEmpty { blocks.append("_(voice note)_") }

        return blocks.isEmpty ? "_(empty fil)_" : blocks.joined(separator: "\n\n")
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
