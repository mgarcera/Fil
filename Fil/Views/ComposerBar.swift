import SwiftUI
import PhotosUI
import UIKit

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
    /// In search mode the field IS the query: the capture icons hide, the placeholder changes, and
    /// the trailing button runs the search instead of sending a fil.
    var searchMode: Bool = false
    /// True once a search has run (results on screen) — the trailing button becomes "restart".
    var searchShowingResults: Bool = false
    /// Rotating search placeholders (empty → the static `searchPlaceholder`).
    var searchPrompts: [String] = []
    var searchPlaceholder: String = "search your thoughts"
    let onSend: () -> Void
    let onRecordVoice: () -> Void
    let onRemoveStagedImage: (Int) -> Void
    /// A photo captured with the camera (JPEG data) — staged like a picked photo.
    var onCapturePhoto: (Data) -> Void = { _ in }
    /// Enter search (resting trailing); run it (submit); restart it (refresh, on results); exit (X, empty).
    var onEnterSearch: () -> Void = {}
    var onSubmitSearch: () -> Void = {}
    var onRestartSearch: () -> Void = {}
    var onExitSearch: () -> Void = {}

    @State private var dissolvingText: String?
    @State private var showPhotoPicker = false   // the + menu's "Add photo" presents the picker
    @State private var showCamera = false         // the + menu's "Take a photo" presents the camera
    @FocusState private var focusedTodoID: UUID?

    private let placeholders = ["Tap to write", "Writing tip: your first line becomes the title."]
    private let placeholderInterval: TimeInterval = 10

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasText: Bool { !trimmedText.isEmpty }
    private var hasTodoContent: Bool { todos.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    /// A photo must carry a note — a captionless photo can't be sent, the same way an empty to-do
    /// row doesn't count. Text is always what unlocks send.
    private var canSend: Bool { hasText }
    /// Staged photos (or to-dos) keep the composer "composing" so the send button stays visible
    /// (dimmed) while the user types the required note, rather than falling back to the search glyph.
    private var isComposing: Bool { hasText || !stagedImageData.isEmpty || hasTodoContent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !searchMode && !stagedImageData.isEmpty { stagedImageRow }

            inputArea

            if !searchMode && !todos.isEmpty {
                Divider().overlay(Theme.divider).padding(.top, 2)
                todoRows
            }

            HStack(alignment: .center, spacing: 10) {
                // Capture controls (hidden in search mode): + is a menu (Record / Add a photo); the
                // to-do button sits beside it, always visible.
                if !searchMode {
                    Menu {
                        // Labels/icons/grouping mirror the filament sheet's add menu (KeywordAttachmentSheet).
                        Section {
                            Button { onRecordVoice() } label: { Label("Record", systemImage: "mic.fill") }
                        }
                        Section {
                            Button { showPhotoPicker = true } label: { Label("Add photo", systemImage: "photo") }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 56, height: 56).contentShape(Circle())
                    }
                    .disabled(isProcessing)
                    .accessibilityLabel("more capture options")

                    Button { addTodoPill() } label: {
                        captureIcon("checklist")
                    }
                    .buttonStyle(.plain).disabled(isProcessing).accessibilityLabel("add to-do")
                }

                Spacer(minLength: 0)

                // A manual keyboard dismiss, shown while the composer OR a to-do field is focused.
                if focus.wrappedValue || focusedTodoID != nil {
                    Button {
                        focus.wrappedValue = false
                        focusedTodoID = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 56, height: 56).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("dismiss keyboard")
                    .transition(.scale.combined(with: .opacity))
                }

                trailingButton
            }
        }
        // No glass here — the shared home dock wraps composer + baskets in one liquid-glass container.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos)
        .animation(.snappy(duration: 0.2), value: searchMode)
        .animation(.snappy(duration: 0.2), value: focus.wrappedValue)
        .animation(.snappy(duration: 0.2), value: focusedTodoID)
        .onChange(of: focusedTodoID) { oldValue, _ in removeRowIfEmpty(oldValue) }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 8, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) { onCapturePhoto(data) }
            }
            .ignoresSafeArea()
        }
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
                .font(Theme.fredoka(15, weight: .light)).foregroundStyle(Theme.secondaryText)
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


    /// A capture-option icon revealed under the + (matches the composer's 56pt icon buttons).
    private func captureIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 56, height: 56).contentShape(Circle())
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
                if searchMode {
                    if searchPrompts.isEmpty {
                        AnimatedGradientRevealText(text: searchPlaceholder, maxDuration: 1.2, settledOpacity: 0.4)
                            .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                            .allowsHitTesting(false)
                            .id(searchPlaceholder)
                    } else {
                        TimelineView(.periodic(from: .now, by: placeholderInterval)) { context in
                            let index = Int(context.date.timeIntervalSinceReferenceDate / placeholderInterval) % searchPrompts.count
                            AnimatedGradientRevealText(text: searchPrompts[index], maxDuration: 1.2, settledOpacity: 0.4)
                                .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                        }
                        .allowsHitTesting(false)
                    }
                } else if let contextLabel {
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
                .lineLimit(1...4).focused(focus).submitLabel(searchMode ? .search : .return)
                // Guard against an iOS 27 crash: the inline grammar/proofreading pass calls a
                // proofreading-shimmer selector on the vertical TextField's backing VerticalTextView that
                // it doesn't implement, terminating the app when typing longer, sentence-forming text.
                // Disabling Writing Tools keeps that path from ever running. Re-test on the iOS 27 GA seed.
                .writingToolsBehavior(.disabled)
                .opacity(dissolvingText == nil ? 1 : 0)
                // Return in the vertical field inserts a newline; in search treat it as "run search".
                .onChange(of: text) { _, newValue in
                    guard searchMode, newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    onSubmitSearch()
                }

            if let dissolvingText {
                GradientDissolveText(text: dissolvingText)
                    .font(Theme.fredoka(15, weight: .medium)).foregroundStyle(Theme.primaryText)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 8)
    }

    // Trailing action:
    //  • search mode → run the search (beamed arrow, when there's a query);
    //  • capture + composing → send;
    //  • capture + idle → enter search (a filled-circle magnifier where the mic used to be).
    @ViewBuilder private var trailingButton: some View {
        if searchMode {
            if !hasText {
                // Empty query → an X that leaves search (the old header "home" button).
                Button(action: onExitSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 56, height: 56)
                        .background(Theme.primaryText, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("close search")
            } else if searchShowingResults {
                // Results on screen → refresh restarts the search (fresh query).
                Button(action: onRestartSearch) {
                    beamedCircle(symbol: "arrow.clockwise", weight: .bold)
                }
                .buttonStyle(.plain).disabled(isProcessing).accessibilityLabel("new search")
            } else {
                Button(action: onSubmitSearch) {
                    beamedCircle(symbol: "arrow.up", weight: .bold)
                }
                .buttonStyle(.plain).disabled(isProcessing).accessibilityLabel("search")
            }
        } else if isComposing {
            Button(action: sendWithDissolve) {
                beamedCircle(symbol: "arrow.up", weight: .bold).opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain).disabled(isProcessing || !canSend).accessibilityLabel("send thought")
        } else {
            Button(action: onEnterSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 56, height: 56)
                    .background(Theme.primaryText, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("search your thoughts")
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
        // Hold the overlay until the dissolve actually finishes (scales with length), then clear it —
        // a fixed delay cut long notes off mid-animation.
        let hold = GradientDissolveText.completion(for: sent) + 0.05
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(hold))
            dissolvingText = nil
        }
    }

    private func beamedCircle(symbol: String, weight: Font.Weight) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: weight)).foregroundStyle(Theme.background)
            .frame(width: 56, height: 56)
            .background(Theme.primaryText, in: Circle())
    }

    private var stagedImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Key on the image data (stable per photo), not the index — otherwise removing one
                // shifts every later index and SwiftUI fades the last cell instead of scaling out
                // the one actually removed.
                ForEach(Array(stagedImageData.enumerated()), id: \.element) { index, data in
                    stagedImageThumbnail(data: data, index: index)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Padding so the (x) badge, which sits just outside each thumbnail's top-right corner,
            // isn't clipped by the ScrollView's bounds.
            .padding(.top, 8)
            .padding(.horizontal, 8)
        }
        .animation(.snappy(duration: 0.2), value: stagedImageData.count)
    }

    @ViewBuilder private func stagedImageThumbnail(data: Data, index: Int) -> some View {
        if let image = Image(data: data) {
            image.resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button { onRemoveStagedImage(index) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 18, height: 18).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain).offset(x: 6, y: -6).accessibilityLabel("remove photo")
                }
        }
    }
}
