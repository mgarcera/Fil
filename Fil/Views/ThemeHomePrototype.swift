import SwiftUI
import SwiftData

/// TEMPORARY prototype — reimagines the home as theme-grouped sections instead of the day timeline:
/// a vertical stack of named clusters, each an always-open grid of small fil blobs. Theme is the
/// spine, newest-first within.
///
/// Clusters are MOCK (stable UUID hash into fixed buckets) so we can verdict the *feel* before
/// building the real on-device semantic clustering. Delete this file + its ContentView entry point
/// once the direction is locked.
struct ThemeHomePrototype: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedNote: Note?
    @AppStorage("prefersLowercase") private var prefersLowercase = false

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
            VStack(alignment: .leading, spacing: 12) {
                Text(theme.name)
                    .font(Theme.dmSans(18, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Each fil as a small blob + its title, so you can tell them apart at a glance.
                VStack(spacing: 10) {
                    ForEach(fils, id: \.uuid) { note in
                        Button { selectedNote = note } label: {
                            HStack(spacing: 12) {
                                NoteBlobShape(seed: note.blobShapeSeed)
                                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                                    .frame(width: 24, height: 24)
                                Text(displayTitle(note))
                                    .font(Theme.dmSans(15, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
