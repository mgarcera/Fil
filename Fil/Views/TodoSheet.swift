import SwiftUI

/// Every to-do across all fils, grouped by the fil it belongs to. Reached from the left-hand FAB on
/// the home screen (mirror of the expand/collapse control). Tapping a fil header opens it; tapping a
/// to-do's circle marks it done (it stays, struck through); swipe right on a to-do to landfil it.
struct TodoSheet: View {
    let notes: [Note]
    let onToggle: (Note, Int) -> Void
    let onDeleteTodo: (Note, Int) -> Void
    let onOpenNote: (Note) -> Void

    @AppStorage("prefersLowercase") private var prefersLowercase = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if filsWithTodos.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                    todoList
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("to-dos")
                .font(Theme.dmSans(18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Text("\(openCount) open")
                .font(Theme.dmMono(12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - List

    private var todoList: some View {
        List {
            ForEach(filsWithTodos) { note in
                Section {
                    ForEach(todoIndices(for: note), id: \.self) { index in
                        todoRow(note, index)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteTodo(note, index)
                                } label: {
                                    Label("landfil", systemImage: "trash")
                                }
                                .tint(Theme.recordRed)
                            }
                    }
                } header: {
                    filHeader(note)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func filHeader(_ note: Note) -> some View {
        Button {
            onOpenNote(note)
        } label: {
            HStack(spacing: 10) {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    .frame(width: 18, height: 18)
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
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 4, trailing: 20))
        .accessibilityHint("opens the fil")
    }

    private func todoRow(_ note: Note, _ index: Int) -> some View {
        let done = isDone(note, index)
        return Button {
            onToggle(note, index)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(done ? Theme.tertiaryText : Theme.secondaryText)
                Text(note.todos[index])
                    .font(Theme.dmSans(14))
                    .foregroundStyle(done ? Theme.tertiaryText : Theme.secondaryText)
                    .strikethrough(done, color: Theme.tertiaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.todos[index])
        .accessibilityValue(done ? "done" : "open")
        .accessibilityHint(done ? "mark open" : "mark done")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("no to-dos yet")
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

    private var filsWithTodos: [Note] {
        notes
            .filter { !todoIndices(for: $0).isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var openCount: Int {
        filsWithTodos.reduce(0) { total, note in
            total + todoIndices(for: note).filter { !isDone(note, $0) }.count
        }
    }

    /// Indices of every non-empty to-do (open OR completed) for a fil.
    private func todoIndices(for note: Note) -> [Int] {
        note.todos.indices.filter { index in
            !note.todos[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func isDone(_ note: Note, _ index: Int) -> Bool {
        note.completedTodos.indices.contains(index) && note.completedTodos[index]
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
