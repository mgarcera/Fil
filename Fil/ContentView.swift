import SwiftUI
import SwiftData
import PhotosUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// A value identity (UUID) for the presented fil sheet, so `.sheet(item:)` doesn't bind to the
/// SwiftData Note object and re-present when the note churns from a background save.
private struct PresentedFil: Identifiable {
    let id: UUID
}

struct ContentView: View {
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedNote: Note?
    @State private var recorder = VoiceRecorderViewModel()
    @State private var showFilSetup = false
    @State private var searchActive = false          // composer search/X ↔ canvas: search vs compose
    @State private var folderInteriorOpen = false      // canvas → hide chrome inside a folder interior
    @State private var homeDeepLink: HomeDeepLink?      // Lock Screen widget tap → open the Bin / a folder

    /// First-party, on-device activation instrumentation (no third-party SDK). Epoch seconds.
    /// (The first-fil payoff — congrats, "from mason" seed, review ask — now lives in CanvasHome,
    /// where creation happens.)
    @AppStorage("firstLaunchAt") private var firstLaunchAt: Double = 0
    @FocusState private var isComposerFocused: Bool
    @State private var isCreatingTextEntry = false
    private let temporaryDraftStore = TemporaryFilDraftStore.shared
    @State private var temporaryDraft = TemporaryFilDraftStore.shared.draft
    @State private var creatingFilIDs: [UUID] = []
    @State private var filSheetPath: [FilSheetRoute] = []
    @State private var pendingPinnedNoteID: UUID?
    @State private var activeScreensaverMode: FilScreensaverView.Mode?
    @State private var showKoiPond = false
    @AppStorage("lastScreensaverMode") private var lastScreensaverModeRaw = FilScreensaverView.Mode.liquid.rawValue
    @AppStorage("autoScreensaverEnabled") private var autoScreensaverEnabled = false
    /// The Lock Screen activity choice (Off / Bin / Folder). Stored in the App Group so out-of-process
    /// captures honor it; observed here to re-sync the running activity when the user flips it.
    @AppStorage(LockScreenActivity.storageKey, store: .filAppGroup) private var lockScreenActivityRaw = LockScreenActivity.off.rawValue

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // The capture-first home: type to capture, header search to surface. Replaces the day
            // timeline + bottom composer + FABs. Text-only capture for now.
            CanvasHome(searchActive: $searchActive, screensaverActive: activeScreensaverMode != nil || showKoiPond, folderInteriorOpen: $folderInteriorOpen, deepLink: $homeDeepLink, onSettings: { SoundscapeManager.shared.playSettingsSound(); showFilSetup = true })

            // Home controls (settings, search/close, new-search refresh) all live as floating buttons
            // over the composer now — no top header.
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
            // Collapse the decorative screensaver canvas into a single VoiceOver element and,
            // crucially, expose a dismiss action so a VoiceOver user isn't trapped in it (the
            // sighted tap-to-exit isn't discoverable to them). Hidden entirely when idle.
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(activeScreensaverMode == nil && !showKoiPond)
            .accessibilityLabel("Screensaver")
            .accessibilityHint("Double tap to dismiss")
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.4)) {
                    activeScreensaverMode = nil
                    showKoiPond = false
                }
            }
        }
        // Present off a VALUE identity (the fil's UUID), not the SwiftData @Observable Note object.
        // Binding the sheet directly to the Note made SwiftUI's sheet machinery observe the object
        // and spuriously re-present it whenever the note/@Query churned from a background save — the
        // flicker. A value item is stable across those saves.
        .sheet(item: presentedFilBinding, onDismiss: handleArticleDismissed) { presented in
            if let note = notes.first(where: { $0.uuid == presented.id }) {
                FilSheetContent(note: note, filSheetPath: $filSheetPath) { route in
                    filSheetDestination(route)
                }
            }
        }
        // Each secondary sheet is hosted on its OWN Color.clear layer rather than stacked on the
        // main view alongside the article sheet. Multiple `.sheet` modifiers on one view make a
        // body re-run (e.g. a background note write) spuriously dismiss + re-present a non-last
        // sheet — the article-sheet flicker we tracked down. Isolating them keeps each independent.
        .background(secondarySheetsHost)
        .alert("Error", isPresented: .init(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .onChange(of: notes.map(\.uuid)) { _, noteIDs in
            let currentNoteIDs = Set(noteIDs)
            if let pendingPinnedNoteID, currentNoteIDs.contains(pendingPinnedNoteID) {
                openFil(with: pendingPinnedNoteID)
            }
        }
        .onOpenURL(perform: handleIncomingURL)
        // Screenshot mode opens straight onto the screen being captured. In-process, because
        // `simctl openurl` would put an "Open in Fil?" system prompt in the frame.
        .task {
            guard let stage = DemoLibrary.initialStage(folderIDsByName: DemoLibrary.seededFolderIDsByName())
            else { return }
            // Let the folders section mount first. Setting the link before it exists drops it
            // on a cold launch, which is exactly when a capture run happens.
            try? await Task.sleep(for: .milliseconds(700))
            switch stage {
            case .deepLink(let link):
                homeDeepLink = link
            case .player(let folderID, _):
                // Only the folder is opened from here. The folder interior owns `playerSelection`
                // and picks the fil up itself, so nothing has to be threaded down three views.
                homeDeepLink = .folder(folderID)
            case .pinning:
                // Driven by the folders view, which owns `togglePin` and the folder list.
                break
            case .canvas(let rawMode):
                // Set the state directly rather than calling `launchScreensaver`, which waits on
                // the 60s idle timer and on a fil-count threshold. A capture run should satisfy
                // neither: it has no touches to go idle from, and its library is fixed.
                activeScreensaverMode = FilScreensaverView.Mode(rawValue: rawMode) ?? .liquid
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                ingestSharedDrafts()
                drainPendingCapture()
            case .background:
                // Refresh the Lock Screen activity from the current Bin just before we're hidden.
                Task { await LockScreenActivityCoordinator.sync(modelContext: modelContext) }
            default:
                break
            }
        }
        .onChange(of: lockScreenActivityRaw) { _, _ in
            Task { await LockScreenActivityCoordinator.sync(modelContext: modelContext) }
        }
        .background(autoScreensaverDetector)
        .onAppear { applyScreenAwake(); drainPendingCapture() }
        .onChange(of: shouldKeepScreenAwake) { _, _ in applyScreenAwake() }
        .task {
            if firstLaunchAt == 0 { firstLaunchAt = Date.now.timeIntervalSince1970 }
            FilSelectionStore.shared.context = modelContext   // let the selection basket resolve + mutate fils
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


    /// How many fils each screensaver needs before it unlocks. Denser modes (the wave
    /// lattice, the drifting leaves field) ask for more so they don't open sparse.
    private func screensaverUnlockThreshold(for mode: FilScreensaverView.Mode) -> Int {
        switch mode {
        case .wave: return 33
        case .auroraLeaves: return 25
        case .liquid, .auroraRibbons: return 10
        }
    }

    private let koiPondUnlockThreshold = 10

    private func launchScreensaver(_ mode: FilScreensaverView.Mode) {
        guard notes.count >= screensaverUnlockThreshold(for: mode) else { return }
        lastScreensaverModeRaw = mode.rawValue
        SoundscapeManager.shared.playTransformRefilSound()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            activeScreensaverMode = mode
        }
    }

    private func launchKoiPond() {
        guard notes.count >= koiPondUnlockThreshold else { return }
        SoundscapeManager.shared.playTransformRefilSound()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            showKoiPond = true
        }
    }

    /// After a minute untouched, auto-launch a screensaver. Only while the feature is on,
    /// the library is unlocked, the app is foreground, and nothing is already covering the
    /// screen or mid-interaction (recording, keyboard, a sheet, a confirmation).
    private var autoScreensaverIdleActive: Bool {
        autoScreensaverEnabled
            && notes.count >= koiPondUnlockThreshold
            && scenePhase == .active
            && activeScreensaverMode == nil
            && !showKoiPond
            && !recorder.isRecording
            && !isComposerFocused
            && selectedNote == nil
            && !showFilSetup
    }

    /// The single source of truth for the display-sleep override: keep the screen awake
    /// while the idle feature is armed (so the screensaver can appear and persist) and
    /// while any screensaver is already showing.
    private var shouldKeepScreenAwake: Bool {
        (autoScreensaverEnabled && notes.count >= koiPondUnlockThreshold && scenePhase == .active)
            || activeScreensaverMode != nil
            || showKoiPond
    }

    @ViewBuilder
    private var autoScreensaverDetector: some View {
        #if canImport(UIKit)
        IdleScreensaverDetector(isActive: autoScreensaverIdleActive, idleDelay: 60) {
            autoLaunchScreensaver()
        }
        #endif
    }

    private func applyScreenAwake() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
        #endif
    }

    /// Launches the last-used mode if it's unlocked, otherwise the base (liquid) mode.
    private func autoLaunchScreensaver() {
        guard autoScreensaverIdleActive else { return }
        let last = FilScreensaverView.Mode(rawValue: lastScreensaverModeRaw) ?? .liquid
        let mode = notes.count >= screensaverUnlockThreshold(for: last) ? last : .liquid
        launchScreensaver(mode)
    }

    // The secondary sheets live on their own isolated host, off the main body where the article
    // sheet is presented. Stacking them alongside the article sheet made a body re-run (e.g. a
    // background note write) spuriously dismiss + re-present it — the flicker we tracked down.
    /// Value identity (the fil's UUID) for the article sheet, mirroring `selectedNote`. Presenting
    /// off this instead of the Note object keeps the sheet stable across background note saves.
    private var presentedFilBinding: Binding<PresentedFil?> {
        Binding(
            get: { selectedNote.map { PresentedFil(id: $0.uuid) } },
            set: { newValue in if newValue == nil { selectedNote = nil } }
        )
    }

    private var secondarySheetsHost: some View {
        Color.clear
            .sheet(isPresented: $showFilSetup) { filSetupSheet }
    }

    // Secondary-sheet contents, extracted so the (large) body stays type-checkable.
    private var filSetupSheet: some View {
        SettingsView(
            screensaverOptions: screensaverOptions,
            autoScreensaverUnlocked: StoreManager.shared.isPro && notes.count >= koiPondUnlockThreshold
        )
            .presentationDetents([.fraction(0.6), .large])
            .presentationBackground(Theme.background)
    }

    /// Screensaver launchers for Settings → Appearance. Each dismisses settings, then launches.
    private var screensaverOptions: [ScreensaverOption] {
        // Two gates. The first screensaver is earned by writing, so every free user reaches one and
        // the count-unlock charm survives. The rest come with Fil Extra.
        //
        // v1-route #11b described exactly this split and it was never built — nothing in the
        // screensaver system read isPro, so all five were free. Extra's non-AI half had to be
        // made, not just written down.
        let isExtra = StoreManager.shared.isPro
        func option(_ title: String, _ image: String, _ description: String,
                    unlockAt: Int, extraOnly: Bool = true,
                    launch: @escaping () -> Void) -> ScreensaverOption {
            let earned = notes.count >= unlockAt
            let unlocked = extraOnly ? (isExtra && earned) : earned
            let requirement = extraOnly && !isExtra
                ? "Comes with Fil Extra"
                : "Unlocks at \(unlockAt) thoughts"
            return ScreensaverOption(title: title, systemImage: image, description: description,
                                     isUnlocked: unlocked, requirement: requirement) {
                showFilSetup = false
                launch()
            }
        }
        return [
            option("Filosophy", "camera.filters", "A lava lamp of your thoughts.", unlockAt: screensaverUnlockThreshold(for: .liquid), extraOnly: false) { launchScreensaver(.liquid) },
            option("Filharmonic", "wave.3.left", "Let your thoughts ripple.", unlockAt: screensaverUnlockThreshold(for: .wave)) { launchScreensaver(.wave) },
            option("Filanthropy", "wind", "Watch your thoughts drift and swirl.", unlockAt: screensaverUnlockThreshold(for: .auroraLeaves)) { launchScreensaver(.auroraLeaves) },
            option("Chlorofil", "rainbow", "Your thoughts in streaks of light. Uses your latest thoughts, so they'll always change color.", unlockAt: screensaverUnlockThreshold(for: .auroraRibbons)) { launchScreensaver(.auroraRibbons) },
            option("Fillet", "fish.fill", "Your thoughts...as fish food.", unlockAt: koiPondUnlockThreshold) { launchKoiPond() },
        ]
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

    /// Drain a pending capture stamped by a Control Center control (openAppWhenRun writes the flag to
    /// the shared app group; we route it once the app is foregrounded, then clear it).
    private func drainPendingCapture() {
        let defaults = UserDefaults.filAppGroup
        guard let mode = defaults.string(forKey: "pendingCapture") else { return }
        defaults.removeObject(forKey: "pendingCapture")
        searchActive = false
        switch mode {
        case "voice":   homeDeepLink = .voice
        case "compose": homeDeepLink = .compose
        default:        break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if let pinnedNoteID = pinnedNoteID(from: url) {
            openFil(with: pinnedNoteID)
            return
        }

        // Live Activity taps. Recognized here so they aren't misread as draft text below.
        if url.scheme?.lowercased() == "fil" {
            let host = (url.host() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            switch host {
            case "basket":
                // Pop to the folders home root, where the Bin dock is visible.
                searchActive = false
                homeDeepLink = .bin
                SoundscapeManager.shared.playOpenFilClick()
                return
            case "folder":
                // Open the tapped folder's interior. The folders section routes it once it mounts.
                if let id = folderID(from: url) {
                    searchActive = false
                    homeDeepLink = .folder(id)
                    SoundscapeManager.shared.playOpenFilClick()
                }
                return
            case "capture-compose":
                // Control Center "compose" control: open the composer, keyboard up.
                searchActive = false
                homeDeepLink = .compose
                return
            case "capture-voice":
                // Control Center "voice" control: open and start a voice fil immediately.
                searchActive = false
                homeDeepLink = .voice
                return
            default:
                break
            }
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

    /// Parses the `id` query item of `fil://folder?id=<uuid>` (the pinned-folder widget / activity).
    private func folderID(from url: URL) -> UUID? {
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
        filSheetPath.removeAll()
        selectedNote = note
    }

    /// Runs on launch / app-active: promotes every out-of-app capture into a real unfiled fil (the
    /// Bin), then re-syncs the Lock Screen activity from the true Bin. Share-extension image drops
    /// still become fils directly; its text/link drops stage in the buffer alongside Action-Button
    /// captures and are drained together.
    private func ingestSharedDrafts() {
        let drafts = SharedDraftInbox.drain()

        var directToFil: [SharedDraftInbox.InboundDraft] = []
        for draft in drafts {
            let caption = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.images.isEmpty && !caption.isEmpty {
                FilBasketStore.shared.add(text: caption)
            } else {
                directToFil.append(draft)
            }
        }

        Task {
            if !directToFil.isEmpty { await createFils(from: directToFil) }
            drainCaptureBuffer()
            await LockScreenActivityCoordinator.sync(modelContext: modelContext)
        }
    }

    /// Empties the out-of-app capture buffer into real unfiled fils. Links become link fils; anything
    /// else becomes a plain text fil (no generated title — matches the home's inline capture).
    private func drainCaptureBuffer() {
        let staged = FilBasketStore.shared.drain()
        guard !staged.isEmpty else { return }

        for item in staged {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let gradient = freshGradientPair()
            if let linkURL = normalizedLinkURL(from: text) {
                LinkFil.make(url: linkURL, gradient: gradient, uuid: UUID(), in: modelContext)
            } else {
                let note = Note(
                    title: "",
                    transcript: text,
                    keyword: "",
                    gradientStartHex: gradient.start,
                    gradientEndHex: gradient.end
                )
                modelContext.insert(note)
            }
        }
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
        LinkFil.normalizedURL(from: text)
    }

    private func saveLinkNote(for url: URL, filID: UUID) {
        LinkFil.make(url: url, gradient: freshGradientPair(), uuid: filID, in: modelContext)
        SoundscapeManager.shared.playArticleMadeSound()
    }

    private func saveImageFil(caption: String, imageData: [Data], todos: [String] = [], filID: UUID) async throws {
        // Photos have no title (see Note.displayBadgeText); the caption is the note.
        let gradient = freshGradientPair()
        let note = Note(
            title: "",
            transcript: caption,
            todos: todos,
            keyword: "",
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
        todos: [String] = [],
        filID: UUID
    ) async throws {
        // No AI title: the first line of the transcript is the title (Note.titleLine). For a to-do-only
        // fil (no transcript), fall back to the first to-do so the card still reads meaningfully.
        let title = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (todos.first ?? "")
            : ""

        let gradient = freshGradientPair()
        let note = Note(
            title: title,
            transcript: transcript,
            audioFilePath: audioFilePath,
            duration: duration,
            todos: todos,
            keyword: title,
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


/// The content of the fil sheet. Crucially, it *owns* the presentation-detent selection
/// as local `@State` instead of ContentView. Dragging between detents therefore only
/// re-evaluates this small view (and ArticleView) — not ContentView's body, which would
/// otherwise rebuild the entire home grid (re-grouping every note) on each drag update.
private struct FilSheetContent<Destination: View>: View {
    let note: Note
    @Binding var filSheetPath: [FilSheetRoute]
    @ViewBuilder let destination: (FilSheetRoute) -> Destination

    @State private var detent: PresentationDetent

    init(
        note: Note,
        filSheetPath: Binding<[FilSheetRoute]>,
        @ViewBuilder destination: @escaping (FilSheetRoute) -> Destination
    ) {
        self.note = note
        self._filSheetPath = filSheetPath
        self.destination = destination
        _detent = State(initialValue: note.isLinkFil ? .fraction(0.2) : .fraction(0.6))
    }

    private var availableDetents: Set<PresentationDetent> {
        note.isLinkFil ? [.fraction(0.2)] : [.fraction(0.6), .large]
    }

    var body: some View {
        NavigationStack(path: $filSheetPath) {
            ArticleView(
                note: note,
                ignoresTopSafeArea: false,
                showsCloseButton: true,
                filSheetPath: $filSheetPath,
                selectedPresentationDetent: $detent
            )
            .navigationDestination(for: FilSheetRoute.self) { route in
                destination(route)
            }
        }
        .presentationDetents(availableDetents, selection: $detent)
        .presentationBackground(Theme.background)
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
