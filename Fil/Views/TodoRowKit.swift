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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isCompleted ? Theme.inactiveTabBackground : Theme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.secondaryText.opacity(isCompleted ? 0.4 : 0.6), lineWidth: 1.5)
                }

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// A tappable to-do row (checkbox + text). Tapping toggles done. Used verbatim by both the article
/// view (in a VStack) and the to-dos sheet (in a List) so the design lives in one place.
struct TodoRowContent: View {
    let text: String
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                TodoStatusCircle(isCompleted: isCompleted)

                Text(text)
                    .font(Theme.dmMono(13, weight: .bold))
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
        .accessibilityValue(isCompleted ? "done" : "open")
        .accessibilityHint(isCompleted ? "mark open" : "mark done")
    }
}

/// A lightweight swipe-left-to-landfil for to-do rows *outside* a `List` — SwiftUI's `.swipeActions`
/// only works inside a `List`, and the article view's to-do section is a plain `VStack`. Drag the row
/// left past the threshold to trigger `onLandfil`; a trash glyph fades in behind it only while
/// dragging, so nothing shows at rest (no opaque row background needed). Inside a `List`, keep using
/// native `.swipeActions` instead — this is only for non-List contexts.
struct SwipeToLandfil<Content: View>: View {
    let onLandfil: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    private let maxReveal: CGFloat = 96
    private let trigger: CGFloat = 120

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(offset <= -trigger ? Theme.recordRed : Theme.tertiaryText)
                .opacity(min(1, Double(-offset / maxReveal)))
                .padding(.trailing, 8)

            content
                .offset(x: offset)
                // Plain .gesture (not high-priority) so the vertical ScrollView still scrolls and the
                // inner toggle Button still taps — a horizontal drag isn't claimed by the scroll view.
                .gesture(swipe)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Only engage on a clearly-horizontal drag, so vertical scrolls pass through.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = max(-maxReveal - 24, min(0, value.translation.width))
            }
            .onEnded { value in
                if value.translation.width <= -trigger {
                    withAnimation(.easeOut(duration: 0.2)) { offset = -maxReveal - 24 }
                    onLandfil()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
                }
            }
    }
}
