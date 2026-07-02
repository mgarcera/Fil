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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedNote: Note?
    @State private var recorder = VoiceRecorderViewModel()
    @State private var showPermissionAlert = false
    @State private var showFilSetup = false
    @FocusState private var isComposerFocused: Bool
    @State private var textEntryText = ""
    @State private var selectedComposerPhotos: [PhotosPickerItem] = []
    @State private var stagedComposerImageData: [Data] = []
    @State private var isCreatingTextEntry = false
    private let temporaryDraftStore = TemporaryFilDraftStore.shared
    @State private var temporaryDraft = TemporaryFilDraftStore.shared.draft
    @AppStorage("isDarkMode") private var isDarkMode = true
    @Namespace private var composerNamespace
    @Namespace private var filCreationNamespace
    @State private var creatingFilIDs: [UUID] = []
    @State private var visibleTip = emptyStateTip
    @State private var showHomeFocusSheet = false
    @State private var selectedNoteDetent = PresentationDetent.fraction(0.6)
    @State private var filSheetPath: [FilSheetRoute] = []
    @State private var homeFocusDetent = PresentationDetent.fraction(0.3)
    @State private var selectedNoteIDs = Set<UUID>()
    @State private var landfillingNoteIDs = Set<UUID>()
    @State private var showBulkLandfilConfirmation = false
    @State private var pendingHomeFocusSelection: HomeFocusSelection?
    @State private var pendingPinnedNoteID: UUID?
    @State private var sectionCollapseCommandID = 0
    @State private var sectionCollapseCommandStage = 0
    @State private var activeScreensaverMode: FilScreensaverView.Mode?
    @State private var showKoiPond = false
    @AppStorage("lastScreensaverMode") private var lastScreensaverModeRaw = FilScreensaverView.Mode.liquid.rawValue
    @AppStorage("collapsedDaySectionKeys") private var collapsedDaySectionKeysRaw = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if notes.isEmpty {
                        AnimatedGradientRevealText(text: visibleTip)
                            .font(Theme.dmSans(15, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .blur(radius: isComposerFocused ? 8 : 0)
                            .opacity(isComposerFocused ? 0 : 1)
                            .animation(.easeInOut(duration: 0.3), value: isComposerFocused)
                    }

                    notesSection
                }
                // Clear the floating header so content starts below it, then scrolls under.
                .padding(.top, 64)
                .padding(.bottom, 100)
            }
            .frame(maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if isComposerFocused {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isComposerFocused = false }
                }
            }
            .overlay(alignment: .bottom) {
                bottomComposer
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .zIndex(1)
            }

            // The header floats as a top-pinned sibling (not a ScrollView overlay) so its
            // glass controls reliably receive taps while content scrolls beneath it.
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }
        }
        .overlay {
            // The full-bleed frame lives on this always-present container that ignores
            // the safe area, so it is established before the screensaver is inserted.
            // Only opacity/scale transition inside it — the Canvas is full-screen from
            // its first frame, so the centered blob block never repositions on open/close.
            ZStack {
                if let mode = activeScreensaverMode {
                    FilScreensaverView(
                        notes: notes,
                        initialMode: mode,
                        onModeChanged: { lastScreensaverModeRaw = $0.rawValue }
                    ) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            activeScreensaverMode = nil
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                if showKoiPond {
                    AquariumView(blobs: FilScreensaverView.buildBlobs(from: notes)) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showKoiPond = false
                        }
                    }
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
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
        .onChange(of: selectedComposerPhotos) { _, newItems in
            if !newItems.isEmpty {
                isComposerFocused = true
            }
            Task {
                await loadStagedComposerImages(from: newItems)
            }
        }
        .onChange(of: notes.map(\.uuid)) { _, noteIDs in
            let currentNoteIDs = Set(noteIDs)
            selectedNoteIDs.formIntersection(currentNoteIDs)
            landfillingNoteIDs.formIntersection(currentNoteIDs)

            if let pendingPinnedNoteID, currentNoteIDs.contains(pendingPinnedNoteID) {
                openFil(with: pendingPinnedNoteID)
            }
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                ingestSharedDrafts()
            }
        }
        .task {
            ingestSharedDrafts()
        }
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
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    SoundscapeManager.shared.playSettingsSound()
                    showFilSetup = true
                } label: {
                    Image("FilLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
                .accessibilityLabel("Settings")

                Spacer()

                HStack(spacing: 4) {
                    Menu {
                        Section("Screensavers") {
                            Button {
                                launchScreensaver(.liquid)
                            } label: {
                                Label("filosophy", systemImage: "camera.filters")
                            }
                            Button {
                                launchScreensaver(.wave)
                            } label: {
                                Label("filharmonic", systemImage: "light.overhead.left")
                            }
                            Button {
                                launchScreensaver(.auroraLeaves)
                            } label: {
                                Label("filanthropy", systemImage: "water.waves")
                            }
                            Button {
                                launchScreensaver(.auroraRibbons)
                            } label: {
                                Label("chlorofil", systemImage: "rainbow")
                            }
                            Button {
                                launchKoiPond()
                            } label: {
                                Label("fillet", systemImage: "fish.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "zzz")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(notes.isEmpty)
                    .opacity(notes.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Screensaver")

                    Button {
                        SoundscapeManager.shared.playLightModeSound()
                        withAnimation(.snappy) { isDarkMode.toggle() }
                    } label: {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .glassEffect()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func launchScreensaver(_ mode: FilScreensaverView.Mode) {
        guard !notes.isEmpty else { return }
        lastScreensaverModeRaw = mode.rawValue
        SoundscapeManager.shared.playTransformRefilSound()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            activeScreensaverMode = mode
        }
    }

    private func launchKoiPond() {
        guard !notes.isEmpty else { return }
        SoundscapeManager.shared.playTransformRefilSound()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            showKoiPond = true
        }
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
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                if showsSectionToggleFAB {
                    HStack {
                        Spacer()
                        sectionToggleFAB
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                composerContent
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: showsSectionToggleFAB)
        }
    }

    /// The expand/collapse control lives as a floating glass button above the composer
    /// (Apple Maps style), sharing the composer's glass container. Hidden when there's
    /// nothing to collapse or while recording / bulk-selecting so it never crowds it.
    private var showsSectionToggleFAB: Bool {
        !allDaySectionKeys.isEmpty && !isSelectingNotes && !recorder.isRecording
    }

    private var sectionToggleFAB: some View {
        Button {
            toggleAllDaySections()
        } label: {
            Image(systemName: areAllDaySectionsCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(areAllDaySectionsCollapsed ? "Expand all sections" : "Collapse all sections")
    }

    @ViewBuilder
    private var composerContent: some View {
        Group {
            if isSelectingNotes {
                bulkSelectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    if !creatingFilIDs.isEmpty {
                        creatingFilIndicator
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let draft = temporaryDraft, !recorder.isRecording {
                        temporaryDraftBar(draft)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    composerBar
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: recorder.isRecording)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: isSelectingNotes)
    }

    private var composerBar: some View {
        ComposerBar(
            text: $textEntryText,
            selectedPhotos: $selectedComposerPhotos,
            stagedImageData: stagedComposerImageData,
            isRecording: recorder.isRecording,
            recordingDuration: recorder.recordingDuration,
            isProcessing: isCreatingTextEntry,
            focus: $isComposerFocused,
            onSend: {
                Task { await createTextEntry(from: textEntryText) }
            },
            onStartRecording: { startRecording() },
            onStopRecording: { stopRecording() },
            onRemoveStagedImage: removeStagedComposerImage
        )
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

    @ViewBuilder
    private var notesSection: some View {
        if notes.isEmpty && creatingFilIDs.isEmpty {
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
                creatingFilIDs: creatingFilIDs,
                creationNamespace: filCreationNamespace,
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
                    .glassEffect(.regular, in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text("\(selectedNoteIDs.count) selected")
                .font(Theme.dmSans(13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 20)
                .frame(height: 40)
                .glassEffect(.regular, in: .capsule)
                .contentShape(Capsule())

            Button {
                showBulkLandfilConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(Theme.recordRed), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func temporaryDraftBar(_ draft: TemporaryFilDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                textEntryText = draft.text
                temporaryDraftStore.clear()
                temporaryDraft = nil
                isComposerFocused = true
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
                .glassEffect(.regular, in: .capsule)
                .contentShape(Capsule())
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
                    .glassEffect(.regular, in: .circle)
                    .contentShape(Circle())
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
                    .glassEffect(.regular, in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var creatingFilIndicator: some View {
        HStack(spacing: 8) {
            CreatingFilBlobView()
                .frame(width: 20, height: 20)
            Text(creatingFilIDs.count > 1 ? "creating \(creatingFilIDs.count) fils…" : "creating fil…")
                .font(Theme.dmSans(12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
        .contentShape(Capsule())
    }

    /// Adds a placeholder blob to the grid's top slot and returns its id — used as the
    /// new fil's `uuid` so the blob can morph into the real card once it's created.
    private func beginCreatingFil() -> UUID {
        let id = UUID()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            creatingFilIDs.append(id)
        }
        return id
    }

    /// Removes the placeholder, letting its just-created card surface and morph into place.
    private func finishCreatingFil(_ id: UUID) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            creatingFilIDs.removeAll { $0 == id }
        }
    }

    /// Shared wrapper for every fil-creation path: shows the creating blob, runs the
    /// build closure (which must insert a note whose `uuid` is the provided id), then
    /// morphs the blob into the resulting card.
    @MainActor
    private func createFil(_ build: (UUID) async throws -> Void) async {
        let filID = beginCreatingFil()
        isCreatingTextEntry = true
        SoundscapeManager.shared.startMeshDuringProcessSound()

        var succeeded = false
        do {
            try await build(filID)
            succeeded = true
        } catch {
            recorder.errorMessage = error.localizedDescription
        }

        isCreatingTextEntry = false
        SoundscapeManager.shared.stopMeshDuringProcessSound()

        // Let the inserted note surface in the query before morphing the blob into it.
        if succeeded {
            try? await Task.sleep(for: .milliseconds(300))
        }
        finishCreatingFil(filID)
    }

    private func handleIncomingURL(_ url: URL) {
        if let pinnedNoteID = pinnedNoteID(from: url) {
            openFil(with: pinnedNoteID)
            return
        }

        guard let text = TemporaryFilDraftIntake.text(from: url) else { return }

        temporaryDraftStore.hold(text)
        temporaryDraft = temporaryDraftStore.draft
        SoundscapeManager.shared.playOpenFilClick()
    }

    /// Parses `fil://pinned?id=<uuid>` (from the pinned-fil Live Activity / widget).
    private func pinnedNoteID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "fil" else { return nil }

        let host = url.host()?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "pinned" || path == "pinned" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let idValue = components?.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        return UUID(uuidString: idValue)
    }

    private func openFil(with id: UUID) {
        guard let note = notes.first(where: { $0.uuid == id }) else {
            // The query may not have loaded yet on a cold launch; retry when notes populate.
            pendingPinnedNoteID = id
            return
        }
        pendingPinnedNoteID = nil
        SoundscapeManager.shared.playOpenFilClick()
        selectedNoteDetent = initialSelectedNoteDetent(for: note)
        filSheetPath.removeAll()
        selectedNote = note
    }

    /// Drains content shared into Fil from the Share Extension (via the App Group inbox)
    /// and turns each item straight into a fil — no intermediate draft state.
    private func ingestSharedDrafts() {
        let drafts = SharedDraftInbox.drain()
        guard !drafts.isEmpty else { return }
        Task { await createFils(from: drafts) }
    }

    @MainActor
    private func createFils(from drafts: [SharedDraftInbox.InboundDraft]) async {
        for draft in drafts {
            let caption = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            await createFil { filID in
                if !draft.images.isEmpty {
                    try await saveImageFil(
                        caption: caption.isEmpty ? "Shared photo" : caption,
                        imageData: draft.images,
                        filID: filID
                    )
                } else if let linkURL = normalizedLinkURL(from: caption) {
                    saveLinkNote(for: linkURL, filID: filID)
                } else if !caption.isEmpty {
                    try await saveGeneratedNote(from: caption, filID: filID)
                }
            }
        }
    }

    private func createFilFromTemporaryDraft(_ draft: TemporaryFilDraft) async {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            temporaryDraftStore.clear()
            temporaryDraft = nil
            return
        }

        withAnimation(.snappy) {
            temporaryDraftStore.clear()
            temporaryDraft = nil
        }

        await createFil { filID in
            try await saveGeneratedNote(from: trimmed, filID: filID)
        }
    }

    private func startRecording() {
        Task {
            let granted = await recorder.requestPermissions()
            if granted {
                isComposerFocused = false
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
        Task {
            await createFil { filID in
                let transcript = try await recorder.transcribe(url: url)
                try await saveGeneratedNote(
                    from: transcript,
                    audioFilePath: url.lastPathComponent,
                    duration: duration,
                    filID: filID
                )
            }
            recorder.isProcessing = false
        }
    }

    private func createTextEntry(from text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let stagedImages = stagedComposerImageData
        isComposerFocused = false
        textEntryText = ""
        selectedComposerPhotos = []
        stagedComposerImageData = []

        await createFil { filID in
            if !stagedImages.isEmpty {
                try await saveImageFil(caption: trimmed, imageData: stagedImages, filID: filID)
            } else if let linkURL = normalizedLinkURL(from: trimmed) {
                saveLinkNote(for: linkURL, filID: filID)
            } else {
                try await saveGeneratedNote(from: trimmed, filID: filID)
            }
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

    private func saveLinkNote(for url: URL, filID: UUID) {
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
        note.uuid = filID
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

    private func saveImageFil(caption: String, imageData: [Data], filID: UUID) async throws {
        let metadata = try await ArticleGenerationService.shared.generateMetadata(
            from: caption,
            userProfile: activeUserProfile
        )

        let gradient = freshGradientPair()
        let note = Note(
            title: metadata.keyword,
            transcript: caption,
            articleBody: "",
            keyword: metadata.keyword,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.uuid = filID
        note.imageFilImages = imageData.enumerated().map { index, data in
            NoteImage(data: data, order: index, note: note)
        }
        modelContext.insert(note)
        SoundscapeManager.shared.playArticleMadeSound()
    }

    private func saveGeneratedNote(
        from transcript: String,
        audioFilePath: String = "",
        duration: TimeInterval = 0,
        filID: UUID
    ) async throws {
        let metadata = try await ArticleGenerationService.shared.generateMetadata(
            from: transcript,
            userProfile: activeUserProfile
        )

        let gradient = freshGradientPair()
        let note = Note(
            title: metadata.keyword,
            transcript: transcript,
            articleBody: "",
            audioFilePath: audioFilePath,
            duration: duration,
            todos: metadata.todos,
            keyword: metadata.keyword,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.uuid = filID
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

private struct FocusEntryButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(displayCount)")
                .font(Theme.dmSans(14, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var displayCount: String {
        count > 99 ? "99+" : "\(count)"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
