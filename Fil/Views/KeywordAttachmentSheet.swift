import SwiftUI
import SwiftData
import PhotosUI
import LinkPresentation
import QuickLook
import SafariServices
import UniformTypeIdentifiers
import AVFoundation
import CoreTransferable

struct KeywordPopup: View {
    private static let linkCaptionLimit = 15

    private struct LinkEditorState {
        enum Mode {
            case add
            case edit(UUID)
        }

        let mode: Mode
        var url: String
        var caption: String

        var title: String {
            switch mode {
            case .add:
                "Add URL"
            case .edit:
                "Edit URL"
            }
        }

        var message: String? {
            switch mode {
            case .add:
                nil
            case .edit:
                "Update the URL or caption for this attachment."
            }
        }
    }

    let note: Note
    let keyword: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var allNotes: [Note]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var videoPickerPresented = false
    @State private var showVideoCamera = false
    @State private var videoThumbnails: [UUID: UIImage] = [:]
    @State private var linkEditor: LinkEditorState?
    @State private var linkEditorDetent = PresentationDetent.fraction(0.6)
    @State private var noteEditorDetent = PresentationDetent.large
    @State private var favicons: [UUID: UIImage] = [:]
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var inAppBrowserURL: URL?
    @State private var editingNoteID: UUID?
    @State private var photoPickerPresented = false
    @State private var draggingID: UUID?
    @State private var dragSnapshot: [UUID] = []
    @State private var didCompleteDrop = false
    @State private var showNotePicker = false
    @State private var showFilLinkPicker = false
    @State private var showCamera = false
    @State private var showPDFImporter = false
    @State private var recordingEntryID: UUID?
    @State private var memoRecorder: AVAudioRecorder?
    @State private var memoTimer: Timer?
    @State private var memoDuration: TimeInterval = 0
    @State private var pendingLandfilEntryID: UUID?

    private var attachment: KeywordAttachment? {
        note.attachments.first { $0.keyword == keyword }
    }

    private let maxSlots = 32
    private let cornerRadius: CGFloat = 30
    /// Matches CanvasHome.gridBlobSize so the link picker's blobs are the same size as search blobs.
    private let linkPickerBlobSize: CGFloat = 150
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            // Same backdrop as the parent fil (article view): the colored gradient wash plus the
            // top-edge glow, in the parent note's colors — rasterized to one static image so a
            // 0.6 → full detent drag stretches a single cheap layer instead of re-laying-out the
            // blurred circles/strokes each frame.
            StaticBlurBackdrop(colorScheme: colorScheme, contentID: note.uuid) {
                ZStack {
                    FilrSheetBackground(
                        startColor: Color(hex: note.gradientStartHex),
                        endColor: Color(hex: note.gradientEndHex),
                        isLightMode: colorScheme == .light
                    )

                    FilrTopEdgeGlow(
                        startColor: Color(hex: note.gradientStartHex),
                        endColor: Color(hex: note.gradientEndHex)
                    )
                }
            }
            .ignoresSafeArea()

            ScrollView {
                Color.clear
                    .frame(height: 8)

                LazyVGrid(columns: columns, spacing: 8) {
                    let entries = attachment?.entries ?? []
                    ForEach(entries, id: \.id) { entry in
                        entryView(entry)
                            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: cornerRadius))
                            .draggable(makeDragItem(for: entry.id))
                            .dropDestination(for: AttachmentDragItem.self) { items, _ in
                                handleDrop(items, targetID: entry.id)
                            } isTargeted: { isTargeted in
                                guard isTargeted else { return }
                                updateDropTarget(entry.id)
                            }
                    }

                    let emptyCount = max(0, maxSlots - entries.count)
                    ForEach(0..<emptyCount, id: \.self) { _ in
                        addButton
                    }
                }
                .padding(16)
                .dropDestination(for: AttachmentDragItem.self) { items, _ in
                    handleDrop(items, targetID: nil)
                } isTargeted: { isTargeted in
                    if !isTargeted {
                        finalizeDragIfNeeded(committed: didCompleteDrop)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SoundscapeManager.shared.playGridSound()
            for entry in attachment?.entries ?? [] where entry.kind == .link {
                if let data = entry.faviconData, let img = UIImage(data: data) {
                    favicons[entry.id] = img
                } else if entry.text != nil {
                    fetchFavicon(for: entry)
                }
            }
        }
        .onChange(of: selectedPhoto) {
            guard let selectedPhoto else { return }
            Task {
                if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                    appendEntry(.image(data))
                }
                self.selectedPhoto = nil
            }
        }
        .onChange(of: linkEditor?.caption) { _, newValue in
            guard let newValue, newValue.count > Self.linkCaptionLimit else { return }
            linkEditor?.caption = String(newValue.prefix(Self.linkCaptionLimit))
        }
        .sheet(isPresented: Binding(
            get: { linkEditor != nil },
            set: { if !$0 { clearLinkEditor() } }
        )) {
            if let linkEditor {
                LinkEditorSheet(
                    title: linkEditor.title,
                    url: linkURLBinding,
                    caption: linkCaptionBinding,
                    onSave: saveLinkEditor,
                    onCancel: clearLinkEditor
                )
                .presentationDetents([.fraction(0.6)], selection: $linkEditorDetent)
                .presentationBackground(Theme.background)
            }
        }
        .alert("Move to landfil?", isPresented: Binding(
            get: { pendingLandfilEntryID != nil },
            set: { if !$0 { pendingLandfilEntryID = nil } }
        )) {
            Button("Landfil", role: .destructive) {
                confirmLandfilEntry()
            }
            Button("Cancel", role: .cancel) {
                pendingLandfilEntryID = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $selectedPhoto, matching: .images)
        .photosPicker(isPresented: $videoPickerPresented, selection: $selectedVideo, matching: .videos)
        .onChange(of: selectedVideo) { _, newValue in
            guard let newValue else { return }
            importVideo(newValue)
        }
        .quickLookPreview($previewURL, in: previewURLs)
        .sheet(isPresented: Binding(
            get: { inAppBrowserURL != nil },
            set: { if !$0 { inAppBrowserURL = nil } }
        )) {
            if let url = inAppBrowserURL {
                InAppBrowserView(url: url)
                    .presentationBackground(Theme.background)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingNoteID != nil },
            set: { if !$0 { editingNoteID = nil } }
        )) {
            if let id = editingNoteID,
               let idx = attachment?.entries.firstIndex(where: { $0.id == id }) {
                NoteEditorSheet(
                    title: Binding(
                        get: { attachment?.entries[idx].noteTitle ?? "" },
                        set: { attachment?.entries[idx].noteTitle = $0 }
                    ),
                    text: Binding(
                        get: { attachment?.entries[idx].text ?? "" },
                        set: { attachment?.entries[idx].text = $0 }
                    )
                )
                .presentationDetents([.large], selection: $noteEditorDetent)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let att = findOrCreate()
                    att.entries.append(.image(data))
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showVideoCamera) {
            CameraVideoPicker { url in
                saveImportedVideo(from: url)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    appendEntry(.pdf(data: data, name: url.lastPathComponent))
                }
            }
        }
        .sheet(isPresented: $showFilLinkPicker) {
            filLinkPickerSheet
        }
    }

    /// "link a thought": pick another fil to link, shown as blobs (the same NoteCardView component
    /// as the search grid) rather than a menu of titles.
    private var filLinkPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 24) {
                    ForEach(otherNotes) { otherNote in
                        Button {
                            appendLinkedNote(otherNote)
                            showFilLinkPicker = false
                        } label: {
                            VStack(spacing: 10) {
                                NoteCardView(note: otherNote, cardHeight: linkPickerBlobSize)
                                    .frame(width: linkPickerBlobSize, height: linkPickerBlobSize)
                                    .frame(maxWidth: .infinity)
                                filLinkTitle(otherNote)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Link a thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFilLinkPicker = false }
                }
            }
        }
        .presentationDetents([.large, .fraction(0.6)])
        .presentationBackground(Theme.background)
    }

    /// Fil title under a picker blob, styled like the search grid: a one-line title centers, a title
    /// that wraps to 2+ lines left-aligns (ViewThatFits, no manual line counting).
    private func filLinkTitle(_ note: Note) -> some View {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "fil" : trimmed
        return ViewThatFits(in: .horizontal) {
            Text(label)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(label)
                .multilineTextAlignment(.leading)
                .frame(width: linkPickerBlobSize, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.dmSans(15, weight: .medium))
        .foregroundStyle(Theme.primaryText)
        .frame(width: linkPickerBlobSize)
    }

    // MARK: - Entry Views

    @ViewBuilder
    private func entryView(_ entry: AttachmentEntry) -> some View {
        switch entry.kind {
        case .image:
            imageView(entry)
        case .recording:
            voiceMemoView(entry)
        case .link:
            linkView(entry)
        case .textNote:
            noteView(entry)
        case .linkedNote:
            linkedNoteView(entry)
        case .pdf:
            pdfView(entry)
        case .video:
            videoView(entry)
        }
    }

    private func videoView(_ entry: AttachmentEntry) -> some View {
        Button {
            openVideoPreview(for: entry)
        } label: {
            VideoAttachmentTile(thumbnail: videoThumbnails[entry.id], cornerRadius: cornerRadius)
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .task { loadThumbnail(for: entry) }
        .contextMenu {
            landfilButton(for: entry.id)
        }
    }

    @ViewBuilder
    private func imageView(_ entry: AttachmentEntry) -> some View {
        if let data = entry.imageData, let uiImage = UIImage(data: data) {
            Button {
                openImagePreview(for: entry.id)
            } label: {
                ImageAttachmentTile(uiImage: uiImage, cornerRadius: cornerRadius)
            }
            .buttonStyle(AttachmentCellButtonStyle())
            .contextMenu {
                landfilButton(for: entry.id)
            }
        }
    }

    private func voiceMemoView(_ entry: AttachmentEntry) -> some View {
        let isRecordingThis = recordingEntryID == entry.id
        let playbackDuration = entry.text
            .flatMap { AudioPlayerViewModel.audioFileURL(for: $0) }
            .map(audioDuration(for:))

        return Button {
            if isRecordingThis {
                stopMemoRecording(entryID: entry.id)
            } else if let path = entry.text, AudioPlayerViewModel.hasAudioFile(for: path) {
                openMemoPreview(for: entry)
            }
        } label: {
            VoiceMemoAttachmentTile(
                isRecording: isRecordingThis,
                displayedDuration: isRecordingThis ? memoDuration : playbackDuration,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .contextMenu {
            landfilButton(for: entry.id)
        }
    }

    private func pdfView(_ entry: AttachmentEntry) -> some View {
        Button {
            openPDFPreview(for: entry)
        } label: {
            PDFAttachmentTile(name: entry.pdfName ?? "PDF", cornerRadius: cornerRadius)
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .contextMenu {
            landfilButton(for: entry.id)
        }
    }

    private func linkView(_ entry: AttachmentEntry) -> some View {
        Button {
            if let urlString = entry.text, let url = URL(string: urlString) {
                inAppBrowserURL = url
            }
        } label: {
            LinkAttachmentTile(
                icon: favicons[entry.id],
                caption: entry.linkCaption,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .contextMenu {
            Button {
                beginEditingLink(entry)
            } label: {
                Label("Edit URL", systemImage: "pencil")
            }
            landfilButton(for: entry.id)
        }
    }

    private func noteView(_ entry: AttachmentEntry) -> some View {
        Button {
            noteEditorDetent = .large
            editingNoteID = entry.id
        } label: {
            NoteAttachmentTile(title: entry.noteTitle, cornerRadius: cornerRadius)
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .contextMenu {
            landfilButton(for: entry.id)
        }
    }

    private func linkedNoteView(_ entry: AttachmentEntry) -> some View {
        let target = resolveLinkedNote(entry)
        return Group {
            if let target {
                NavigationLink(value: FilSheetRoute.linkedNote(target.uuid)) {
                    linkedFilBlob(target)
                }
            } else {
                Button {} label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            NoteBlobShape(seed: 0.5)
                                .fill(Theme.cardBackground)
                                .overlay {
                                    Image(systemName: "link.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                        }
                }
                .disabled(true)
            }
        }
        .buttonStyle(AttachmentCellButtonStyle())
        .contextMenu {
            landfilButton(for: entry.id)
        }
    }

    /// A linked fil rendered with the SAME blob component (NoteCardView) the search grid and input
    /// bar use — so a linked photo shows its image, a voice fil its waveform, etc. Fills the cell.
    private func linkedFilBlob(_ target: Note) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    NoteCardView(note: target, cardHeight: geo.size.height)
                }
            }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Menu {
            if otherNotes.count > 0 {
                Section {
                    Button {
                        showFilLinkPicker = true
                    } label: {
                        Label("Link a thought", systemImage: "link.circle")
                    }
                }
            }
            Section {
                Button {
                    let entry = AttachmentEntry.note()
                    appendEntry(entry)
                    noteEditorDetent = .large
                    editingNoteID = entry.id
                } label: {
                    Label("Write note", systemImage: "note.text")
                }
                Button {
                    startMemoRecording()
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                Button {
                    beginAddingLink()
                } label: {
                    Label("URL", systemImage: "link")
                }
            }
            Section {
                Button {
                    photoPickerPresented = true
                } label: {
                    Label("Add photo", systemImage: "photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                    }
                }
                Button {
                    videoPickerPresented = true
                } label: {
                    Label("Add video", systemImage: "video")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showVideoCamera = true
                    } label: {
                        Label("Take a video", systemImage: "video.badge.plus")
                    }
                }
            }
            Section {
                Button {
                    showPDFImporter = true
                } label: {
                    Label("Upload PDF", systemImage: "doc.fill")
                }
            }
        } label: {
            AddAttachmentTile(cornerRadius: cornerRadius)
        }
    }

    // MARK: - Helpers

    private func landfilButton(for id: UUID) -> some View {
        Button(role: .destructive) {
            pendingLandfilEntryID = id
        } label: {
            Label("Landfil", systemImage: "trash")
        }
    }

    private func openImagePreview(for entryID: UUID) {
        let imageEntries = (attachment?.entries ?? []).filter { $0.kind == .image }
        let preview = AttachmentPreviewBuilder.makeImagePreview(entries: imageEntries, selectedEntryID: entryID)
        previewURLs = preview.urls
        if let selectedURL = preview.selectedURL {
            previewURL = selectedURL
        }
    }

    /// Copies the picked video into the documents directory (alongside audio memos) and appends a
    /// `.video` entry holding its filename — never stores the bytes in SwiftData.
    private func importVideo(_ item: PhotosPickerItem) {
        Task {
            defer { Task { @MainActor in selectedVideo = nil } }
            guard let movie = try? await item.loadTransferable(type: VideoAttachmentFile.self) else { return }
            await MainActor.run { saveImportedVideo(from: movie.url) }
            try? FileManager.default.removeItem(at: movie.url)
        }
    }

    /// Copies a video at `sourceURL` (from the library or camera) into the documents dir and appends
    /// a `.video` entry pointing at it. Runs on the main actor (mutates the model).
    private func saveImportedVideo(from sourceURL: URL) {
        let filename = "video-\(UUID().uuidString).mov"
        let dest = AudioPlayerViewModel.recordingsDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            return
        }
        FileProtection.protectAtRest(dest)
        appendEntry(.video(path: filename))
    }

    /// Videos live in the same documents directory as audio, so the audio resolver works for both.
    private func openVideoPreview(for entry: AttachmentEntry) {
        guard let url = AudioPlayerViewModel.audioFileURL(for: entry.text ?? "") else { return }
        previewURLs = [url]
        previewURL = url
    }

    /// Generates a first-frame thumbnail once per video entry, cached in memory.
    private func loadThumbnail(for entry: AttachmentEntry) {
        guard videoThumbnails[entry.id] == nil,
              let url = AudioPlayerViewModel.audioFileURL(for: entry.text ?? "") else { return }
        let id = entry.id
        Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true   // correct portrait orientation
            generator.maximumSize = CGSize(width: 400, height: 400)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            guard let result = try? await generator.image(at: time) else { return }
            let image = UIImage(cgImage: result.image)
            await MainActor.run { videoThumbnails[id] = image }
        }
    }

    private func fetchFavicon(for entry: AttachmentEntry) {
        guard let urlString = entry.text, let url = URL(string: urlString) else { return }
        let entryID = entry.id
        FaviconLoader.loadFavicon(for: url) { image in
            guard let image else { return }
            self.favicons[entryID] = image
            if let data = image.pngData() {
                self.updateEntry(id: entryID) { $0.faviconData = data }
            }
        }
    }

    private func beginAddingLink() {
        linkEditorDetent = .fraction(0.6)
        linkEditor = LinkEditorState(mode: .add, url: "", caption: "")
    }

    private func beginEditingLink(_ entry: AttachmentEntry) {
        linkEditorDetent = .fraction(0.6)
        linkEditor = LinkEditorState(
            mode: .edit(entry.id),
            url: entry.text ?? "",
            caption: entry.linkCaption ?? ""
        )
    }

    private func saveLinkEditor() {
        guard let linkEditor else { return }

        let trimmedURL = linkEditor.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let normalizedURL = trimmedURL.hasPrefix("http") ? trimmedURL : "https://\(trimmedURL)"
        let trimmedCaption = linkEditor.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = trimmedCaption.isEmpty ? nil : String(trimmedCaption.prefix(Self.linkCaptionLimit))

        switch linkEditor.mode {
        case .add:
            let entry = AttachmentEntry.link(url: normalizedURL, caption: caption)
            appendEntry(entry)
            fetchFavicon(for: entry)
        case .edit(let id):
            let previousURL = entry(for: id)?.text
            guard previousURL != nil else {
                clearLinkEditor()
                return
            }

            updateEntry(id: id) {
                $0.text = normalizedURL
                $0.linkCaption = caption
            }

            if previousURL != normalizedURL {
                updateEntry(id: id) { $0.faviconData = nil }
                favicons[id] = nil
                if let updatedEntry = entry(for: id) {
                    fetchFavicon(for: updatedEntry)
                }
            }
        }

        clearLinkEditor()
    }

    private func clearLinkEditor() {
        linkEditor = nil
    }

    private func confirmLandfilEntry() {
        guard let id = pendingLandfilEntryID else { return }
        SoundscapeManager.shared.playLandfilSound()
        landfilEntry(id: id)
        pendingLandfilEntryID = nil
    }

    private func startMemoRecording() {
        Task { @MainActor in
            guard let recorder = await MemoRecordingController.makeRecorder() else { return }
            recorder.record()
            FileProtection.protectAtRest(recorder.url)
            memoRecorder = recorder
            memoDuration = 0

            let entry = AttachmentEntry.recording(path: recorder.url.lastPathComponent)
            appendEntry(entry)
            recordingEntryID = entry.id

            memoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                memoDuration += 0.1
            }
        }
    }

    private func stopMemoRecording(entryID: UUID) {
        memoRecorder?.stop()
        memoRecorder = nil
        memoTimer?.invalidate()
        memoTimer = nil
        recordingEntryID = nil
        memoDuration = 0
    }

    private func openMemoPreview(for entry: AttachmentEntry) {
        guard let path = entry.text, let url = AudioPlayerViewModel.audioFileURL(for: path) else { return }
        previewURLs = [url]
        previewURL = url
    }

    private func openPDFPreview(for entry: AttachmentEntry) {
        guard let data = entry.pdfData else { return }
        guard let url = AttachmentPreviewBuilder.makePDFPreview(data: data, suggestedName: entry.pdfName) else { return }
        previewURLs = [url]
        previewURL = url
    }

    private func audioDuration(for url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    private func formatMemoDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func resolveLinkedNote(_ entry: AttachmentEntry) -> Note? {
        guard let idString = entry.linkedNoteID,
              let uuid = UUID(uuidString: idString) else { return nil }
        return allNotes.first { $0.uuid == uuid }
    }

    private var otherNotes: [Note] {
        allNotes.filter { $0.uuid != note.uuid }
    }

    private func findOrCreate() -> KeywordAttachment {
        if let existing = attachment { return existing }
        let new = KeywordAttachment(keyword: keyword, note: note)
        modelContext.insert(new)
        return new
    }

    private func entry(for id: UUID) -> AttachmentEntry? {
        attachment?.entries.first(where: { $0.id == id })
    }

    private func appendEntry(_ entry: AttachmentEntry) {
        let attachment = findOrCreate()
        attachment.entries.append(entry)
    }

    private func appendLinkedNote(_ linkedNote: Note) {
        // One-directional: the link lives only on this fil. The target gets no backlink.
        appendEntry(.linkedNote(id: linkedNote.uuid, title: linkedNote.title))
        modelContext.saveOrLog()
    }

    private func updateEntry(id: UUID, mutate: (inout AttachmentEntry) -> Void) {
        guard let attachment, let index = attachment.entries.firstIndex(where: { $0.id == id }) else { return }
        var updatedEntry = attachment.entries[index]
        mutate(&updatedEntry)
        attachment.entries[index] = updatedEntry
    }

    private func landfilEntry(id: UUID) {
        guard let attachment else { return }
        let removedEntries = attachment.entries.filter { $0.id == id }
        attachment.entries.removeAll { $0.id == id }
        for entry in removedEntries where entry.kind == .linkedNote {
            removeBacklink(for: entry)
        }
        for entry in removedEntries where entry.kind == .video {
            if let url = AudioPlayerViewModel.audioFileURL(for: entry.text ?? "") {
                try? FileManager.default.removeItem(at: url)
            }
            videoThumbnails[entry.id] = nil
        }
        if attachment.entries.isEmpty {
            modelContext.delete(attachment)
        }
    }

    private func removeBacklink(for entry: AttachmentEntry) {
        guard let linkedNote = resolveLinkedNote(entry) else { return }
        let parentID = note.uuid.uuidString
        linkedNote.threadedBacklinks.removeAll {
            $0.parentNoteID == parentID && $0.parentKeyword == keyword
        }
        modelContext.saveOrLog()
    }

    private var linkURLBinding: Binding<String> {
        Binding(
            get: { linkEditor?.url ?? "" },
            set: { linkEditor?.url = $0 }
        )
    }

    private var linkCaptionBinding: Binding<String> {
        Binding(
            get: { linkEditor?.caption ?? "" },
            set: { linkEditor?.caption = String($0.prefix(Self.linkCaptionLimit)) }
        )
    }

    private func makeDragItem(for entryID: UUID) -> AttachmentDragItem {
        beginDragging(entryID)
        return AttachmentDragItem(id: entryID)
    }

    private func beginDragging(_ entryID: UUID) {
        guard draggingID != entryID else { return }
        dragSnapshot = attachment?.entries.map(\.id) ?? []
        draggingID = entryID
        didCompleteDrop = false
    }

    private func updateDropTarget(_ targetID: UUID) {
        guard let attachment,
              let draggingID,
              draggingID != targetID,
              let fromIndex = attachment.entries.firstIndex(where: { $0.id == draggingID }),
              let toIndex = attachment.entries.firstIndex(where: { $0.id == targetID })
        else { return }

        withAnimation(.snappy(duration: 0.25)) {
            attachment.entries.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    private func handleDrop(_ items: [AttachmentDragItem], targetID: UUID?) -> Bool {
        guard let droppedItem = items.first else {
            finalizeDragIfNeeded(committed: false)
            return false
        }

        beginDragging(droppedItem.id)

        if let targetID {
            updateDropTarget(targetID)
        }

        finalizeDragIfNeeded(committed: true)
        return true
    }

    private func finalizeDragIfNeeded(committed: Bool) {
        guard draggingID != nil else { return }

        if !committed {
            restoreDragSnapshot()
        }

        draggingID = nil
        dragSnapshot = []
        didCompleteDrop = committed
    }

    private func restoreDragSnapshot() {
        guard let attachment, !dragSnapshot.isEmpty else { return }

        let currentEntriesByID = Dictionary(uniqueKeysWithValues: attachment.entries.map { ($0.id, $0) })
        let restoredEntries = dragSnapshot.compactMap { currentEntriesByID[$0] }

        guard restoredEntries.count == attachment.entries.count else { return }
        attachment.entries = restoredEntries
    }
}

struct MissingLinkedFilView: View {
    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            Text("Thought not found")
                .font(Theme.dmMono(12))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

private struct AttachmentDragItem: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .attachmentDragItem)
    }
}

private extension UTType {
    static let attachmentDragItem = UTType(importedAs: "com.fil.attachment-drag-item")
}

private struct AttachmentCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private enum AttachmentPreviewBuilder {
    struct ImagePreview {
        let urls: [URL]
        let selectedURL: URL?
    }

    static func makeImagePreview(entries: [AttachmentEntry], selectedEntryID: UUID) -> ImagePreview {
        let tempDir = previewDirectoryURL()
        var urls: [URL] = []
        var selectedIndex = 0

        for (index, entry) in entries.enumerated() {
            guard let data = entry.imageData else { continue }
            let url = tempDir.appendingPathComponent("image-\(index).jpg")
            try? data.write(to: url)
            urls.append(url)
            if entry.id == selectedEntryID {
                selectedIndex = urls.count - 1
            }
        }

        let selectedURL = urls.indices.contains(selectedIndex) ? urls[selectedIndex] : nil
        return ImagePreview(urls: urls, selectedURL: selectedURL)
    }

    static func makePDFPreview(data: Data, suggestedName: String?) -> URL? {
        let tempDir = previewDirectoryURL()
        let url = tempDir.appendingPathComponent(suggestedName ?? "document.pdf")
        try? data.write(to: url)
        return url
    }

    private static func previewDirectoryURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fil-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}

enum FaviconLoader {
    static func loadFavicon(for url: URL, completion: @escaping @MainActor (UIImage?) -> Void) {
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let iconProvider = metadata?.iconProvider else {
                Task { @MainActor in completion(nil) }
                return
            }

            iconProvider.loadObject(ofClass: UIImage.self) { image, _ in
                Task { @MainActor in
                    completion(image as? UIImage)
                }
            }
        }
    }

    static func loadMetadata(for url: URL, completion: @escaping @MainActor (_ title: String?, _ icon: UIImage?) -> Void) {
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let iconProvider = metadata?.iconProvider else {
                Task { @MainActor in completion(metadata?.title, nil) }
                return
            }

            iconProvider.loadObject(ofClass: UIImage.self) { image, _ in
                Task { @MainActor in
                    completion(metadata?.title, image as? UIImage)
                }
            }
        }
    }
}

private enum MemoRecordingController {
    static func makeRecorder() async -> AVAudioRecorder? {
        guard await AudioSessionCoordinator.configurePlayAndRecord() else { return nil }

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memo-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        return try? AVAudioRecorder(url: url, settings: settings)
    }
}

private struct ImageAttachmentTile: View {
    let uiImage: UIImage
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct VideoAttachmentTile: View {
    let thumbnail: UIImage?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Lets a picked `PhotosPickerItem` video load as a file URL we can copy into the documents dir.
private struct VideoAttachmentFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

private struct VoiceMemoAttachmentTile: View {
    let isRecording: Bool
    let displayedDuration: TimeInterval?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if isRecording {
                    VStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                        if let displayedDuration {
                            Text(formatDuration(displayedDuration))
                                .font(Theme.dmMono(11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.secondaryText)
                        if let displayedDuration {
                            Text(formatDuration(displayedDuration))
                                .font(Theme.dmMono(11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PDFAttachmentTile: View {
    let name: String
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                VStack(spacing: 4) {
                    Image("filpdficon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(name)
                        .font(Theme.dmSans(11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
    }
}

private struct LinkAttachmentTile: View {
    let icon: UIImage?
    let caption: String?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                VStack(spacing: 4) {
                    if let icon {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(Theme.dmMono(10))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
            }
    }
}

private struct NoteAttachmentTile: View {
    let title: String?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                Text(title?.isEmpty == false ? title! : "...")
                    .font(Theme.dmSans(11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
    }
}


private struct AddAttachmentTile: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }
    }
}

struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct LinkEditorSheet: View {
    private static let captionLimit = 15

    let title: String
    @Binding var url: String
    @Binding var caption: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case url
        case caption
    }

    private var limitedCaptionBinding: Binding<String> {
        Binding(
            get: { caption },
            set: { caption = String($0.prefix(Self.captionLimit)) }
        )
    }

    private var remainingCaptionCharacters: Int {
        max(0, Self.captionLimit - caption.count)
    }

    private var remainingCaptionColor: Color {
        remainingCaptionCharacters <= 5 ? .red : Theme.tertiaryText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(Theme.dmSans(20, weight: .bold))
                        .foregroundStyle(Theme.primaryText)

                    Spacer(minLength: 12)

                    Button {
                        onSave()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, height: 44)
                            .background(Theme.cardBackground, in: Circle())
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL")
                            .font(Theme.dmMono(11))
                            .foregroundStyle(Theme.tertiaryText)

                        TextField("https://", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.primaryText)
                            .focused($focusedField, equals: .url)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Caption")
                                .font(Theme.dmMono(11))
                                .foregroundStyle(Theme.tertiaryText)
                            Spacer()
                            Text("\(remainingCaptionCharacters)")
                                .font(Theme.dmMono(11))
                                .foregroundStyle(remainingCaptionColor)
                        }

                        LimitedTextField(
                            placeholder: "Optional",
                            text: $caption,
                            limit: Self.captionLimit,
                            fontSize: 15,
                            textColor: UIColor(Theme.primaryText)
                        )
                        .frame(height: 22)
                    }
                }
                .padding(16)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .onAppear {
            focusedField = .url
        }
    }
}

private struct LimitedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let limit: Int
    let fontSize: CGFloat
    let textColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, limit: limit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.textColor = textColor
        textField.font = .systemFont(ofSize: fontSize)
        textField.borderStyle = .none
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
        uiView.font = .systemFont(ofSize: fontSize)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let limit: Int

        init(text: Binding<String>, limit: Int) {
            _text = text
            self.limit = limit
        }

        @objc func editingChanged(_ textField: UITextField) {
            let currentText = textField.text ?? ""
            let limitedText = String(currentText.prefix(limit))
            if currentText != limitedText {
                textField.text = limitedText
            }
            text = limitedText
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else { return false }
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            return updatedText.count <= limit
        }
    }
}

// MARK: - Note Editor Sheet

struct NoteEditorSheet: View {
    @Binding var title: String
    @Binding var text: String
    @FocusState private var focusedField: Field?
    private enum Field { case title, body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $title)
                    .font(Theme.dmSans(20, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .focused($focusedField, equals: .title)

                TextField("Write a note...", text: $text, axis: .vertical)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.primaryText)
                    .focused($focusedField, equals: .body)
            }
            .padding(20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .topTrailing) {
            Button {
                focusedField = nil
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardBackground, in: Circle())
            }
            .padding(16)
        }
        .onAppear { focusedField = nil }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Records a video with the camera and hands back the captured file URL (a temp file).
struct CameraVideoPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraVideoPicker
        init(_ parent: CameraVideoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onCapture(url)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
