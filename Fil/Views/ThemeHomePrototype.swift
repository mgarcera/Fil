import SwiftUI
import SwiftData

/// TEMPORARY prototype — reimagines the home as theme-grouped sections (Extra-style) instead of the
/// day timeline: a vertical scroll of named, collapsible clusters, each a grid of fil blobs, theme
/// as the spine, newest-first within a theme.
///
/// The clusters here are MOCK — fils are hand-assigned to a fixed set of themed buckets by a stable
/// hash — so we can verdict the *feel* before building the real on-device semantic clustering.
/// Delete this file (and its entry point in ContentView) once the direction is locked.
struct ThemeHomePrototype: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedNote: Note?
    @State private var collapsed: Set<String> = []

    /// Placeholder themes. The real version generates an emoji + short name per on-device cluster.
    private struct MockTheme: Identifiable {
        let id = UUID()
        let emoji: String
        let name: String
    }
    private let themes: [MockTheme] = [
        .init(emoji: "💭", name: "half-formed ideas"),
        .init(emoji: "🌊", name: "the lake house"),
        .init(emoji: "💼", name: "work & the job"),
        .init(emoji: "❤️", name: "people i love"),
        .init(emoji: "✨", name: "everything else")
    ]

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
            let isCollapsed = collapsed.contains(theme.name)
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    SoundscapeManager.shared.playCollapsingSound()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
                        if isCollapsed { collapsed.remove(theme.name) } else { collapsed.insert(theme.name) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(theme.emoji)
                            .font(.system(size: 18))
                        Text(theme.name)
                            .font(Theme.dmSans(18, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.tertiaryText)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isCollapsed {
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
}
