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
    @State private var showPermissionAlert = false
    @State private var showMicPriming = false
    @State private var showTodoSheet = false
    @State private var showFilSetup = false

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
    @FocusState private var isSearchFieldFocused: Bool
    @State private var textEntryText = ""
    @State private var pendingComposerTodos: [ComposerTodo] = []
    @State private var selectedComposerPhotos: [PhotosPickerItem] = []
    @State private var stagedComposerImageData: [Data] = []
    @State private var isCreatingTextEntry = false
    private let temporaryDraftStore = TemporaryFilDraftStore.shared
    @State private var temporaryDraft = TemporaryFilDraftStore.shared.draft
    @AppStorage("isDarkMode") private var isDarkMode = true
    @Namespace private var composerNamespace
    @Namespace private var filCreationNamespace
    @State private var creatingFilIDs: [UUID] = []
    @State private var filSheetPath: [FilSheetRoute] = []
    @State private var selectedNoteIDs = Set<UUID>()
    @State private var landfillingNoteIDs = Set<UUID>()
    @State private var showBulkLandfilConfirmation = false
    @State private var pendingPinnedNoteID: UUID?
    @State private var activeScreensaverMode: FilScreensaverView.Mode?
    @State private var showKoiPond = false
    @State private var isSearching = false
    @State private var searchText = ""
    @AppStorage("lastScreensaverMode") private var lastScreensaverModeRaw = FilScreensaverView.Mode.liquid.rawValue
    @AppStorage("autoScreensaverEnabled") private var autoScreensaverEnabled = false
    @AppStorage("collapsedDaySectionKeys") private var collapsedDaySectionKeysRaw = ""
    /// Live, animatable set of collapsed day-section keys. @AppStorage above is the
    /// persistence mirror (seeded in init, written on change) — this is what drives the
    /// animation, because @AppStorage changes don't tween under withAnimation.
    @State private var collapsedDayKeys: Set<String> = []

    init() {
        // Seed the live set from persisted storage so collapsed sections are correct on the
        // very first render (no expand→collapse flash on launch).
        let raw = UserDefaults.standard.string(forKey: "collapsedDaySectionKeys") ?? ""
        let keys = raw.split(separator: "\n").compactMap { line -> String? in
            let key = line.split(separator: "|", maxSplits: 1).first.map(String.init)
            guard let key, !key.isEmpty else { return nil }
            return key
        }
        _collapsedDayKeys = State(initialValue: Set(keys))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
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
                if !isSearching {
                    bottomComposer
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .zIndex(1)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .alert("microphone access is off", isPresented: $showPermissionAlert) {
            Button("open settings") { openAppSettings() }
            Button("not now", role: .cancel) {}
        } message: {
            Text("to record a voice fil, turn on microphone and speech recognition for fil in settings. you can always type instead.")
        }
        .alert("move to landfil?", isPresented: $showBulkLandfilConfirmation) {
            Button("landfil", role: .destructive) {
                landfilSelectedNotes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedNoteIDs.count) about to be deleted. this cannot be undone.")
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
        .onOpenURL(perform: handleIncomingURL)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                ingestSharedDrafts()
            }
        }
        .background(autoScreensaverDetector)
        .onAppear { applyScreenAwake() }
        .onChange(of: shouldKeepScreenAwake) { _, _ in applyScreenAwake() }
        .onChange(of: collapsedDayKeys) { _, _ in persistCollapsedDayKeys() }
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
            if isSearching {
                searchBar
            } else {
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
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isSearching = true
                        }
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(notes.isEmpty)
                    .opacity(notes.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Search")

                    Menu {
                        Section("Screensavers") {
                            screensaverMenuButton("filosophy", systemImage: "camera.filters", unlockAt: screensaverUnlockThreshold(for: .liquid)) { launchScreensaver(.liquid) }
                            screensaverMenuButton("filharmonic", systemImage: "wave.3.left", unlockAt: screensaverUnlockThreshold(for: .wave)) { launchScreensaver(.wave) }
                            screensaverMenuButton("filanthropy", systemImage: "wind", unlockAt: screensaverUnlockThreshold(for: .auroraLeaves)) { launchScreensaver(.auroraLeaves) }
                            screensaverMenuButton("chlorofil", systemImage: "rainbow", unlockAt: screensaverUnlockThreshold(for: .auroraRibbons)) { launchScreensaver(.auroraRibbons) }
                            screensaverMenuButton("fillet", systemImage: "fish.fill", unlockAt: koiPondUnlockThreshold) { launchKoiPond() }
                        }
                        Section {
                            Button {
                                autoScreensaverEnabled.toggle()
                            } label: {
                                Text(autoScreensaverEnabled ? "auto is on" : "auto is off")
                                Text("start after 60 seconds idle. keeps your screen awake.")
                                if autoScreensaverEnabled {
                                    Image(systemName: "power")
                                }
                            }
                            .disabled(notes.count < koiPondUnlockThreshold)
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
                    .accessibilityLabel(isDarkMode ? "switch to light mode" : "switch to dark mode")
                }
                .padding(.horizontal, 6)
                .glassEffect()
            }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearching)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)

                TextField("search fils", text: $searchText)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.primaryText)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .glassEffect(in: .rect(cornerRadius: 23))

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSearching = false
                }
                searchText = ""
                isSearchFieldFocused = false
            } label: {
                Text("cancel")
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.primaryText)
            }
            .buttonStyle(.plain)
        }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Live, in-memory search across a fil's body, title/keyword, and keyword
    /// attachments. Case-insensitive substring match; empty query shows everything.
    private var filteredNotes: [Note] {
        let query = trimmedSearch.lowercased()
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.transcript.lowercased().contains(query)
                || note.title.lowercased().contains(query)
                || note.keyword.lowercased().contains(query)
                || note.attachments.contains { $0.keyword.lowercased().contains(query) }
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

    /// A screensaver entry in the menu. Locked below its threshold: disabled, with a
    /// lock icon and the "· N fils" requirement appended to its title.
    @ViewBuilder
    private func screensaverMenuButton(_ title: String, systemImage: String, unlockAt: Int, action: @escaping () -> Void) -> some View {
        let unlocked = notes.count >= unlockAt
        Button(action: action) {
            Label(unlocked ? title : "\(title) · \(unlockAt) fils", systemImage: unlocked ? systemImage : "lock.fill")
        }
        .disabled(!unlocked)
    }

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
            && !showBulkLandfilConfirmation
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

    private var allDaySectionKeys: [String] {
        let dayPartition = FilDayPartition()
        let keys = Set(notes.map { note in
            Self.daySectionKeyFormatter.string(from: dayPartition.dayStart(for: note.timestamp))
        })
        return keys.sorted()
    }

    private var areAllDaySectionsCollapsed: Bool {
        let keys = allDaySectionKeys
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { collapsedDayKeys.contains($0) }
    }

    /// Mirrors the live @State back to @AppStorage for persistence. Kept separate from the
    /// animation driver: @AppStorage changes don't participate in withAnimation, so driving
    /// the animation off it makes the collapse snap instead of tween.
    private func persistCollapsedDayKeys() {
        collapsedDaySectionKeysRaw = collapsedDayKeys
            .sorted()
            .map { "\($0)|2" }
            .joined(separator: "\n")
    }

    private func toggleCollapsedDayKey(_ key: String) {
        if collapsedDayKeys.contains(key) {
            collapsedDayKeys.remove(key)
        } else {
            collapsedDayKeys.insert(key)
        }
    }

    private func toggleAllDaySections() {
        let shouldCollapse = !areAllDaySectionsCollapsed
        if shouldCollapse {
            SoundscapeManager.shared.playCollapsePartTwoSound()
        } else {
            SoundscapeManager.shared.playCollapsingSound()
        }

        // Mutate the animatable @State Set inside withAnimation. Every DaySectionView reads
        // its collapsed state from this Set in body, so this single change animates all
        // sections together via Core Animation — the same one-transaction path that makes
        // the search (forceExpanded) collapse smooth. Persistence happens via onChange.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            collapsedDayKeys = shouldCollapse ? Set(allDaySectionKeys) : []
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

    private var isSelectingNotes: Bool {
        !selectedNoteIDs.isEmpty
    }

    private var selectedNotes: [Note] {
        notes.filter { selectedNoteIDs.contains($0.uuid) }
    }

    private var bottomComposer: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                if showsSectionToggleFAB || showsTodoFAB {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if showsSectionToggleFAB { sectionToggleFAB }
                            if showsTodoFAB { todoFAB }
                        }
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                composerContent
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: showsSectionToggleFAB)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: showsTodoFAB)
        }
    }

    /// The expand/collapse control lives as a floating glass button above the composer
    /// (Apple Maps style), sharing the composer's glass container. Hidden when there's
    /// nothing to collapse or while recording / bulk-selecting so it never crowds it.
    private var showsSectionToggleFAB: Bool {
        !allDaySectionKeys.isEmpty && !isSelectingNotes && !recorder.isRecording && !isSearching
    }

    /// Left-hand FAB, a mirror of the expand/collapse control — opens the to-dos sheet. Shown only
    /// when there are open to-dos to see.
    private var showsTodoFAB: Bool {
        openTodoCount > 0 && !isSelectingNotes && !recorder.isRecording && !isSearching
    }

    /// Total open (incomplete, non-empty) to-dos across all fils — shown as the FAB's count.
    private var openTodoCount: Int {
        notes.reduce(0) { total, note in
            total + note.todos.indices.reduce(into: 0) { subtotal, index in
                let hasText = !note.todos[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isDone = note.completedTodos.indices.contains(index) && note.completedTodos[index]
                if hasText && !isDone { subtotal += 1 }
            }
        }
    }

    private var todoFAB: some View {
        Button {
            SoundscapeManager.shared.playTabSound()
            ensureTodoIDs()
            showTodoSheet = true
        } label: {
            Text(openTodoCount > 99 ? "99+" : "\(openTodoCount)")
                .font(Theme.dmSans(openTodoCount > 99 ? 13 : 17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        // Sits beneath the expand/collapse control, sharing its trailing inset.
        .padding(.trailing, 10)
        .accessibilityLabel("\(openTodoCount) open to-dos")
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
        // Nudge left so the icon lines up with the composer's mic/send icon (inset by
        // the composer's 14pt padding + half the 36pt button) rather than the bar edge.
        .padding(.trailing, 10)
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
            todos: $pendingComposerTodos,
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

    private static let emptyStateTip = "welcome :) to get started, share a thought below."

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
            .sheet(isPresented: $showTodoSheet) { todoSheetView }
            .sheet(isPresented: $showMicPriming) { micPrimingSheetView }
    }

    // Secondary-sheet contents, extracted so the (large) body stays type-checkable.
    private var filSetupSheet: some View {
        SettingsView()
            .presentationDetents([.fraction(0.6)])
            .presentationBackground(Theme.background)
    }

    private var todoSheetView: some View {
        TodoSheet(
            notes: notes,
            onToggle: toggleTodoFromSheet,
            onDeleteTodo: deleteTodoFromSheet,
            onOpenNote: openNoteFromSheet,
            onLandfilNote: landfilNoteFromSheet
        )
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.background)
    }

    private var micPrimingSheetView: some View {
        MicPrimingSheet(
            onEnable: {
                showMicPriming = false
                beginRecording()
            },
            onNotNow: {
                showMicPriming = false
                isComposerFocused = true
            }
        )
        .presentationDetents([.height(360)])
        .presentationBackground(Theme.background)
    }

    private var searchEmptyState: some View {
        Text("no fils match “\(trimmedSearch)”")
            .font(Theme.dmSans(15, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            emptyStateMessage
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        // Fill the scroll viewport so the bottom-anchored composer stays put even with zero fils
        // (otherwise the ScrollView collapses to content height and the composer floats up).
        .containerRelativeFrame(.vertical)
        .blur(radius: isComposerFocused ? 8 : 0)
        .opacity(isComposerFocused ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: isComposerFocused)
    }

    /// Empty-home message: a first-run welcome, or — once the user has made (and cleared) fils —
    /// a playful "blank canvas" line with the "fil" in "filled" in the accent colors.
    @ViewBuilder
    private var emptyStateMessage: some View {
        if firstUserFilAt == 0 {
            AnimatedGradientRevealText(text: Self.emptyStateTip)
                .font(Theme.dmSans(16, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        } else {
            AnimatedGradientRevealText(text: "here's a blank canvas.\nhow will you fill it?")
                .font(Theme.dmSans(17, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if notes.isEmpty && creatingFilIDs.isEmpty {
            emptyState
        } else if isSearching && !trimmedSearch.isEmpty && filteredNotes.isEmpty {
            searchEmptyState
        } else {
            NoteGridView(
                notes: filteredNotes,
                selectedNote: $selectedNote,
                selectedNoteIDs: selectedNoteIDs,
                landfillingNoteIDs: landfillingNoteIDs,
                isSelectionMode: isSelectingNotes,
                forceExpanded: isSearching,
                creatingFilIDs: creatingFilIDs,
                creationNamespace: filCreationNamespace,
                collapsedDayKeys: collapsedDayKeys,
                onToggleCollapse: { date in
                    toggleCollapsedDayKey(Self.daySectionKeyFormatter.string(from: date))
                },
                onSelectNote: { note in
                    SoundscapeManager.shared.playOpenFilClick()
                    filSheetPath.removeAll()
                    selectedNote = note
                },
                onToggleSelection: toggleNoteSelection,
                onBeginSelection: beginNoteSelection,
                onToggleSectionSelection: toggleSectionSelection
            )
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

    private func toggleTodoFromSheet(_ note: Note, _ index: Int) {
        note.normalizeCompletedTodos()
        guard note.completedTodos.indices.contains(index) else { return }
        SoundscapeManager.shared.playTodoArticleToggleSound()
        withAnimation(.snappy) {
            note.completedTodos[index].toggle()
        }
        modelContext.saveOrLog()
    }

    /// Backfills stable per-to-do IDs for any notes that predate them, so the to-dos sheet has
    /// correct list identity. Runs at a safe point (opening the sheet), never during rendering.
    private func ensureTodoIDs() {
        var changed = false
        for note in notes where note.todoIDs.count != note.todos.count {
            note.normalizeCompletedTodos()
            changed = true
        }
        if changed { modelContext.saveOrLog() }
    }

    private func deleteTodoFromSheet(_ note: Note, _ index: Int) {
        guard note.todos.indices.contains(index) else { return }
        SoundscapeManager.shared.playLandfilSound()
        withAnimation(.snappy) {
            note.removeTodo(at: index)
        }
        modelContext.saveOrLog()
    }

    private func landfilNoteFromSheet(_ note: Note) {
        SoundscapeManager.shared.playLandfilSound()
        withAnimation(.snappy) {
            deleteNoteResources(note)
            modelContext.delete(note)
        }
        modelContext.saveOrLog()
    }

    private func openNoteFromSheet(_ note: Note) {
        showTodoSheet = false
        // Let the to-dos sheet dismiss before presenting the fil, so the two sheets don't fight.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            SoundscapeManager.shared.playOpenFilClick()
            filSheetPath.removeAll()
            selectedNote = note
        }
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
        // Prime before the first system prompt; route to Settings once permission is denied
        // (iOS never re-shows the dialog, so a raw denial would otherwise dead-end the feature).
        switch recorder.permissionStatus {
        case .authorized:
            beginRecording()
        case .notDetermined:
            showMicPriming = true
        case .denied:
            showPermissionAlert = true
        }
    }

    private func beginRecording() {
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

    private func openAppSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func stopRecording() {
        guard let result = recorder.stopRecording() else { return }
        processRecording(url: result.url, duration: result.duration)
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
        FilLandfil.cleanUpResources(for: note)
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
        // Collapse the editable pills into clean to-do strings: trim, drop blanks, dedupe.
        var seenTodos: Set<String> = []
        let todos = pendingComposerTodos.compactMap { pill -> String? in
            let t = pill.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seenTodos.insert(t.lowercased()).inserted else { return nil }
            return t
        }
        // A fil always needs contextual content — a thought or an image. To-dos ride along
        // with it, never on their own.
        guard !trimmed.isEmpty || !stagedComposerImageData.isEmpty else { return }

        let stagedImages = stagedComposerImageData
        isComposerFocused = false
        textEntryText = ""
        pendingComposerTodos = []
        selectedComposerPhotos = []
        stagedComposerImageData = []

        await createFil { filID in
            if !stagedImages.isEmpty {
                try await saveImageFil(caption: trimmed, imageData: stagedImages, todos: todos, filID: filID)
            } else if todos.isEmpty, let linkURL = normalizedLinkURL(from: trimmed) {
                saveLinkNote(for: linkURL, filID: filID)
            } else {
                try await saveGeneratedNote(from: trimmed, todos: todos, filID: filID)
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
