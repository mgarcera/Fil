import SwiftUI
import PhotosUI

/// One editable to-do being composed alongside a fil. Identified so each floating pill
/// keeps a stable focus target as pills are inserted/removed.
struct ComposerTodo: Identifiable, Equatable {
    let id = UUID()
    var text: String = ""
}

/// The single, always-on composer bar. It shifts between three states in place:
/// idle (placeholder + mic), typing (text field + send), and recording (waveform + stop).
///
/// To-dos are created explicitly, never auto-extracted: the checklist button floats an
/// editable to-do "pill" above the bar. The thought field stays put — the pills are
/// lightweight satellites of it — and each pill is its own live, editable field. On send
/// the thought plus every non-empty pill become the fil.
struct ComposerBar: View {
    @Binding var text: String
    @Binding var todos: [ComposerTodo]
    @Binding var selectedPhotos: [PhotosPickerItem]
    let stagedImageData: [Data]
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let isProcessing: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onRemoveStagedImage: (Int) -> Void

    /// The just-sent text, shown dissolving in place for a beat after send.
    @State private var dissolvingText: String?
    /// Which floating to-do pill currently holds the keyboard, if any.
    @FocusState private var focusedTodoID: UUID?

    /// Rotating idle prompts, crossfaded slowly for a subtle sense of life.
    private let placeholders = [
        "tap to write",
        "thoughts come in all shapes and sizes",
    ]
    private let placeholderInterval: TimeInterval = 10

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasText: Bool { !trimmedText.isEmpty }

    private var hasTodoContent: Bool {
        todos.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// To-dos always accompany a thought (or image) — never stand alone. Send stays
    /// disabled until there's that contextual content, so a fil is never just a to-do list.
    private var canSend: Bool {
        hasText || !stagedImageData.isEmpty
    }

    /// Whether the trailing button should offer "send" at all (vs. the mic). Shows as soon
    /// as the user is composing anything, including to-dos — but stays disabled per canSend.
    private var isComposing: Bool {
        canSend || hasTodoContent
    }

    var body: some View {
        barContent
    }

    /// The glass bar itself — thought field, to-do rows, media/to-do controls, and the
    /// trailing action. To-dos render under the thought (mirroring the article) so nothing
    /// conceptually moves when the fil opens.
    private var barContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stagedImageData.isEmpty && !isRecording {
                stagedImageRow
            }

            inputArea

            if !todos.isEmpty && !isRecording {
                Divider()
                    .overlay(Theme.divider)
                    .padding(.top, 2)

                todoRows
            }

            HStack(alignment: .center, spacing: 10) {
                if !isRecording {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .disabled(isProcessing)

                    Button(action: addTodoPill) {
                        Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }

                Spacer(minLength: 0)

                trailingButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if !isRecording {
                focus.wrappedValue = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos)
        // When focus leaves a row (tapping another row, the thought field, or dismissing the
        // keyboard), drop it if it's still empty.
        .onChange(of: focusedTodoID) { oldValue, _ in
            removeRowIfEmpty(oldValue)
        }
    }

    // MARK: - To-do rows (inside the bar, under the thought)

    private var todoRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($todos) { $todo in
                todoRow($todo)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos)
    }

    private func todoRow(_ todo: Binding<ComposerTodo>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            TextField("to-do", text: todo.text)
                .font(Theme.dmMono(13))
                .foregroundStyle(Theme.secondaryText)
                .focused($focusedTodoID, equals: todo.wrappedValue.id)
                .submitLabel(.next)
                .onSubmit { handleTodoReturn(for: todo.wrappedValue.id) }
        }
        .padding(.vertical, 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func addTodoPill() {
        let pill = ComposerTodo()
        todos.append(pill)
        focusedTodoID = pill.id
    }

    /// Return on a filled pill spawns a fresh empty pill just after it (rapid entry).
    /// Return on an empty pill removes it and hands focus back to the thought field.
    private func handleTodoReturn(for id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            todos.remove(at: index)
            focusedTodoID = nil
            focus.wrappedValue = true
        } else {
            let pill = ComposerTodo()
            todos.insert(pill, at: index + 1)
            focusedTodoID = pill.id
        }
    }

    /// An empty row is ephemeral: once it loses focus it's removed, so there's no delete
    /// button to hunt for. To drop a filled row, clear its text and move on.
    private func removeRowIfEmpty(_ id: UUID?) {
        guard let id, let index = todos.firstIndex(where: { $0.id == id }) else { return }
        guard todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            _ = todos.remove(at: index)
        }
    }

    // MARK: - Thought input

    @ViewBuilder
    private var inputArea: some View {
        if isRecording {
            WaveformView(duration: recordingDuration, isAnimating: true, fillsWidth: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ZStack(alignment: .leading) {
                if trimmedText.isEmpty, dissolvingText == nil {
                    rotatingPlaceholder
                }

                TextField("", text: $text, axis: .vertical)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1...4)
                    .focused(focus)
                    .submitLabel(.return)
                    .opacity(dissolvingText == nil ? 1 : 0)

                if let dissolvingText {
                    GradientDissolveText(text: dissolvingText)
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.primaryText)
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if isRecording {
            Button(action: onStopRecording) {
                beamedCircle(symbol: "stop.fill", weight: .semibold)
            }
            .buttonStyle(.plain)
        } else if isComposing {
            Button(action: sendWithDissolve) {
                beamedCircle(symbol: "arrow.up", weight: .bold)
                    .opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing || !canSend)
        } else {
            Button(action: onStartRecording) {
                filledCircle(symbol: "mic.fill")
            }
            .buttonStyle(.plain)
        }
    }

    /// Idle prompt that slowly rotates. Driven off the wall clock via `TimelineView`
    /// rather than a `.task`, so it keeps advancing even as the composer's siblings churn.
    private var rotatingPlaceholder: some View {
        TimelineView(.periodic(from: .now, by: placeholderInterval)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / placeholderInterval) % placeholders.count
            AnimatedGradientRevealText(text: placeholders[index], maxDuration: 1.2, settledOpacity: 0.4)
                .font(Theme.dmSans(15))
                .foregroundStyle(Theme.primaryText)
        }
        .allowsHitTesting(false)
    }

    /// Captures the outgoing text so it can dissolve in place, then hands off to `onSend`
    /// (which clears the field + to-dos and starts the blob-creation flow).
    private func sendWithDissolve() {
        let sent = trimmedText
        onSend()
        guard !sent.isEmpty else { return }

        dissolvingText = sent
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            dissolvingText = nil
        }
    }

    private func filledCircle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.background)
            .frame(width: 36, height: 36)
            .background(Theme.primaryText, in: Circle())
    }

    /// A filled prominent circle with the animated accent border beam (send / stop).
    /// The beam is applied before the fill so it renders in front of the circle.
    private func beamedCircle(symbol: String, weight: Font.Weight) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(Theme.background)
            .frame(width: 36, height: 36)
            .borderBeam(
                border: Theme.primaryText,
                beam: Theme.accentGradientColors,
                beamBlur: 6,
                cornerRadius: 18,
                isEnabled: true
            )
            .background(Theme.primaryText, in: Circle())
    }

    private var stagedImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stagedImageData.enumerated()), id: \.offset) { index, data in
                    stagedImageThumbnail(data: data, index: index)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private func stagedImageThumbnail(data: Data, index: Int) -> some View {
        if let image = Image(data: data) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        onRemoveStagedImage(index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 14, height: 14)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
        }
    }
}
