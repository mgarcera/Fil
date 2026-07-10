import SwiftUI
import SwiftData

/// TEMPORARY prototype — reimagines the home as theme-grouped sections instead of the day timeline:
/// a vertical stack of named clusters, each a list of blob + title rows. Theme is the spine,
/// newest-first within. Now backed by the real on-device `FilClusteringService`.
///
/// Reached via a temporary grid button in the ContentView home header; delete both once the theme
/// home is promoted to replace the timeline.
struct ThemeHomePrototype: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedNote: Note?
    @State private var clusters: [FilCluster] = []
    @State private var hasComputed = false
    @AppStorage("prefersLowercase") private var prefersLowercase = false

    private var notesByID: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.uuid, $0) })
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    if !hasComputed {
                        Text("reading your fils…")
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 24)
                    } else if clusters.isEmpty {
                        Text("keep filling — themes emerge as you go.")
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 24)
                    }
                    ForEach(clusters) { cluster in
                        section(for: cluster)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: notes.map(\.uuid)) {
            await recomputeClusters()
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
    private func section(for cluster: FilCluster) -> some View {
        let fils = cluster.filIDs.compactMap { notesByID[$0] }
        if !fils.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(cluster.name)
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

    private func recomputeClusters() async {
        // Links and photos are identity-based, not meaning-based — they get their own fixed sections
        // and are excluded from the semantic grouping so they don't pollute the note themes.
        let linkFils = notes.filter { $0.isLinkFil }
        let photoFils = notes.filter { !$0.isLinkFil && $0.isImageFil }
        let textFils = notes.filter { !$0.isLinkFil && !$0.isImageFil }

        let inputs = textFils.map { note in
            FilClusterInput(id: note.uuid, text: clusterText(note), keyword: displayTitle(note))
        }
        var result = await FilClusteringService.shared.clusters(for: inputs)

        if !linkFils.isEmpty {
            result.append(FilCluster(name: "links", filIDs: linkFils.map(\.uuid)))
        }
        if !photoFils.isEmpty {
            result.append(FilCluster(name: "photos", filIDs: photoFils.map(\.uuid)))
        }

        clusters = result
        hasComputed = true
    }

    /// Text handed to the grouping model: the fil's title plus a short content snippet, so the model
    /// can read the note's tone and stance (which is what the "kind of thought" grouping keys on),
    /// not just a bare topic label.
    private func clusterText(_ note: Note) -> String {
        let title = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (title.isEmpty, body.isEmpty) {
        case (false, false): return "\(title): \(String(body.prefix(140)))"
        case (false, true):  return title
        case (true, false):  return String(body.prefix(140))
        case (true, true):   return "fil"
        }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
