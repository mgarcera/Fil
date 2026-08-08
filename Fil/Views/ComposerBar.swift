import SwiftUI
import PhotosUI

/// One editable to-do being composed alongside a fil.
struct ComposerTodo: Identifiable, Equatable {
    let id = UUID()
    var text: String = ""
}

/// The always-on composer — a floating liquid-glass bar pinned at the bottom of the home, riding
/// above the keyboard. Thought field + optional to-do "pills" + photo/checklist controls, and a
/// trailing send / mic button. Restored from the pre-blank-canvas design (ComposerBar era).
struct ComposerBar: View {
    @Binding var text: String
    @Binding var todos: [ComposerTodo]
    @Binding var selectedPhotos: [PhotosPickerItem]
    let stagedImageData: [Data]
    let isProcessing: Bool
    /// When set (inside a folder), the placeholder reads "add to {folder}" and the fil files there.
    var contextLabel: String? = nil
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onRecordVoice: () -> Void
    let onRemoveStagedImage: (Int) -> Void

    @State private var dissolvingText: String?
    @FocusState private var focusedTodoID: UUID?

    private let placeholders = ["tap to write", "thoughts come in all shapes and sizes"]
    private let placeholderInterval: TimeInterval = 10

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasText: Bool { !trimmedText.isEmpty }
    private var hasTodoContent: Bool { todos.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var canSend: Bool { hasText || !stagedImageData.isEmpty }
    private var isComposing: Bool { canSend || hasTodoContent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stagedImageData.isEmpty { stagedImageRow }

            inputArea

            if !todos.isEmpty {
                Divider().overlay(Theme.divider).padding(.top, 2)
                todoRows
            }

            HStack(alignment: .center, spacing: 10) {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 56, height: 56).contentShape(Circle())
                }
                .disabled(isProcessing)
                .accessibilityLabel("add photos")

                Button(action: addTodoPill) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 56, height: 56).contentShape(Circle())
                }
                .buttonStyle(.plain).disabled(isProcessing).accessibilityLabel("add to-do")

                Spacer(minLength: 0)

                trailingButton
            }
        }
        // No glass here — the shared home dock wraps composer + baskets in one liquid-glass container.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos)
        .onChange(of: focusedTodoID) { oldValue, _ in removeRowIfEmpty(oldValue) }
    }

    // MARK: - To-do pills

    private var todoRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($todos) { $todo in todoRow($todo) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos)
    }

    private func todoRow(_ todo: Binding<ComposerTodo>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            TextField("to-do", text: todo.text)
                .font(Theme.fredoka(13, weight: .light)).foregroundStyle(Theme.secondaryText)
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

    private func handleTodoReturn(for id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        if todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            todos.remove(at: index); focusedTodoID = nil; focus.wrappedValue = true
        } else {
            let pill = ComposerTodo()
            todos.insert(pill, at: index + 1); focusedTodoID = pill.id
        }
    }

    private func removeRowIfEmpty(_ id: UUID?) {
        guard let id, let index = todos.firstIndex(where: { $0.id == id }) else { return }
        guard todos[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { _ = todos.remove(at: index) }
    }

    // MARK: - Thought input

    private var inputArea: some View {
        ZStack(alignment: .leading) {
            if trimmedText.isEmpty, dissolvingText == nil {
                if let contextLabel {
                    AnimatedGradientRevealText(text: contextLabel, maxDuration: 1.2, settledOpacity: 0.4)
                        .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                        .allowsHitTesting(false)
                        .id(contextLabel)   // re-reveal when the folder context changes
                } else {
                    rotatingPlaceholder
                }
            }

            TextField("", text: $text, axis: .vertical)
                .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                .lineLimit(1...4).focused(focus).submitLabel(.return)
                .opacity(dissolvingText == nil ? 1 : 0)

            if let dissolvingText {
                GradientDissolveText(text: dissolvingText)
                    .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var trailingButton: some View {
        if isComposing {
            Button(action: sendWithDissolve) {
                beamedCircle(symbol: "arrow.up", weight: .bold).opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain).disabled(isProcessing || !canSend).accessibilityLabel("send fil")
        } else {
            Button(action: onRecordVoice) {
                filledCircle(symbol: "mic.fill")
            }
            .buttonStyle(.plain).accessibilityLabel("record voice note").accessibilityAddTraits(.startsMediaSession)
        }
    }

    private var rotatingPlaceholder: some View {
        TimelineView(.periodic(from: .now, by: placeholderInterval)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / placeholderInterval) % placeholders.count
            AnimatedGradientRevealText(text: placeholders[index], maxDuration: 1.2, settledOpacity: 0.4)
                .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
        }
        .allowsHitTesting(false)
    }

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
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.background)
            .frame(width: 56, height: 56).background(Theme.primaryText, in: Circle())
    }

    private func beamedCircle(symbol: String, weight: Font.Weight) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: weight)).foregroundStyle(Theme.background)
            .frame(width: 56, height: 56)
            .borderBeam(border: Theme.primaryText, beam: Theme.accentGradientColors, beamBlur: 6, cornerRadius: 28, isEnabled: true)
            .background(Theme.primaryText, in: Circle())
    }

    private var stagedImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stagedImageData.enumerated()), id: \.offset) { index, data in
                    stagedImageThumbnail(data: data, index: index)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder private func stagedImageThumbnail(data: Data, index: Int) -> some View {
        if let image = Image(data: data) {
            image.resizable().scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button { onRemoveStagedImage(index) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 14, height: 14).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain).offset(x: 5, y: -5).accessibilityLabel("remove photo")
                }
        }
    }
}
