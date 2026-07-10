import SwiftUI
import SwiftData

/// TEMPORARY prototype — reimagines the home as theme-grouped sections instead of the day timeline:
/// a vertical stack of named clusters, each surfacing its open to-dos up top with the fil blobs
/// tucked below (minimized; tap the header to reveal). Theme is the spine, newest-first within.
///
/// Clusters are MOCK (stable UUID hash into fixed buckets) so we can verdict the *feel* before
/// building the real on-device semantic clustering. Delete this file + its ContentView entry point
/// once the direction is locked.
struct ThemeHomePrototype: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNote: Note?
    /// Themes whose fil grid is revealed. Empty by default → fils stay minimized.
    @State private var expanded: Set<String> = []

    private struct MockTheme: Identifiable {
        let id = UUID()
        let name: String
    }
    private let themes: [MockTheme] = [
        .init(name: "half-formed ideas"),
        .init(name: "the lake house"),
        .init(name: "work & the job"),
        .init(name: "people i love"),
        .init(name: "everything else")
    ]

    private struct ThemeTodo: Identifiable {
        let id: UUID
        let note: Note
        let index: Int
        let text: String
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    ForEach(themes) { theme in
                        section(for: theme)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $selectedNote) { note in
            NavigationStack { ArticleView(note: note) }
                .presentationDetents([.fraction(0.6), .large])
                .presentationBackground(Theme.background)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("themes")
                .font(Theme.dmSans(24, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("prototype")
                .font(Theme.dmMono(11))
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
            Button("close") { dismiss() }
                .font(Theme.dmSans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func section(for theme: MockTheme) -> some View {
        let fils = fils(in: theme)
        if !fils.isEmpty {
            let isExpanded = expanded.contains(theme.name)
            let todos = openTodos(in: fils)

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    SoundscapeManager.shared.playCollapsingSound()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
                        if isExpanded { expanded.remove(theme.name) } else { expanded.insert(theme.name) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(theme.name)
                            .font(Theme.dmSans(18, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.tertiaryText)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // The theme's open to-dos, surfaced up top.
                if !todos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(todos) { todo in
                            TodoRowContent(text: todo.text, isCompleted: false) {
                                toggle(todo)
                            }
                        }
                    }
                }

                // The fils themselves — minimized until the header is tapped.
                if isExpanded {
                    LazyVGrid(columns: columns, spacing: 26) {
                        ForEach(fils, id: \.uuid) { note in
                            Button { selectedNote = note } label: {
                                NoteCardView(note: note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    /// MOCK grouping: a stable hash of the fil's UUID string picks a bucket. Stands in for the real
    /// semantic cluster assignment. Deterministic across launches so sections don't reshuffle.
    private func fils(in theme: MockTheme) -> [Note] {
        guard let index = themes.firstIndex(where: { $0.id == theme.id }) else { return [] }
        return notes.filter { bucket(for: $0) == index }
    }

    private func bucket(for note: Note) -> Int {
        let sum = note.uuid.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % themes.count
    }

    private func openTodos(in fils: [Note]) -> [ThemeTodo] {
        fils.flatMap { note in
            note.todoRowItems
                .filter { !$0.done }
                .map { ThemeTodo(id: $0.id, note: note, index: $0.index, text: $0.text) }
        }
    }

    private func toggle(_ todo: ThemeTodo) {
        todo.note.normalizeCompletedTodos()
        guard todo.note.completedTodos.indices.contains(todo.index) else { return }
        SoundscapeManager.shared.playTodoArticleToggleSound()
        withAnimation(.snappy) { todo.note.completedTodos[todo.index].toggle() }
        modelContext.saveOrLog()
    }
}
