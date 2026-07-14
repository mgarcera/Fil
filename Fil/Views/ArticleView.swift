import SwiftUI
import SwiftData
import QuickLook
#if canImport(UIKit)
import UIKit
#endif

enum FilSheetRoute: Hashable {
    case keyword(noteID: UUID, keyword: String)
    case linkedNote(UUID)
}

struct ArticleView: View {
    let note: Note
    let autoFocusEmptyTitle: Bool
    let backlinkContextNoteID: UUID?
    let threadContextKeyword: String?
    let threadContextParentTitle: String?
    let showsThreadedFilRows: Bool
    let ignoresTopSafeArea: Bool
    let topContentInset: CGFloat
    let showsCloseButton: Bool
    @Binding private var filSheetPath: [FilSheetRoute]
    @Binding private var selectedPresentationDetent: PresentationDetent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var allNotes: [Note]
    @AppStorage("prefersLowercase") private var prefersLowercase = false
    @State private var player = AudioPlayerViewModel()
    private let pinnedFilStore = PinnedFilStore.shared
    @State private var pinnedFil: PinnedFilSnapshot? = PinnedFilStore.shared.pinnedFil
    @State private var linkBrowserURL: URL?
    @State private var showLandfilConfirmation = false
    @State private var pendingLandfilTodo: ArticleTodoLandfil?
    @State private var backlinkSheetDetent = PresentationDetent.fraction(0.6)
    @State private var backlinkNoteToOpen: Note?
    /// True once the link description fetch has finished (found or not), so the "no description"
    /// line only shows after we've actually tried — never while still loading.
    @State private var descriptionFetchDone = false
    @State private var transcriptTextHeight: CGFloat = 100
    @State private var isEditingTranscript = false
    @State private var isAddingTodo = false
    @State private var newTodoText = ""
    @FocusState private var isTodoFieldFocused: Bool
    @State private var pinToastMessage: String?
    @State private var pinToastDismissTask: Task<Void, Never>?
    @State private var transcriptDraftBaseline = ""
    @State private var selectedImageFilIndex = 0
    @State private var imagePreviewURL: URL?
    @State private var imagePreviewURLs: [URL] = []

    init(
        note: Note,
        autoFocusEmptyTitle: Bool = false,
        backlinkContextNoteID: UUID? = nil,
        threadContextKeyword: String? = nil,
        threadContextParentTitle: String? = nil,
        showsThreadedFilRows: Bool = true,
        ignoresTopSafeArea: Bool = true,
        topContentInset: CGFloat = 0,
        showsCloseButton: Bool = false,
        filSheetPath: Binding<[FilSheetRoute]> = .constant([]),
        selectedPresentationDetent: Binding<PresentationDetent> = .constant(.fraction(0.6))
    ) {
        self.note = note
        self.autoFocusEmptyTitle = autoFocusEmptyTitle
        self.backlinkContextNoteID = backlinkContextNoteID
        self.threadContextKeyword = threadContextKeyword
        self.threadContextParentTitle = threadContextParentTitle
        self.showsThreadedFilRows = showsThreadedFilRows
        self.ignoresTopSafeArea = ignoresTopSafeArea
        self.topContentInset = topContentInset
        self.showsCloseButton = showsCloseButton
        self._filSheetPath = filSheetPath
        self._selectedPresentationDetent = selectedPresentationDetent
    }

    private var hasAudioRecording: Bool {
        AudioPlayerViewModel.hasAudioFile(for: note.audioFilePath)
    }

    private var isTranscriptEdited: Bool {
        guard let originalTranscript = note.originalTranscript else { return false }
        return originalTranscript != note.transcript
    }

    private var isCurrentFilPinned: Bool {
        pinnedFil?.id == note.uuid
    }

    private var transcriptBinding: Binding<String> {
        Binding(
            get: { note.transcript },
            set: updateTranscript
        )
    }

    private var threadContextTitle: String? {
        threadContextKeyword?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var threadContextSubtitle: String? {
        threadContextParentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            // The blurred backdrop (~18 circles) and top-edge glow (3 blurred strokes) each
            // take part in layout on every frame of the detent resize — the lag we isolated.
            // Rasterizing them to a single static image once, then stretching that one image
            // as the sheet grows, collapses them to a single cheap layer. The heavy blur
            // hides the stretch, so the look is preserved.
            StaticBlurBackdrop(colorScheme: colorScheme, contentID: note.uuid) {
                ZStack {
                    if note.imageData == nil {
                        CalibrateSheetBackground(
                            startColor: Color(hex: note.gradientStartHex),
                            endColor: Color(hex: note.gradientEndHex),
                            isLightMode: colorScheme == .light
                        )
                    }

                    FilrTopEdgeGlow(
                        startColor: Color(hex: note.gradientStartHex),
                        endColor: Color(hex: note.gradientEndHex)
                    )
                }
            }
            .ignoresSafeArea()

            if note.isLinkFil {
                linkFilContentView
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    // Pinned to the top; the sticky open button lives at the bottom.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .bottom) {
                        if note.sourceURL != nil {
                            openLinkButton
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }
                    }
                    // Backfill the description for links made before this existed (or that failed the
                    // first fetch). Mark done either way so the "no description" line can show.
                    .task(id: note.uuid) {
                        if (note.sourceDescription?.isEmpty ?? true), let url = note.sourceURL {
                            if let description = await LinkFil.fetchDescription(for: url) {
                                note.sourceDescription = description
                                modelContext.saveOrLog()
                            }
                        }
                        descriptionFetchDone = true
                    }
            } else {
                ScrollView {
                    if topContentInset > 0 {
                        Color.clear
                            .frame(height: topContentInset)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        heroImage

                        VStack(alignment: .leading, spacing: 16) {
                            if !note.isImageFil || selectedPresentationDetent == .large {
                                sourceTypeIndicator
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if note.isImageFil {
                                imageFilContentView
                            } else {
                                articleContentView
                            }
                        }
                        .padding(16)
                    }
                }
            }

        }
        .ignoresSafeArea(edges: ignoresTopSafeArea ? .top : [])
        .overlay(alignment: .topTrailing) {
            pinToast
        }
        // Hide the nav bar only for a *root* link fil (it has its own open + swipe-to-dismiss). A
        // link fil pushed inside the filament stack keeps its bar, so there's a back button.
        .toolbar(note.isLinkFil && filSheetPath.isEmpty ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            normalizeTodoCompletionStates()
            if hasAudioRecording {
                player.load(path: note.audioFilePath)
            }
        }
        .onDisappear { player.stop() }
        .toolbar {
            if showsCloseButton && !note.isLinkFil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close fil")
                }
            }

            if !note.isLinkFil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            togglePinnedFil()
                        } label: {
                            Label(isCurrentFilPinned ? "unpin from lock screen" : "pin to lock screen",
                                  systemImage: isCurrentFilPinned ? "pin.slash" : "pin")
                        }

                        ShareLink(item: filShareCard, preview: SharePreview("a fil from fil")) {
                            Label("share", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showLandfilConfirmation = true
                        } label: {
                            Label("landfil", systemImage: "trash")
                        }

                        Section("created") {
                            Text(note.timestamp, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("more")

                    Button {
                        toggleEditing()
                    } label: {
                        Image(systemName: isEditingTranscript ? "checkmark" : "pencil")
                    }
                    .accessibilityLabel(isEditingTranscript ? "Finish editing" : "Edit fil")
                }
            }
        }
        .quickLookPreview($imagePreviewURL, in: imagePreviewURLs)
        .alert("move to landfil?", isPresented: $showLandfilConfirmation) {
            Button("landfil", role: .destructive) { landfilFil() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("this fil will be deleted. this cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { linkBrowserURL != nil },
            set: { if !$0 { linkBrowserURL = nil } }
        )) {
            if let linkBrowserURL {
                InAppBrowserView(url: linkBrowserURL)
                    .presentationBackground(Theme.background)
            }
        }
        .sheet(item: $backlinkNoteToOpen) { linkedParent in
            NavigationStack {
                ArticleView(note: linkedParent)
            }
            .presentationDetents([.fraction(0.6)], selection: $backlinkSheetDetent)
            .presentationBackground(Theme.background)
        }
    }

    private var backlinkParentNote: Note? {
        backlinkParent?.note
    }

    private var backlinkParent: (note: Note, keyword: String)? {
        for backlink in note.threadedBacklinks {
            guard let uuid = UUID(uuidString: backlink.parentNoteID),
                  let parent = allNotes.first(where: { $0.uuid == uuid }) else {
                continue
            }
            let keyword = backlink.parentKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            return (parent, keyword.isEmpty ? "threaded fil" : keyword)
        }
        return nil
    }

    @ViewBuilder
    private var pinToast: some View {
        if let pinToastMessage {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(pinToastMessage)
                    .font(Theme.dmSans(12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassEffect(.regular, in: .capsule)
            .contentShape(Capsule())
            .padding(.top, 8)
            .padding(.trailing, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var heroImage: some View {
        Group {
            if let imageData = note.imageData, let image = Image(data: imageData) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 75)
                    .clipped()
            } else {
                Color.clear
                    .frame(height: note.isLinkFil ? 0 : 18)
            }
        }
        .frame(height: note.imageData == nil ? (note.isLinkFil ? 0 : 18) : 75)
    }

    private var imageFilContentView: some View {
        VStack(alignment: .leading, spacing: 14) {
            let images = note.sortedImageFilImages

            if !images.isEmpty {
                TabView(selection: $selectedImageFilIndex) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, noteImage in
                        if let uiImage = UIImage(data: noteImage.data) {
                            Button {
                                openImageFilPreview(selectedIndex: index)
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .tag(index)
                        }
                    }
                }
                .frame(height: imageFilCarouselHeight)
                .tabViewStyle(.page(indexDisplayMode: .never))

                if images.count > 1 {
                    Text("\(selectedImageFilIndex + 1) / \(images.count)")
                        .font(Theme.dmMono(11))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.cardBackground.opacity(0.82), in: Capsule())
                        .overlay(Capsule().stroke(Theme.divider.opacity(0.6), lineWidth: 1))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // Caption sits directly under the photo(s), always visible (not gated on the detent).
            let caption = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !caption.isEmpty {
                Text(caption)
                    .font(Theme.dmMono(13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // To-dos (and the add control) surface only at the full detent, so the compact
            // image view stays clean.
            if selectedPresentationDetent == .large {
                if !note.todos.isEmpty {
                    todoQuoteList
                }

                addTodoControl
            }
        }
    }

    private var imageFilCarouselHeight: CGFloat {
        // Expand the photo on the full detent; compact stays a peek with the caption below it.
        selectedPresentationDetent == .large ? 640 : 340
    }

    private func openImageFilPreview(selectedIndex: Int) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fil-image-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let urls = note.sortedImageFilImages.enumerated().compactMap { index, noteImage -> URL? in
            let url = tempDir.appendingPathComponent("image-fil-\(note.uuid.uuidString)-\(index).jpg")
            guard (try? noteImage.data.write(to: url)) != nil else { return nil }
            return url
        }

        imagePreviewURLs = urls
        if urls.indices.contains(selectedIndex) {
            imagePreviewURL = urls[selectedIndex]
        }
    }

    private var linkFilContentView: some View {
        VStack(spacing: 16) {
            if let url = note.sourceURL {
                // The URL, display-only — opening is the "open" button below (tap or swipe up).
                HStack(spacing: 9) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(url.absoluteString)
                        .font(Theme.dmMono(12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Theme.background.opacity(0.72), in: Capsule())
                .overlay(Capsule().stroke(Theme.divider.opacity(0.55), lineWidth: 1))
            }

            HStack(alignment: .center, spacing: 12) {
                linkIcon

                Text(linkDisplayTitle)
                    .font(Theme.dmSans(16, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The page's description (fetched in the background), filling the space below the title.
            if let description = note.sourceDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(Theme.dmSans(15, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if descriptionFetchDone {
                Text("can't get a description from this page. must be interesting.")
                    .font(Theme.dmSans(15, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens the in-app browser. Tap or a deliberate swipe up both open it — the browser sheet then
    /// slides up, so the upward gesture and the sheet's motion read as one continuous action.
    private var openLinkButton: some View {
        Button { openLink() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("open")
                    .font(Theme.dmSans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open link")
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    // Commit on a deliberate upward drag or a quick upward flick (same action as tap).
                    let up = value.translation.height < -30 || value.velocity.height < -500
                    if up { openLink() }
                }
        )
    }

    private func openLink() {
        guard let url = note.sourceURL else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        linkBrowserURL = url
    }

    private var linkDisplayTitle: String {
        let sourceTitle = note.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sourceTitle.isEmpty {
            return sourceTitle
        }

        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return note.sourceDomain ?? "link"
    }

    @ViewBuilder
    private var linkIcon: some View {
        if let data = note.sourceFaviconData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 54, height: 54)
                .background(Theme.cardBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var articleContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleView

            transcriptSection

            if !note.todos.isEmpty {
                todoQuoteList
            }

            addTodoControl

            if showsThreadedFilRows, backlinkParentNote != nil {
                Divider()
                    .overlay(Theme.divider)
                    .padding(.top, 4)

                threadedFilRows
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        // The card badge is the fil's title/identity and is generated from the
        // transcript — it isn't directly editable. Only threaded fils show a
        // header here (their parent context).
        if threadContextTitle != nil {
            threadContextHeader
                .transition(.blurReplace)
        }
    }

    private var threadContextHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(threadContextTitle ?? "")
                .font(Theme.dmSans(22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let threadContextSubtitle {
                Text("from \(threadContextSubtitle)")
                    .font(Theme.dmMono(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // When editing, let the text area grow to fill the larger detent. Derived
    // from the discrete detent (not per-frame geometry) so it doesn't re-evaluate
    // this shader-heavy body during the sheet's resize animation.
    private var editingTranscriptMinHeight: CGFloat {
        selectedPresentationDetent == .large ? 560 : 220
    }

    private var transcriptSection: some View {
        Group {
            if isEditingTranscript {
                // Match the reading view (SelectableTextView) exactly so text doesn't shift when
                // toggling edit: system font, body-relative 16pt, label @0.85, 6pt line spacing.
                TextEditor(text: transcriptBinding)
                    .font(Theme.dmSans(16))
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    // Cancel TextEditor's built-in ~5pt lineFragmentPadding so the text left-aligns
                    // with the zero-inset reading view (no horizontal shift on toggling edit).
                    .padding(.horizontal, -5)
                    .frame(minHeight: editingTranscriptMinHeight, alignment: .topLeading)
            } else {
                SelectableTextView(
                    text: prefersLowercase ? note.transcript.lowercased() : note.transcript,
                    highlightedKeywords: note.attachments.map(\.keyword),
                    gradientStartHex: note.gradientStartHex,
                    gradientEndHex: note.gradientEndHex,
                    onSelectText: { selectedText, _ in
                        filSheetPath.append(.keyword(noteID: note.uuid, keyword: selectedText))
                    },
                    onTapHighlight: { keyword in
                        filSheetPath.append(.keyword(noteID: note.uuid, keyword: keyword))
                    },
                    onMakeTodo: { selectedText in
                        makeTodo(from: selectedText)
                    },
                    height: $transcriptTextHeight
                )
                .frame(height: transcriptTextHeight)
            }
        }
            .transition(.blurReplace)
            .animation(.snappy(duration: 0.18), value: isEditingTranscript)
    }

    @ViewBuilder
    private var threadedFilRows: some View {
        if let backlinkParent {
            linkedFilRow(backlinkParent.note, title: backlinkParent.keyword)
        }
    }

    private func linkedFilRow(_ parent: Note, title: String) -> some View {
        Button {
            SoundscapeManager.shared.playOpenFilClick()
            if backlinkContextNoteID == parent.uuid {
                dismiss()
            } else {
                backlinkNoteToOpen = parent
            }
        } label: {
            HStack(spacing: 10) {
                ArticleBacklinkBlobShape(seed: parent.backlinkBlobSeed)
                    .fill(Theme.gradient(startHex: parent.gradientStartHex, endHex: parent.gradientEndHex))
                    .frame(width: 30, height: 30)

                Text(title)
                    .font(Theme.dmSans(14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open linked fil")
    }

    @ViewBuilder
    private var sourceTypeIndicator: some View {
        if !note.audioFilePath.isEmpty {
            PlaybackWaveformView(
                player: player,
                totalDuration: note.duration,
                showsPlayButton: hasAudioRecording
            )
        }
    }

    private func toggleEditing() {
        SoundscapeManager.shared.playTabSound()
        if isEditingTranscript {
            let shouldRefreshMetadata = note.transcript != transcriptDraftBaseline
            withAnimation(.snappy(duration: 0.18)) {
                isEditingTranscript = false
            }
            if shouldRefreshMetadata {
                Task { await refreshMetadataFromTranscript() }
            }
        } else {
            transcriptDraftBaseline = note.transcript
            withAnimation(.snappy(duration: 0.18)) {
                isEditingTranscript = true
            }
        }
    }

    /// The fil rendered as a shareable branded card. Cheap to build (value copy); the bitmap is
    /// only produced when the user actually picks a share destination.
    private var filShareCard: FilShareCardData {
        let title = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return FilShareCardData(
            title: title.isEmpty ? "fil" : title,
            excerpt: String(transcript.prefix(160)),
            startHex: note.gradientStartHex,
            endHex: note.gradientEndHex,
            seed: note.blobShapeSeed
        )
    }

    private func togglePinnedFil() {
        SoundscapeManager.shared.playTabSound()

        let willPin = !isCurrentFilPinned
        if isCurrentFilPinned {
            pinnedFilStore.unpin()
            Task {
                await PinnedFilLiveActivityController.unpin()
            }
        } else {
            let snapshot = pinnedFilStore.pin(note)
            Task {
                await PinnedFilLiveActivityController.pin(snapshot)
            }
        }

        withAnimation(.snappy(duration: 0.18)) {
            pinnedFil = pinnedFilStore.pinnedFil
        }

        showPinToast(willPin ? "pinned to live activity" : "unpinned from live activity")
    }

    private func showPinToast(_ message: String) {
        pinToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            pinToastMessage = message
        }
        pinToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                pinToastMessage = nil
            }
        }
    }

    @ViewBuilder
    private var todoQuoteList: some View {
        if !note.todos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Stable identity (from Note.todoIDs) so removal animations track the right row.
                // Long-press a to-do to landfil it.
                ForEach(note.todoRowItems) { item in
                    TodoRowContent(text: item.text, isCompleted: item.done) {
                        toggleTodo(at: item.index)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingLandfilTodo = ArticleTodoLandfil(index: item.index, text: item.text)
                        } label: {
                            Label("landfil", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 2)
            .padding(.leading, 20)
            .landfilConfirmation(item: $pendingLandfilTodo) { pending in
                "“\(pending.text)” will be deleted. this cannot be undone."
            } onConfirm: { pending in
                removeTodo(at: pending.index)
            }
        }
    }

    /// The always-available control for adding a to-do to this fil. Shows a compact
    /// "+ to-do" button that expands into an inline field. Kept low-emphasis — Fil isn't a
    /// to-do app, action items are just one kind of thought that lands in it.
    @ViewBuilder
    private var addTodoControl: some View {
        Group {
            if isAddingTodo {
                HStack(alignment: .center, spacing: 12) {
                    TodoStatusCircle(isCompleted: false)

                    TextField("to do", text: $newTodoText)
                        .font(Theme.dmSans(16))
                        .foregroundStyle(Theme.secondaryText)
                        .focused($isTodoFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { commitNewTodo() }

                    Button(action: commitNewTodo) {
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            } else {
                Button(action: startAddingTodo) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("to do")
                            .font(Theme.dmSans(16))
                    }
                    .foregroundStyle(Theme.tertiaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.leading, 20)
    }

    private func startAddingTodo() {
        newTodoText = ""
        withAnimation(.snappy(duration: 0.18)) { isAddingTodo = true }
        isTodoFieldFocused = true
    }

    /// Commits the field as a to-do. A non-empty entry stays in add mode for rapid entry;
    /// submitting an empty field exits.
    private func commitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation(.snappy(duration: 0.18)) { isAddingTodo = false }
            isTodoFieldFocused = false
            return
        }
        note.addTodo(trimmed)
        modelContext.saveOrLog()
        SoundscapeManager.shared.playTodoArticleToggleSound()
        newTodoText = ""
        isTodoFieldFocused = true
    }

    private func removeTodo(at index: Int) {
        SoundscapeManager.shared.playTodoArticleToggleSound()
        note.removeTodo(at: index)
        modelContext.saveOrLog()
    }

    /// Deletes the whole fil (from the ⋯ menu). Dismisses first so the view isn't rendering a
    /// deleted model, then removes its audio + the record — mirroring the home grid's landfil.
    private func landfilFil() {
        SoundscapeManager.shared.playLandfilSound()
        let noteToDelete = note
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            FilLandfil.cleanUpResources(for: noteToDelete)
            modelContext.delete(noteToDelete)
            modelContext.saveOrLog()
        }
    }

    /// Promotes arbitrary text (e.g. a selection from the transcript) into a to-do. This is
    /// how voice fils and anything missed at capture get action items after the fact.
    private func makeTodo(from text: String) {
        note.addTodo(text)
        modelContext.saveOrLog()
        SoundscapeManager.shared.playTodoArticleToggleSound()
    }

    private func isTodoCompleted(at index: Int) -> Bool {
        guard note.completedTodos.indices.contains(index) else { return false }
        return note.completedTodos[index]
    }

    private func toggleTodo(at index: Int) {
        normalizeTodoCompletionStates()
        guard note.completedTodos.indices.contains(index) else { return }
        SoundscapeManager.shared.playTodoArticleToggleSound()
        note.completedTodos[index].toggle()
        modelContext.saveOrLog()
    }

    private func normalizeTodoCompletionStates() {
        if note.completedTodos.count < note.todos.count {
            note.completedTodos.append(contentsOf: Array(repeating: false, count: note.todos.count - note.completedTodos.count))
        } else if note.completedTodos.count > note.todos.count {
            note.completedTodos = Array(note.completedTodos.prefix(note.todos.count))
        }
    }

    private func updateTranscript(_ newValue: String) {
        guard newValue != note.transcript else { return }
        if note.originalTranscript == nil {
            note.originalTranscript = note.transcript
        }
        note.transcript = newValue
        modelContext.saveOrLog()
    }

    @MainActor
    private func refreshMetadataFromTranscript() async {
        // Drives the badge's "thinking" blur; cleared once the new title is in place,
        // which triggers its gradient reveal out of that blur.
        TitleRegenerationTracker.shared.begin(note.uuid)
        defer { TitleRegenerationTracker.shared.end(note.uuid) }
        do {
            // Only the title is regenerated from the edited transcript. To-dos are never
            // auto-extracted — they're created and edited explicitly by the user.
            let metadata = try await ArticleGenerationService.shared.generateMetadata(
                from: note.transcript
            )
            note.keyword = metadata.keyword
            note.title = metadata.keyword
            modelContext.saveOrLog()
        } catch {
            // Keep transcript edits even if metadata refresh fails.
        }
    }
}

private struct CalibrateStageBackdrop: View {
    let startColor: Color
    let endColor: Color
    let isGenerating: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(startColor.opacity(isGenerating ? 0.24 : 0.16))
                .frame(width: isGenerating ? 180 : 150, height: isGenerating ? 180 : 150)
                .blur(radius: isGenerating ? 44 : 34)
                .offset(x: -54, y: -58)
                .animation(.easeInOut(duration: 1.2), value: isGenerating)

            Circle()
                .fill(endColor.opacity(isGenerating ? 0.22 : 0.14))
                .frame(width: isGenerating ? 190 : 160, height: isGenerating ? 190 : 160)
                .blur(radius: isGenerating ? 46 : 36)
                .offset(x: 126, y: -12)
                .animation(.easeInOut(duration: 1.1), value: isGenerating)

            Circle()
                .fill(startColor.mix(with: endColor, by: 0.5).opacity(isGenerating ? 0.2 : 0.12))
                .frame(width: isGenerating ? 220 : 180, height: isGenerating ? 220 : 180)
                .blur(radius: isGenerating ? 48 : 38)
                .offset(x: 40, y: 114)
                .animation(.easeInOut(duration: 1.3), value: isGenerating)
        }
        .frame(height: 240)
        .allowsHitTesting(false)
    }
}

private struct ArticleBacklinkBlobShape: Shape {
    let seed: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = 5 + Int(seed * 4.999)
        let amplitude = CGFloat(0.055 + (seed * 0.055))
        let secondaryFrequency = CGFloat(2 + Int(Self.unitNoise(seed, salt: 17) * 4))
        let tertiaryFrequency = CGFloat(3 + Int(Self.unitNoise(seed, salt: 23) * 4))
        let phaseA = CGFloat(seed * .pi * 2)
        let phaseB = CGFloat((1 - seed) * .pi * 2)
        let rotation = CGFloat((Self.unitNoise(seed, salt: 29) - 0.5) * 0.7)
        let asymmetryPhase = CGFloat(Self.unitNoise(seed, salt: 37) * .pi * 2)
        let asymmetryStrength = CGFloat((Self.unitNoise(seed, salt: 41) - 0.5) * 0.18)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.46
        let radiusY = rect.height * 0.42
        let blobPoints = (0..<points).map { index in
            let angle = (CGFloat(index) / CGFloat(points) * .pi * 2) + rotation
            let pointOffset = CGFloat((Self.unitNoise(seed, salt: Double(index) + 101) - 0.5) * 0.22)
            let waveOffset = (
                sin(angle * secondaryFrequency + phaseA) * 0.65
                + sin(angle * tertiaryFrequency + phaseB) * 0.45
            ) * amplitude
            let asymmetryOffset = cos(angle + asymmetryPhase) * asymmetryStrength
            let radiusMultiplier = max(0.72, 1 + pointOffset + waveOffset + asymmetryOffset)
            return CGPoint(
                x: center.x + cos(angle) * radiusX * radiusMultiplier,
                y: center.y + sin(angle) * radiusY * radiusMultiplier
            )
        }

        guard let firstPoint = blobPoints.first else { return path }
        path.move(to: firstPoint)

        for index in 0..<points {
            let current = blobPoints[index]
            let next = blobPoints[(index + 1) % points]
            let previous = blobPoints[(index - 1 + points) % points]
            let following = blobPoints[(index + 2) % points]
            path.addCurve(
                to: next,
                control1: CGPoint(
                    x: current.x + (next.x - previous.x) * 0.2,
                    y: current.y + (next.y - previous.y) * 0.2
                ),
                control2: CGPoint(
                    x: next.x - (following.x - current.x) * 0.2,
                    y: next.y - (following.y - current.y) * 0.2
                )
            )
        }

        path.closeSubpath()
        return path
    }

    private static func unitNoise(_ seed: Double, salt: Double) -> Double {
        let value = sin((seed + 0.137) * (salt + 12.9898) * 78.233) * 43758.5453
        return value - floor(value)
    }
}

private extension Note {
    var backlinkBlobSeed: Double {
        let scalars = uuid.uuidString.unicodeScalars
        let hash = scalars.reduce(UInt32(2166136261)) { partial, scalar in
            (partial ^ scalar.value) &* 16777619
        }
        return Double(hash % 10_000) / 10_000
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Renders an expensive, decorative (static-color) view once into a bitmap and displays
/// that bitmap stretched to fill. Because the snapshot is a single layer, resizing the
/// container (e.g. a sheet animating between detents) just stretches one texture instead
/// of re-laying-out and re-blurring the original view tree every frame. The snapshot is
/// taken at the first non-zero size and re-taken only if the width changes (rotation).
/// A to-do pending landfil confirmation in the article view (identity for the shared alert).
private struct ArticleTodoLandfil: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
}

private struct CalibrateSheetBackground: View {
    let startColor: Color
    let endColor: Color
    let isLightMode: Bool

    private func adjustedOpacity(_ value: Double) -> Double {
        isLightMode ? min(value * 1.35, 1.0) : value
    }

    var body: some View {
        ZStack {
            Theme.background

            CalibrateStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.5)
            .offset(y: 250)
            .opacity(adjustedOpacity(0.95))

            CalibrateStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.15)
            .offset(x: 70, y: 160)
            .opacity(adjustedOpacity(0.55))

            CalibrateStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.05)
            .offset(x: -90, y: 210)
            .opacity(adjustedOpacity(0.4))

            CalibrateStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(0.9)
            .offset(x: 150, y: 120)
            .opacity(adjustedOpacity(0.42))

            CalibrateStageBackdrop(
                startColor: startColor.mix(with: endColor, by: 0.55),
                endColor: endColor.mix(with: startColor, by: 0.2),
                isGenerating: false
            )
            .scaleEffect(0.75)
            .offset(x: 120, y: 90)
            .opacity(adjustedOpacity(0.34))

            CalibrateStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(0.95)
            .offset(x: -140, y: 240)
            .opacity(adjustedOpacity(0.4))
        }
    }
}
