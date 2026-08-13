import SwiftUI

/// A single to-do captured by value with a stable identity. Capturing text/done here (rather than
/// indexing `note.todos[index]` inside a row) is what keeps a row animating out of a delete from
/// reading a now-out-of-range index and crashing. `index` is the live position for toggle/delete.
struct FilTodoItem: Identifiable {
    let id: UUID       // stable per-to-do identity (from Note.todoIDs) — drives list animations
    let index: Int     // current position in the fil's todos array (for toggle/delete)
    let text: String
    let done: Bool
}

extension Note {
    /// Every non-empty to-do (open OR completed) captured by value with stable IDs — safe to use for
    /// `ForEach` identity, swipe state, and toggle/delete. Shared by the article view and the to-dos
    /// sheet so the two never drift.
    var todoRowItems: [FilTodoItem] {
        todos.indices.compactMap { index in
            let raw = todos[index]
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let done = completedTodos.indices.contains(index) && completedTodos[index]
            // IDs are backfilled before lists open; fall back defensively just in case.
            let id = todoIDs.indices.contains(index) ? todoIDs[index] : UUID()
            return FilTodoItem(id: id, index: index, text: raw, done: done)
        }
    }
}

/// The to-do checkbox, shared by the article view, the to-dos sheet, and the add-to-do field so the
/// look stays identical in one place. The open-state outline is deliberately high-contrast so it
/// reads clearly in dark mode.
struct TodoStatusCircle: View {
    let isCompleted: Bool
    /// White treatment for colored/dark card backgrounds (the folder fil cards): the outline and
    /// checkmark stay white in BOTH light and dark mode, since the card is already a colored wash.
    var onColor: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1.5)
                }

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(checkColor)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var fillColor: Color {
        if onColor { return .white.opacity(isCompleted ? 0.14 : 0.06) }
        return isCompleted ? Theme.inactiveTabBackground : Theme.cardBackground
    }
    private var strokeColor: Color {
        if onColor { return .white.opacity(isCompleted ? 0.5 : 0.7) }
        return Theme.secondaryText.opacity(isCompleted ? 0.4 : 0.6)
    }
    private var checkColor: Color {
        onColor ? .white : Theme.secondaryText
    }
}

/// A tappable to-do row (checkbox + text). Tapping toggles done. Used verbatim by both the article
/// view (in a VStack) and the to-dos sheet (in a List) so the design lives in one place.
struct TodoRowContent: View {
    let text: String
    let isCompleted: Bool
    /// The to-do text font — defaults to the shared DM Sans; folders pass Fredoka.
    var font: Font = Theme.dmSans(16, weight: .regular)
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                TodoStatusCircle(isCompleted: isCompleted)

                Text(text)
                    .font(font)
                    .foregroundStyle(Theme.secondaryText)
                    .strikethrough(isCompleted, color: Theme.tertiaryText)
                    .opacity(isCompleted ? 0.65 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(isCompleted ? "Done" : "Open")
        .accessibilityHint(isCompleted ? "Mark open" : "Mark done")
    }
}
