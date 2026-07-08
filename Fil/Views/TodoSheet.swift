import SwiftUI

/// Every open (incomplete) to-do across all fils, grouped by the fil it belongs to. Reached from
/// the left-hand FAB on the home screen (mirror of the expand/collapse control). Tapping a fil
/// header opens it; tapping a to-do's circle marks it done and it eases out of the list.
struct TodoSheet: View {
    let notes: [Note]
    let onToggle: (Note, Int) -> Void
    let onOpenNote: (Note) -> Void

    @AppStorage("prefersLowercase") private var prefersLowercase = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if filsWithOpenTodos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        header
                        ForEach(filsWithOpenTodos) { note in
                            filGroup(note)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .animation(.snappy, value: openTodoCount)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("to-dos")
                .font(Theme.dmSans(18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Text("\(openTodoCount) open")
                .font(Theme.dmMono(12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func filGroup(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onOpenNote(note)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                        .frame(width: 14, height: 14)
                    Text(displayTitle(note))
                        .font(Theme.dmSans(15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("opens the fil")

            ForEach(openTodoIndices(for: note), id: \.self) { index in
                todoRow(note, index)
            }
        }
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func todoRow(_ note: Note, _ index: Int) -> some View {
        Button {
            onToggle(note, index)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
                Text(note.todos[index])
                    .font(Theme.dmMono(14))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.todos[index])
        .accessibilityHint("mark done")
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("no open to-dos")
                .font(Theme.dmSans(17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("highlight text in a fil and make it a to-do — they'll gather here.")
                .font(Theme.dmSans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Data

    private var filsWithOpenTodos: [Note] {
        notes
            .filter { !openTodoIndices(for: $0).isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var openTodoCount: Int {
        filsWithOpenTodos.reduce(0) { $0 + openTodoIndices(for: $1).count }
    }

    private func openTodoIndices(for note: Note) -> [Int] {
        note.todos.indices.filter { index in
            let text = note.todos[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let done = note.completedTodos.indices.contains(index) && note.completedTodos[index]
            return !text.isEmpty && !done
        }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
