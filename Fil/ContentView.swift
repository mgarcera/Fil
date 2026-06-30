import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .reverse)]) private var userProfiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNote: Note?
    @State private var recorder = VoiceRecorderViewModel()
    @State private var showPermissionAlert = false
    @State private var showFilSetup = false
    @State private var isTextComposerExpanded = false
    @State private var textEntryText = ""
    @State private var selectedComposerPhotos: [PhotosPickerItem] = []
    @State private var stagedComposerImageData: [Data] = []
    @State private var isCreatingTextEntry = false
    private let temporaryDraftStore = TemporaryFilDraftStore.shared
    @State private var temporaryDraft = TemporaryFilDraftStore.shared.draft
    @AppStorage("isDarkMode") private var isDarkMode = true
    @Namespace private var composerNamespace
    @State private var visibleTip = emptyStateTip
    @State private var showHomeFocusSheet = false
    @State private var selectedNoteDetent = PresentationDetent.fraction(0.6)
    @State private var filSheetPath: [FilSheetRoute] = []
    @State private var homeFocusDetent = PresentationDetent.fraction(0.3)
    @State private var selectedNoteIDs = Set<UUID>()
    @State private var landfillingNoteIDs = Set<UUID>()
    @State private var showBulkLandfilConfirmation = false
    @State private var pendingHomeFocusSelection: HomeFocusSelection?
    @State private var sectionCollapseCommandID = 0
    @State private var sectionCollapseCommandStage = 0
    @AppStorage("collapsedDaySectionKeys") private var collapsedDaySectionKeysRaw = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if notes.isEmpty {
                            AnimatedGradientRevealText(text: visibleTip)
                                .font(Theme.dmSans(15, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .blur(radius: isTextComposerExpanded ? 8 : 0)
                                .opacity(isTextComposerExpanded ? 0 : 1)
                                .animation(.easeInOut(duration: 0.3), value: isTextComposerExpanded)
                        }

                        Group {
                            if notes.isEmpty {
                                emptyState
                            } else {
                                NoteGridView(
                                    notes: notes,
                                    selectedNote: $selectedNote,
                                    selectedNoteIDs: selectedNoteIDs,
                                    landfillingNoteIDs: landfillingNoteIDs,
                                    isSelectionMode: isSelectingNotes,
                                    collapseCommandID: sectionCollapseCommandID,
                                    collapseCommandStage: sectionCollapseCommandStage,
                                    onSelectNote: { note in
                                        SoundscapeManager.shared.playOpenFilClick()
                                        selectedNoteDetent = initialSelectedNoteDetent(for: note)
                                        filSheetPath.removeAll()
                                        selectedNote = note
                                    },
                                    onToggleSelection: toggleNoteSelection,
                                    onBeginSelection: beginNoteSelection,
                                    onToggleSectionSelection: toggleSectionSelection
                                ) { note in
                                    landfilNote(note)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
                .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                bottomComposer
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            MeshGradientView()
                .ignoresSafeArea()
                .opacity(recorder.isProcessing || isCreatingTextEntry ? 0.7 : 0)
                .allowsHitTesting(recorder.isProcessing || isCreatingTextEntry)
                .animation(.easeInOut(duration: 0.6), value: recorder.isProcessing)
                .animation(.easeInOut(duration: 0.6), value: isCreatingTextEntry)
        }
        .sheet(item: $selectedNote, onDismiss: handleArticleDismissed) { note in
            NavigationStack(path: $filSheetPath) {
                ArticleView(
                    note: note,
                    ignoresTopSafeArea: false,
                    showsCloseButton: true,
                    filSheetPath: $filSheetPath,
                    selectedPresentationDetent: $selectedNoteDetent
                )
                    .navigationDestination(for: FilSheetRoute.self) { route in
                        filSheetDestination(route)
                    }
            }
            .presentationDetents(selectedNotePresentationDetents(for: note), selection: $selectedNoteDetent)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showHomeFocusSheet) {
            HomeFocusSheet(notes: notes, userProfile: activeUserProfile) { note in
                pendingHomeFocusSelection = HomeFocusSelection(noteUUID: note.uuid)
            }
            .presentationDetents([.fraction(0.3)], selection: $homeFocusDetent)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showFilSetup) {
            OnboardingView(existingProfile: activeUserProfile, showsSkipControl: false)
                .presentationBackground(Theme.background)
        }
        .alert("Permissions Required", isPresented: $showPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Microphone and speech recognition access are needed to record notes.")
        }
        .alert("move selected fils to landfil?", isPresented: $showBulkLandfilConfirmation) {
            Button("landfil", role: .destructive) {
                landfilSelectedNotes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedNoteIDs.count) selected. this cannot be undone.")
        }
        .alert("Error", isPresented: .init(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .onChange(of: isTextComposerExpanded) { _, newValue in
            if !newValue {
                textEntryText = ""
                selectedComposerPhotos = []
                stagedComposerImageData = []
            }
        }
        .onChange(of: selectedComposerPhotos) { _, newItems in
            Task {
                await loadStagedComposerImages(from: newItems)
            }
        }
        .onChange(of: notes.map(\.uuid)) { _, noteIDs in
            let currentNoteIDs = Set(noteIDs)
            selectedNoteIDs.formIntersection(currentNoteIDs)
            landfillingNoteIDs.formIntersection(currentNoteIDs)
        }
        .onChange(of: showHomeFocusSheet) { _, isPresented in
            guard !isPresented, let pendingHomeFocusSelection else { return }
            guard let note = notes.first(where: { $0.uuid == pendingHomeFocusSelection.noteUUID }) else {
                self.pendingHomeFocusSelection = nil
                return
            }
            self.pendingHomeFocusSelection = nil
            DispatchQueue.main.async {
                SoundscapeManager.shared.playOpenFilClick()
                selectedNoteDetent = .fraction(0.6)
                filSheetPath.removeAll()
                selectedNote = note
            }
        }
        .onOpenURL(perform: handleIncomingURL)
    }

    @ViewBuilder
    private func filSheetDestination(_ route: FilSheetRoute) -> some View {
        switch route {
        case .keyword(let noteID, let keyword):
            if let routeNote = notes.first(where: { $0.uuid == noteID }) {
                KeywordPopup(note: routeNote, keyword: keyword)
            } else {
                MissingLinkedFilView()
            }
        case .linkedNote(let linkedNoteID):
            if let linkedNote = notes.first(where: { $0.uuid == linkedNoteID }) {
                ArticleView(
                    note: linkedNote,
                    showsThreadedFilRows: false,
                    ignoresTopSafeArea: false,
                    filSheetPath: $filSheetPath
                )
            } else {
                MissingLinkedFilView()
            }
        }
    }

    private var header: some View {
        HStack {
            Image("FilLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 32)
            Spacer()
            HStack(spacing: 14) {
                Button {
                    SoundscapeManager.shared.playSettingsSound()
                    showFilSetup = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                }

                Button {
                    SoundscapeManager.shared.playLightModeSound()
                    withAnimation(.snappy) { isDarkMode.toggle() }
                } label: {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.primaryText)
                }

                Button {
                    toggleAllDaySections()
                } label: {
                    Image(systemName: areAllDaySectionsCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                }
                .disabled(allDaySectionKeys.isEmpty)
                .opacity(allDaySectionKeys.isEmpty ? 0.45 : 1)
                .accessibilityLabel(areAllDaySectionsCollapsed ? "Expand all sections" : "Collapse all sections")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var activeUserProfile: UserProfile? {
        userProfiles.first
    }

    private func initialSelectedNoteDetent(for note: Note) -> PresentationDetent {
        note.isLinkFil ? .fraction(0.2) : .fraction(0.6)
    }

    private func selectedNotePresentationDetents(for note: Note) -> Set<PresentationDetent> {
        if note.isLinkFil {
            return [.fraction(0.2)]
        }

        return note.isImageFil ? [.fraction(0.6), .large] : [.fraction(0.6)]
    }

    private var allDaySectionKeys: [String] {
        let dayPartition = FilDayPartition()
        let keys = Set(notes.map { note in
            Self.daySectionKeyFormatter.string(from: dayPartition.dayStart(for: note.timestamp))
        })
        return keys.sorted()
    }

    private var storedCollapseStages: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: collapsedDaySectionKeysRaw
                .split(separator: "\n")
                .compactMap { line in
                    let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                    guard let key = parts.first, !key.isEmpty else { return nil }
                    return (key, parts.count > 1 ? Int(parts[1]) ?? 1 : 1)
                }
        )
    }

    private var areAllDaySectionsCollapsed: Bool {
        let keys = allDaySectionKeys
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { (storedCollapseStages[$0] ?? 0) > 0 }
    }

    private func toggleAllDaySections() {
        let shouldCollapse = !areAllDaySectionsCollapsed
        let nextStage = shouldCollapse ? 2 : 0
        if shouldCollapse {
            SoundscapeManager.shared.playCollapsePartTwoSound()
            collapsedDaySectionKeysRaw = allDaySectionKeys
                .map { "\($0)|2" }
                .joined(separator: "\n")
        } else {
            SoundscapeManager.shared.playCollapsingSound()
            collapsedDaySectionKeysRaw = ""
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            sectionCollapseCommandStage = nextStage
            sectionCollapseCommandID += 1
        }
    }

    private static let daySectionKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var homeFocusPageCount: Int {
        notes.reduce(into: 0) { count, note in
            let hasOpenTodo = note.todos.enumerated().contains { index, _ in
                let isCompleted = note.completedTodos.indices.contains(index) ? note.completedTodos[index] : false
                return !isCompleted
            }
            if hasOpenTodo {
                count += 1
            }
        }
    }

    private var isSelectingNotes: Bool {
        !selectedNoteIDs.isEmpty
    }

    private var selectedNotes: [Note] {
        notes.filter { selectedNoteIDs.contains($0.uuid) }
    }

    private var bottomComposer: some View {
        Group {
            if isSelectingNotes {
                bulkSelectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if recorder.isRecording {
                RecordButton(isRecording: true, duration: recorder.recordingDuration, namespace: composerNamespace) {
                    stopRecording()
                }
                .transition(.blurReplace)
            } else {
                VStack(spacing: 10) {
                    if !isTextComposerExpanded, let draft = temporaryDraft {
                        temporaryDraftBar(draft)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isTextComposerExpanded {
                        textComposerPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        composerActionRow
                            .transition(.blurReplace)
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: recorder.isRecording)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: isSelectingNotes)
    }

    private static let emptyStateTip = """
    fil was made to take advantage of your on-device ai. everything is processed locally and nothing is stored in the cloud

    it's absolutely free. i'm a social worker / data specialist having fun in my digital world and want you to have fun in it too

    i wanted an app whose recipe calls for fluff. filler. a dash of dictation with a tablespoon of inference. 

    to get started, create a fil. watch it fil'n the blanks with fil'r. then, highlight text, click fil'ament, and string up to 32 different kinds of attachments.

    happy fil'ng. and have fun :) mason
    """

    private var emptyState: some View {
        FromMasonFilCard()
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private var bulkSelectionBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    selectedNoteIDs.removeAll()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: Circle())
                    .overlay(Circle().stroke(Theme.divider.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("\(selectedNoteIDs.count) selected")
                .font(Theme.dmSans(13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(Theme.background, in: Capsule())
                .overlay(Capsule().stroke(Theme.divider.opacity(0.55), lineWidth: 1))

            Button {
                showBulkLandfilConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.recordRed, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var textComposerPanel: some View {
        FilComposerInputBar(
            text: $textEntryText,
            selectedPhotos: $selectedComposerPhotos,
            stagedImageData: stagedComposerImageData,
            placeholder: "(thoughts. lore. fil'osophy.)",
            actionSymbol: "arrow.up",
            secondaryActionSymbol: "pin",
            isProcessing: isCreatingTextEntry,
            autoFocus: true,
            onAction: {
                Task {
                    await createTextEntry(from: textEntryText)
                }
            },
            onSecondaryAction: {
                holdTemporaryDraft(from: textEntryText)
            },
            onDismiss: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isTextComposerExpanded = false
                }
            },
            onFocusChange: { _ in },
            onRemoveStagedImage: removeStagedComposerImage
        )
    }

    private func temporaryDraftBar(_ draft: TemporaryFilDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                textEntryText = draft.text
                temporaryDraftStore.clear()
                temporaryDraft = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isTextComposerExpanded = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .bold))

                    Text(draft.previewText.isEmpty ? "temporary draft" : draft.previewText)
                        .font(Theme.dmSans(13, weight: .semibold))
                        .lineLimit(1)

                    Text("\(draft.wordCount)")
                        .font(Theme.dmMono(11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Theme.background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await createFilFromTemporaryDraft(draft)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isCreatingTextEntry)

            Button {
                SoundscapeManager.shared.playOpenFilClick()
                withAnimation(.snappy) {
                    temporaryDraftStore.clear()
                    temporaryDraft = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var composerActionRow: some View {
        HStack(spacing: 10) {
            FocusEntryButton(count: homeFocusPageCount) {
                SoundscapeManager.shared.playTodoSound()
                homeFocusDetent = .fraction(0.3)
                showHomeFocusSheet = true
            }

            NewFilButton(namespace: composerNamespace) {
                SoundscapeManager.shared.playTransformRefilSound()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    isTextComposerExpanded = true
                }
            } onLongPress: {
                startRecording()
            }
        }
    }

    private func holdTemporaryDraft(from text: String) {
        temporaryDraftStore.hold(text)
        temporaryDraft = temporaryDraftStore.draft
        SoundscapeManager.shared.playOpenFilClick()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            textEntryText = ""
            isTextComposerExpanded = false
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let text = TemporaryFilDraftIntake.text(from: url) else { return }

        temporaryDraftStore.hold(text)
        temporaryDraft = temporaryDraftStore.draft
        SoundscapeManager.shared.playOpenFilClick()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isTextComposerExpanded = false
        }
    }

    private func createFilFromTemporaryDraft(_ draft: TemporaryFilDraft) async {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            temporaryDraftStore.clear()
            temporaryDraft = nil
            return
        }

        isCreatingTextEntry = true
        SoundscapeManager.shared.startMeshDuringProcessSound()
        defer {
            isCreatingTextEntry = false
            SoundscapeManager.shared.stopMeshDuringProcessSound()
        }

        do {
            try await saveGeneratedNote(from: trimmed)
            withAnimation(.snappy) {
                temporaryDraftStore.clear()
                temporaryDraft = nil
            }
        } catch {
            recorder.errorMessage = error.localizedDescription
        }
    }

    private func startRecording() {
        Task {
            let granted = await recorder.requestPermissions()
            if granted {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isTextComposerExpanded = false
                }
                await recorder.startRecording()
            } else {
                showPermissionAlert = true
            }
        }
    }

    private func stopRecording() {
        guard let result = recorder.stopRecording() else { return }
        processRecording(url: result.url, duration: result.duration)
    }

    private func landfilNote(_ note: Note) {
        deleteNoteResources(note)
        modelContext.delete(note)
        selectedNoteIDs.remove(note.uuid)
    }

    private func landfilSelectedNotes() {
        let notesToDelete = selectedNotes
        guard !notesToDelete.isEmpty else { return }

        let noteIDs = Set(notesToDelete.map(\.uuid))
        SoundscapeManager.shared.playLandfilSound()
        withAnimation(.easeOut(duration: 0.45)) {
            landfillingNoteIDs.formUnion(noteIDs)
            selectedNoteIDs.subtract(noteIDs)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.45)) {
                for note in notesToDelete {
                    deleteNoteResources(note)
                    modelContext.delete(note)
                }
                landfillingNoteIDs.subtract(noteIDs)
            }
        }
    }

    private func deleteNoteResources(_ note: Note) {
        if let audioURL = AudioPlayerViewModel.audioFileURL(for: note.audioFilePath) {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    private func beginNoteSelection(_ note: Note) {
        guard !recorder.isRecording else { return }
        SoundscapeManager.shared.playTabSound()
        withAnimation(.snappy) {
            _ = selectedNoteIDs.insert(note.uuid)
        }
    }

    private func toggleNoteSelection(_ note: Note) {
        SoundscapeManager.shared.playTabSound()
        withAnimation(.snappy) {
            if selectedNoteIDs.contains(note.uuid) {
                selectedNoteIDs.remove(note.uuid)
            } else {
                selectedNoteIDs.insert(note.uuid)
            }
        }
    }

    private func toggleSectionSelection(_ sectionNotes: [Note]) {
        guard !sectionNotes.isEmpty else { return }
        SoundscapeManager.shared.playTabSound()
        withAnimation(.snappy) {
            let sectionIDs = Set(sectionNotes.map(\.uuid))
            if sectionIDs.isSubset(of: selectedNoteIDs) {
                selectedNoteIDs.subtract(sectionIDs)
            } else {
                selectedNoteIDs.formUnion(sectionIDs)
            }
        }
    }

    private func processRecording(url: URL, duration: TimeInterval) {
        recorder.isProcessing = true
        SoundscapeManager.shared.startMeshDuringProcessSound()
        Task {
            do {
                let transcript = try await recorder.transcribe(url: url)
                try await saveGeneratedNote(
                    from: transcript,
                    audioFilePath: url.lastPathComponent,
                    duration: duration
                )
            } catch {
                recorder.errorMessage = error.localizedDescription
            }
            recorder.isProcessing = false
            SoundscapeManager.shared.stopMeshDuringProcessSound()
        }
    }

    private func createTextEntry(from text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let stagedImages = stagedComposerImageData
        isCreatingTextEntry = true
        SoundscapeManager.shared.startMeshDuringProcessSound()
        defer {
            isCreatingTextEntry = false
            SoundscapeManager.shared.stopMeshDuringProcessSound()
        }

        do {
            if !stagedImages.isEmpty {
                try await saveImageFil(caption: trimmed, imageData: stagedImages)
            } else if let linkURL = normalizedLinkURL(from: trimmed) {
                saveLinkNote(for: linkURL)
            } else {
                try await saveGeneratedNote(from: trimmed)
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                isTextComposerExpanded = false
            }
        } catch {
            recorder.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadStagedComposerImages(from items: [PhotosPickerItem]) async {
        var loadedImageData: [Data] = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            loadedImageData.append(data)
        }

        stagedComposerImageData = loadedImageData
    }

    private func removeStagedComposerImage(at index: Int) {
        guard stagedComposerImageData.indices.contains(index) else { return }
        stagedComposerImageData.remove(at: index)
        if selectedComposerPhotos.indices.contains(index) {
            selectedComposerPhotos.remove(at: index)
        }
    }

    private var recentGradientHistory: (pairs: Set<String>, colors: Set<String>) {
        let recentPairNotes = notes.prefix(8)
        let pairs = Set(recentPairNotes.map { "\($0.gradientStartHex)|\($0.gradientEndHex)" })
        let colors = Set(notes.prefix(4).flatMap { [$0.gradientStartHex, $0.gradientEndHex] })
        return (pairs, colors)
    }

    private func freshGradientPair() -> (start: String, end: String) {
        let history = recentGradientHistory
        return Theme.randomGradientPair(
            avoidingRecentPairs: history.pairs,
            avoidingRecentColors: history.colors
        )
    }

    private func normalizedLinkURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        let candidate = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host(),
              host.contains("."),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    private func saveLinkNote(for url: URL) {
        let gradient = freshGradientPair()
        let fallbackTitle = linkTitleFallback(for: url)
        let note = Note(
            title: fallbackTitle,
            transcript: url.absoluteString,
            articleBody: "",
            keyword: "link",
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end,
            sourceURLString: url.absoluteString,
            sourceTitle: fallbackTitle
        )
        modelContext.insert(note)
        SoundscapeManager.shared.playArticleMadeSound()

        FaviconLoader.loadMetadata(for: url) { title, icon in
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                note.title = title
                note.sourceTitle = title
            }
            if let data = icon?.pngData() {
                note.sourceFaviconData = data
            }
            try? modelContext.save()
        }
    }

    private func linkTitleFallback(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain
    }

    private func saveImageFil(caption: String, imageData: [Data]) async throws {
        let metadata = try await ArticleGenerationService.shared.generateMetadata(
            from: caption,
            userProfile: activeUserProfile
        )

        let gradient = freshGradientPair()
        let note = Note(
            title: "",
            transcript: caption,
            articleBody: "",
            keyword: metadata.keyword,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.imageFilImages = imageData.enumerated().map { index, data in
            NoteImage(data: data, order: index, note: note)
        }
        modelContext.insert(note)
        SoundscapeManager.shared.playArticleMadeSound()
    }

    private func saveGeneratedNote(
        from transcript: String,
        audioFilePath: String = "",
        duration: TimeInterval = 0
    ) async throws {
        let metadata = try await ArticleGenerationService.shared.generateMetadata(
            from: transcript,
            userProfile: activeUserProfile
        )

        let gradient = freshGradientPair()
        let note = Note(
            title: metadata.title,
            transcript: transcript,
            articleBody: "",
            audioFilePath: audioFilePath,
            duration: duration,
            todos: metadata.todos,
            keyword: metadata.keyword,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        modelContext.insert(note)
        SoundscapeManager.shared.playArticleMadeSound()
    }

    private func handleArticleDismissed() {
        filSheetPath.removeAll()
    }
}

private struct HomeFocusSelection {
    let noteUUID: UUID
}

struct RecordButton: View {
    let isRecording: Bool
    let duration: TimeInterval
    var namespace: Namespace.ID?
    let action: () -> Void

    private var beamColors: [Color] {
        Theme.accentGradientColors
    }

    var body: some View {
        Button {
            action()
        } label: {
            buttonLabel
        }
    }

    private var buttonLabel: some View {
        HStack(spacing: 6) {
            if isRecording {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.primaryText)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(Theme.primaryText)
                    .frame(width: 10, height: 10)
            }

            if isRecording {
                Text(formattedDuration)
                    .font(Theme.dmMono(13))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
            } else {
                Text("new fil")
                    .font(Theme.dmSans(13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .borderBeam(
            border: Theme.primaryText,
            beam: beamColors,
            beamBlur: 12,
            cornerRadius: 20,
            isEnabled: isRecording
        )
        .background {
            Capsule()
                .fill(Theme.background)
                .modifier(OptionalMatchedGeometry(id: "composerPill", namespace: namespace))
        }
        .overlay {
            Capsule()
                .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                .modifier(OptionalMatchedGeometry(id: "composerBorder", namespace: namespace))
        }
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct FocusEntryButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(displayCount)")
                .font(Theme.dmSans(14, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(Theme.background)
                }
                .overlay {
                    Circle()
                        .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var displayCount: String {
        count > 99 ? "99+" : "\(count)"
    }
}

private struct NewFilButton: View {
    var namespace: Namespace.ID?
    let onTap: () -> Void
    let onLongPress: () -> Void

    private let holdDuration: TimeInterval = 0.4

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTriggered = false
    @State private var holdTimer: Task<Void, Never>?
    @State private var pressStart: Date?

    var body: some View {
        HStack(spacing: 6) {
            Text("tap to write, hold to speak")
                .font(Theme.dmSans(13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .blur(radius: isHolding ? 4 : 0)
                .opacity(isHolding ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background {
            Capsule()
                .fill(Theme.background)
                .modifier(OptionalMatchedGeometry(id: "composerPill", namespace: namespace))
        }
        .overlay {
            Capsule()
                .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                .modifier(OptionalMatchedGeometry(id: "composerBorder", namespace: namespace))
        }
        .overlay {
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.divider.opacity(0.22))
                    .frame(height: proxy.size.height * holdProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .clipShape(Capsule())
                    .animation(.linear(duration: holdDuration), value: holdProgress)
            }
        }
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding else { return }
                    beginHold()
                }
                .onEnded { _ in
                    endHold()
                }
        )
    }

    private func beginHold() {
        isHolding = true
        holdTriggered = false
        pressStart = Date()

        impactFeedback(style: .light)

        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1
        }

        holdTimer = Task {
            try? await Task.sleep(for: .milliseconds(Int(holdDuration * 1000)))
            guard !Task.isCancelled else { return }
            holdTriggered = true
            impactFeedback(style: .medium)
            onLongPress()
        }
    }

    private func impactFeedback(style: ImpactFeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style.uiImpactFeedbackStyle)
        generator.impactOccurred()
        #endif
    }

    private func endHold() {
        let wasTap = !holdTriggered && (pressStart.map { Date().timeIntervalSince($0) < holdDuration } ?? true)

        holdTimer?.cancel()
        holdTimer = nil

        withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
            holdProgress = 0
        }

        if wasTap && !holdTriggered {
            onTap()
        }
    }
}

private enum ImpactFeedbackStyle {
    case light
    case medium

    #if canImport(UIKit)
    var uiImpactFeedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:
            return .light
        case .medium:
            return .medium
        }
    }
    #endif
}

private struct OptionalMatchedGeometry: ViewModifier {
    let id: String
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
