import SwiftUI

/// Every to-do across all fils, grouped by the fil it belongs to. Reached from the left-hand FAB on
/// the home screen (mirror of the expand/collapse control). Tapping a fil header opens it; tapping a
/// to-do's circle marks it done (it stays, struck through); swipe left on a to-do to landfil it.
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
                    filHeaderRow(note)

                    ForEach(note.todoRowItems) { item in
                        todoRow(note, item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // Indented so to-dos read as nested beneath their fil header (the
                            // checkbox lines up under the header's title text).
                            .listRowInsets(EdgeInsets(top: 6, leading: 56, bottom: 6, trailing: 20))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteTodo(note, item.index)
                                } label: {
                                    Label("landfil", systemImage: "trash")
                                }
                                .tint(Theme.recordRed)
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func filHeaderRow(_ note: Note) -> some View {
        Button {
            onOpenNote(note)
        } label: {
            HStack(spacing: 12) {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    .frame(width: 26, height: 26)
                Text(displayTitle(note))
                    .font(Theme.dmSans(18, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 6, trailing: 20))
        // Tap opens the fil; swipe right does too.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onOpenNote(note)
            } label: {
                Label("open", systemImage: "arrow.up.right")
            }
            .tint(Color(hex: note.gradientStartHex))
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("opens the fil")
    }

    /// Uses the shared `TodoRowContent` so the row is identical to the fil detail view.
    private func todoRow(_ note: Note, _ item: FilTodoItem) -> some View {
        TodoRowContent(text: item.text, isCompleted: item.done) {
            onToggle(note, item.index)
        }
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
            .filter { !$0.todoRowItems.isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var openCount: Int {
        filsWithTodos.reduce(0) { total, note in
            total + note.todoRowItems.filter { !$0.done }.count
        }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
