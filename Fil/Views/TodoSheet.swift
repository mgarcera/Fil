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

    /// When false, only open to-dos are shown; when true, completed ones appear too (struck
    /// through). Toggled by the filter button in the header — a plain two-state switch, no menu.
    @State private var showsCompleted = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if !hasAnyTodos {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 4)

                    // Header (and its filter toggle) stays put even when the current filter has
                    // nothing to show, so you can always switch back to seeing completed ones.
                    if filsWithTodos.isEmpty {
                        allClearState
                    } else {
                        todoList
                    }
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
            filterButton
        }
    }

    /// Toggles between "open only" and "open + completed". Filled icon = filtering to open only;
    /// outline = showing everything.
    private var filterButton: some View {
        Button(action: toggleShowsCompleted) {
            Image(systemName: showsCompleted ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(showsCompleted ? Theme.secondaryText : Theme.primaryText)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("filter to-dos")
        .accessibilityValue(showsCompleted ? "showing open and completed" : "showing open only")
        .accessibilityHint("toggles between open only and all to-dos")
    }

    private func toggleShowsCompleted() {
        SoundscapeManager.shared.playTabSound()
        withAnimation(.snappy(duration: 0.25)) {
            showsCompleted.toggle()
        }
    }

    // MARK: - List

    private var todoList: some View {
        List {
            ForEach(filsWithTodos) { note in
                Section {
                    filHeaderRow(note)

                    ForEach(visibleItems(for: note)) { item in
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

    /// Shown when there are to-dos, but the "open only" filter has nothing to list.
    private var allClearState: some View {
        VStack(spacing: 8) {
            Text("all caught up")
                .font(Theme.dmSans(17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("no open to-dos. tap the filter to see completed ones.")
                .font(Theme.dmSans(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// True if any fil has a to-do at all (regardless of the current filter) — drives the
    /// "nothing here yet" empty state vs. the header + list.
    private var hasAnyTodos: Bool {
        notes.contains { !$0.todoRowItems.isEmpty }
    }

    /// The to-dos to show for a fil under the current filter.
    private func visibleItems(for note: Note) -> [FilTodoItem] {
        showsCompleted ? note.todoRowItems : note.todoRowItems.filter { !$0.done }
    }

    private var filsWithTodos: [Note] {
        notes
            .filter { !visibleItems(for: $0).isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
