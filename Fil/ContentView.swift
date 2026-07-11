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
    @State private var surfaceRequested = false      // header search → canvas "surface a thought"

    @Environment(\.requestReview) private var requestReview
    /// Ask for a rating at most once, after the user has felt the core loop a few times.
    @AppStorage("didRequestReview") private var didRequestReview = false

    // First-run onboarding (action-first + "from mason" seed fil). See docs/onboarding/.
    @AppStorage("didSeedWelcomeFil") private var didSeedWelcomeFil = false
    /// First-party, on-device activation instrumentation (no third-party SDK). Epoch seconds.
    @AppStorage("firstLaunchAt") private var firstLaunchAt: Double = 0
    @AppStorage("firstUserFilAt") private var firstUserFilAt: Double = 0
    /// True only while the welcome seed fil is animating in, so it isn't counted as a user fil.
    @State private var isSeedingWelcomeFil = false
    @State private var showWelcomeCongrats = false
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

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Blank-canvas home (blank-canvas-home branch): tap to capture, header search to surface.
            // Replaces the day timeline + bottom composer + FABs. Text-only capture for now.
            BlankCanvasPrototype(showsChrome: false, surfaceRequested: $surfaceRequested)

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
            // Collapse the decorative screensaver canvas into a single VoiceOver element and,
            // crucially, expose a dismiss action so a VoiceOver user isn't trapped in it (the
            // sighted tap-to-exit isn't discoverable to them). Hidden entirely when idle.
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(activeScreensaverMode == nil && !showKoiPond)
            .accessibilityLabel("screensaver")
            .accessibilityHint("double tap to dismiss")
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                ingestSharedDrafts()
            }
        }
        .background(autoScreensaverDetector)
        .onAppear { applyScreenAwake() }
        .onChange(of: shouldKeepScreenAwake) { _, _ in applyScreenAwake() }
        .task {
            if firstLaunchAt == 0 { firstLaunchAt = Date.now.timeIntervalSince1970 }
            ingestSharedDrafts()
        }
        .overlay {
            if showWelcomeCongrats {
                welcomeCongratsOverlay
                    .transition(.opacity)
            }
        }
    }

    /// A quiet, calm beat after the user's first fil — no confetti. Fades before the seed reveal.
    private var welcomeCongratsOverlay: some View {
        ZStack {
            Theme.background.opacity(0.55).ignoresSafeArea()
            Text("that's a fil.\nit's yours.")
                .font(Theme.dmSans(24, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
        }
        .allowsHitTesting(false)
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
                    // Blank-canvas home: asks the canvas to "surface a thought".
                    Button {
                        surfaceRequested = true
                    } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(notes.isEmpty)
                    .opacity(notes.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Search your thoughts")
                }
                .padding(.horizontal, 6)
                .glassEffect()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
            autoScreensaverUnlocked: notes.count >= koiPondUnlockThreshold
        )
            .presentationDetents([.fraction(0.6)])
            .presentationBackground(Theme.background)
    }

    /// Screensaver launchers for Settings → Appearance. Each dismisses settings, then launches.
    private var screensaverOptions: [ScreensaverOption] {
        func option(_ title: String, _ image: String, unlockAt: Int, launch: @escaping () -> Void) -> ScreensaverOption {
            ScreensaverOption(title: title, systemImage: image, isUnlocked: notes.count >= unlockAt, requirement: "\(unlockAt) fils") {
                showFilSetup = false
                launch()
            }
        }
        return [
            option("filosophy", "camera.filters", unlockAt: screensaverUnlockThreshold(for: .liquid)) { launchScreensaver(.liquid) },
            option("filharmonic", "wave.3.left", unlockAt: screensaverUnlockThreshold(for: .wave)) { launchScreensaver(.wave) },
            option("filanthropy", "wind", unlockAt: screensaverUnlockThreshold(for: .auroraLeaves)) { launchScreensaver(.auroraLeaves) },
            option("chlorofil", "rainbow", unlockAt: screensaverUnlockThreshold(for: .auroraRibbons)) { launchScreensaver(.auroraRibbons) },
            option("fillet", "fish.fill", unlockAt: koiPondUnlockThreshold) { launchKoiPond() },
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

        guard succeeded else { return }
        // The welcome seed fil also runs through createFil — don't treat it as a user fil.
        guard !isSeedingWelcomeFil else { return }

        if firstUserFilAt == 0 { firstUserFilAt = Date.now.timeIntervalSince1970 }
        maybeRequestReview()
        maybeRevealWelcomeFil()
    }

    /// After the user's own first fil, offer a quiet congratulation, then reveal the one-time
    /// "from mason" seed fil — animated in through the normal creation path so the reveal itself
    /// demonstrates the creation blob + discoverability. Runs exactly once, ever.
    private func maybeRevealWelcomeFil() {
        guard !didSeedWelcomeFil else { return }
        didSeedWelcomeFil = true
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.5)) { showWelcomeCongrats = true }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.smooth(duration: 0.5)) { showWelcomeCongrats = false }
            try? await Task.sleep(for: .milliseconds(350))
            isSeedingWelcomeFil = true
            await createFil { filID in insertWelcomeFil(filID) }
            isSeedingWelcomeFil = false
        }
    }

    /// Builds the fixed "from mason" seed fil (no AI) with two sample filaments. Deletable like
    /// any fil; seeded only once (guarded by `didSeedWelcomeFil`).
    private func insertWelcomeFil(_ filID: UUID) {
        let note = Note(
            title: WelcomeFil.title,
            transcript: WelcomeFil.transcript,
            keyword: WelcomeFil.title,
            gradientStartHex: WelcomeFil.gradientStart,
            gradientEndHex: WelcomeFil.gradientEnd
        )
        note.uuid = filID

        let filament = KeywordAttachment(keyword: WelcomeFil.filamentKeyword, note: note)
        filament.entries = [AttachmentEntry(kind: .textNote, text: WelcomeFil.filamentNote, noteTitle: WelcomeFil.filamentNoteTitle)]
        // The "here" filament holds a tutorial video: copy the bundled clip into the documents dir
        // (where .video entries resolve) so it behaves like any user-added video.
        let example = KeywordAttachment(keyword: WelcomeFil.exampleKeyword, note: note)
        if let bundledVideo = Bundle.main.url(
            forResource: WelcomeFil.exampleVideoResource,
            withExtension: WelcomeFil.exampleVideoExtension
        ) {
            // Named for how it should read in the QuickLook title bar ("a vid").
            let filename = "a vid.\(WelcomeFil.exampleVideoExtension)"
            let dest = AudioPlayerViewModel.recordingsDirectory.appendingPathComponent(filename)
            // Decoded path: the space in "a vid.mp4" would percent-encode under .path(), so
            // fileExists(atPath:) must use the real filesystem path or it never finds the copy.
            let destPath = dest.path(percentEncoded: false)
            if !FileManager.default.fileExists(atPath: destPath) {
                try? FileManager.default.copyItem(at: bundledVideo, to: dest)
                FileProtection.protectAtRest(dest)
            }
            if FileManager.default.fileExists(atPath: destPath) {
                example.entries = [AttachmentEntry.video(path: filename)]
            }
        }
        note.attachments = [filament, example]

        modelContext.insert(note)
        SoundscapeManager.shared.playArticleMadeSound()
    }

    /// Requests an App Store review after a genuine "aha" moment — a fil the user just made —
    /// but only once, and only after they've created a few fils, so the ask lands on a happy beat
    /// rather than cold. StoreKit itself further throttles how often the prompt actually shows.
    private func maybeRequestReview() {
        guard !didRequestReview, notes.count >= 3 else { return }
        didRequestReview = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
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
            modelContext.saveOrLog()
        }
    }

    private func linkTitleFallback(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain
    }

    private func saveImageFil(caption: String, imageData: [Data], todos: [String] = [], filID: UUID) async throws {
        let title = caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (todos.first ?? "")
            : await ArticleGenerationService.shared.generateTitle(from: caption)

        let gradient = freshGradientPair()
        let note = Note(
            title: title,
            transcript: caption,
            todos: todos,
            keyword: title,
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
        // A title is generated from the thought. When there's no thought (a to-do-only fil),
        // fall back to the first to-do so the card still reads meaningfully.
        let title: String
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = todos.first ?? ""
        } else {
            title = await ArticleGenerationService.shared.generateTitle(from: transcript)
        }

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
