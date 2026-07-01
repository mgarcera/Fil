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
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .reverse)]) private var userProfiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var allNotes: [Note]
    @State private var player = AudioPlayerViewModel()
    private let pinnedFilStore = PinnedFilStore.shared
    @State private var pinnedFil: PinnedFilSnapshot? = PinnedFilStore.shared.pinnedFil
    @State private var linkBrowserURL: URL?
    @State private var backlinkSheetDetent = PresentationDetent.fraction(0.6)
    @State private var backlinkNoteToOpen: Note?
    @State private var transcriptTextHeight: CGFloat = 100
    @State private var isEditingTranscript = false
    @State private var isDateMetadataExpanded = false
    @State private var titleDraftBaseline = ""
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

    private var activeUserProfile: UserProfile? {
        userProfiles.first
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

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: updateTitle
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

            if note.imageData == nil {
                CalibrateSheetBackground(
                    startColor: Color(hex: note.gradientStartHex),
                    endColor: Color(hex: note.gradientEndHex),
                    isLightMode: colorScheme == .light
                )
                .ignoresSafeArea()
            }

            if note.isLinkFil {
                linkFilContentView
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                                dateMetadata
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
        .toolbar(note.isLinkFil ? .hidden : .automatic, for: .navigationBar)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        togglePinnedFil()
                    } label: {
                        Image(systemName: isCurrentFilPinned ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(isCurrentFilPinned ? "Unpin fil" : "Pin fil")
                }
            }
        }
        .quickLookPreview($imagePreviewURL, in: imagePreviewURLs)
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
    private var dateMetadata: some View {
        Group {
            if isDateMetadataExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        SoundscapeManager.shared.playTabSound()
                        withAnimation(.snappy(duration: 0.18)) {
                            isDateMetadataExpanded = false
                        }
                    } label: {
                        Text(note.timestamp, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                            .font(Theme.dmMono(12))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide date metadata")

                    sourceTypeIndicator
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button {
                    SoundscapeManager.shared.playTabSound()
                    withAnimation(.snappy(duration: 0.18)) {
                        isDateMetadataExpanded = true
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show date metadata")
            }
        }
        .transition(.blurReplace)
        .animation(.snappy(duration: 0.18), value: isDateMetadataExpanded)
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

            let caption = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedPresentationDetent == .large, !caption.isEmpty {
                Text(caption)
                    .font(Theme.dmMono(13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var imageFilCarouselHeight: CGFloat {
        selectedPresentationDetent == .large ? 560 : 340
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
                Button {
                    linkBrowserURL = url
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(url.absoluteString)
                            .font(Theme.dmMono(12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Theme.background.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(Theme.divider.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open link")
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
        }
        .frame(maxWidth: .infinity)
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleView

                Spacer(minLength: 12)

                articleEditButton
            }

            transcriptSection

            if !note.todos.isEmpty {
                Divider()
                    .overlay(Theme.divider)
                    .padding(.top, 4)

                todoQuoteList
            }

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
        if threadContextTitle != nil {
            threadContextHeader
                .transition(.blurReplace)
        } else if isEditingTranscript {
            TextField("title", text: titleBinding, axis: .vertical)
                .font(Theme.dmMono(13))
                .foregroundStyle(Theme.primaryText)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.blurReplace)
        } else if !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(note.title)
                .font(Theme.dmSans(22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var transcriptSection: some View {
        Group {
            if isEditingTranscript {
                TextEditor(text: transcriptBinding)
                    .font(Theme.dmMono(13))
                    .foregroundStyle(Theme.secondaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220, alignment: .topLeading)
            } else {
                SelectableTextView(
                    text: note.transcript,
                    highlightedKeywords: note.attachments.map(\.keyword),
                    gradientStartHex: note.gradientStartHex,
                    gradientEndHex: note.gradientEndHex,
                    onSelectText: { selectedText, _ in
                        filSheetPath.append(.keyword(noteID: note.uuid, keyword: selectedText))
                    },
                    onTapHighlight: { keyword in
                        filSheetPath.append(.keyword(noteID: note.uuid, keyword: keyword))
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
        if note.audioFilePath.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                Text("typed entry")
                    .font(Theme.dmMono(12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        } else {
            PlaybackWaveformView(
                player: player,
                totalDuration: note.duration,
                showsPlayButton: hasAudioRecording
            )
        }
    }

    private var articleEditButton: some View {
        Button {
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
                titleDraftBaseline = note.title
                transcriptDraftBaseline = note.transcript
                withAnimation(.snappy(duration: 0.18)) {
                    isEditingTranscript = true
                }
            }
        } label: {
            Group {
                if isEditingTranscript {
                    Text("done")
                } else {
                    Text("edit")
                }
            }
            .transition(.blurReplace)
            .animation(.snappy(duration: 0.18), value: isEditingTranscript)
        }
        .font(Theme.dmMono(12))
        .foregroundStyle(Theme.secondaryText)
    }

    private func togglePinnedFil() {
        SoundscapeManager.shared.playTabSound()

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
    }

    @ViewBuilder
    private var todoQuoteList: some View {
        if !note.todos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(note.todos.enumerated()), id: \.offset) { index, todo in
                    Button {
                        toggleTodo(at: index)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            todoStatusCircle(isCompleted: isTodoCompleted(at: index))

                            Text(todo)
                                .font(Theme.dmMono(13))
                                .foregroundStyle(Theme.secondaryText)
                                .strikethrough(isTodoCompleted(at: index), color: Theme.tertiaryText)
                                .opacity(isTodoCompleted(at: index) ? 0.65 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private func todoStatusCircle(isCompleted: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isCompleted ? Theme.inactiveTabBackground.opacity(0.9) : Theme.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.tertiaryText.opacity(isCompleted ? 0.28 : 0.42), lineWidth: 1)
                }

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(width: 22, height: 22)
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
        try? modelContext.save()
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
        try? modelContext.save()
    }

    private func updateTitle(_ newValue: String) {
        guard newValue != note.title else { return }
        if note.originalTitle == nil {
            note.originalTitle = note.title
        }
        note.title = newValue
        try? modelContext.save()
    }

    @MainActor
    private func refreshMetadataFromTranscript() async {
        do {
            let metadata = try await ArticleGenerationService.shared.generateMetadata(
                from: note.transcript,
                userProfile: activeUserProfile
            )
            let previousTodoStates = Dictionary(uniqueKeysWithValues: zip(note.todos, note.completedTodos))
            note.keyword = metadata.keyword
            note.todos = metadata.todos
            note.completedTodos = metadata.todos.map { previousTodoStates[$0] ?? false }
            try? modelContext.save()
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
