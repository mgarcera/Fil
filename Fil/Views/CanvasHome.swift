import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import StoreKit
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// A photo picked into the composer, held as a card in the deck until the fil is sent.
private struct PendingPhoto: Identifiable {
    let id = UUID()
    let itemID: String?   // the picker asset id, used to skip re-picking one already staged
    let image: UIImage
    let data: Data
}

/// Fil's home: a blank capture-first canvas. You type a thought and it pops into being as a fil;
/// tapping search opens a query field. Fil Pro gets cloud AI surfacing (a warm summary +
/// semantic/temporal/thematic selection); everyone gets free on-device keyword search. Embedded in
/// ContentView, which owns the header (settings + search/back).
struct CanvasHome: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    // Match the home folder list's order exactly (sortIndex, then newest-first tiebreak) so the
    // composer's folder switcher lists them in the same order as the folders on the home page.
    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)]) private var folders: [Folder]

    // First-run onboarding, re-homed here because creation now happens on the canvas (not through
    // ContentView.createFil). See docs/onboarding/.
    @AppStorage("didSeedWelcomeFil") private var didSeedWelcomeFil = false
    /// Epoch seconds of the user's first real fil; 0 until then. Gates the one-time seed reveal.
    @AppStorage("firstUserFilAt") private var firstUserFilAt: Double = 0
    /// Ask for a rating at most once, after the user has felt the core loop a few times.
    @AppStorage("didRequestReview") private var didRequestReview = false
    @Environment(\.requestReview) private var requestReview

    private enum Phase { case composing, recording, creating, formed, querying, results }

    /// The settled fil blob pops in — scales up from near-zero with a snappy, punchy spring.
    private static let popTransition = AnyTransition.scale(scale: 0.01).combined(with: .opacity)
    private static let popAnimation = Animation.spring(response: 0.24, dampingFraction: 0.46)

    /// Rotating search-field prompts — like the old composer's rotating placeholder — that also teach
    /// the flexible query types (semantic, temporal, type, to-dos).
    private static let queryPrompts = [
        "search your thoughts",
        "what am i forgetting?",
        "today",
        "to dos",
        "photos",
        "times i felt...",
        "my project...",
        "that time i...",
    ]
    private static let queryPromptInterval: TimeInterval = 3.5

    /// Drives search: true enters the query screen (composer becomes the query input), false returns
    /// to the composer. Set by the composer's search / X buttons.
    @Binding var searchActive: Bool
    /// True while a screensaver is on screen — it overrides the keyboard (resigns composer/query
    /// focus), and focus is restored to the current mode when it dismisses.
    var screensaverActive: Bool = false
    /// Set true while a folder interior is open, so ContentView hides its floating header there.
    @Binding var folderInteriorOpen: Bool
    /// A pending Lock Screen deep link (Bin / a folder), routed by the folders section once it mounts.
    @Binding var deepLink: HomeDeepLink?
    /// Opens Settings (owned by ContentView) — driven by the floating settings button over the composer.
    var onSettings: () -> Void = {}
    /// The folder the composer is currently scoped to (nil at the root) — makes the bar contextual.
    @State private var contextFolder: Folder?
    /// Live height of the bottom dock (composer + baskets), so scroll content insets track it.
    @State private var dockHeight: CGFloat = 0
    /// Composer ＋ / ✨ → folders section (new-folder popup / smart-organize).
    @State private var newFolderRequest = false
    @State private var organizeRequest = false

    @State private var phase: Phase = .composing
    @State private var text = ""
    /// The just-made fil, so the gooey creating blob can settle into its final randomized blob.
    @State private var formedNote: Note?
    /// Drives the settled blob's pop in AND out via scale/opacity. A plain state (not a transition)
    /// because a `switch`/`if` removal transition is unreliable here — the blob would pop in and then
    /// vanish with no outro.
    @State private var formedShown = false

    // Surfacing (dev-key Claude spike)
    @State private var query = ""
    @State private var results: [Note] = []
    /// Which surfaced fils go in the to-do checklist, captured once per query so completing a to-do
    /// doesn't reflow the fil into the grid mid-tap.
    @State private var todoFilIDs: Set<UUID> = []
    /// The search phase to restore when the user returns from home, so a search survives a home trip.
    /// Only the header refresh button starts a fresh search (via `beginSurface`).
    @State private var savedSearchPhase: Phase?
    @State private var summary = ""
    /// True when the last query resolved to a deterministic metadata/filter (type/time/to-dos), so the
    /// results screen skips the summary and the free-tier "try Pro" invites (Pro wouldn't do better).
    @State private var isFilterQuery = false
    /// When a Pro query surfaces nothing, a nearby query the corpus can actually answer (from the model),
    /// offered as a tappable chip in the empty state. Empty when there's no good alternative.
    @State private var suggestedQuery = ""
    /// Bumped on every search so a late async result (e.g. the streamed metadata summary) from a
    /// superseded query can tell it's stale and discard itself instead of overwriting newer results.
    @State private var searchToken = 0
    /// A surfaced fil pending landfil confirmation (drives the shared alert).
    @State private var pendingLandfilNote: Note?
    @State private var surfaceError: String?
    @State private var isRetrieving = false
    @State private var selectedNote: Note?
    /// A paged reading session for the Bin / selection baskets (swipe between the tapped set of fils).
    @State private var basketPager: FilPagerSelection?
    /// Tapping a search result opens the Full Screen player over the result set (same as the folders).
    @State private var resultsPager: FilPagerSelection?
    @State private var showPaywall = false
    @State private var showFeedback = false
    // `binFiling` non-nil presents the review tray, which then makes the request itself. The
    // sheet being up is also what stops a second tap starting a second billed call — it covers
    // the chip before you could press it again.
    @State private var binFiling: BinFilingProposal?
    @State private var filingError: String?
    /// Each filed fil's previous folder, kept so the batch can be undone.
    @State private var lastFiling: [UUID: Folder?]?
    // Voice capture: the mic glyph starts recording; the gooey blob pulses while recording, then
    // flows into the same creation animation typed/link fils use.
    @State private var recorder = VoiceRecorderViewModel()
    @State private var showMicPriming = false
    @State private var showEmptyVoicePrompt = false   // transcription came back empty → redo / exit
    @State private var recordingPulse = false
    // Photo capture: "add photo" in the composer edit menu opens the picker.
    @State private var photoItems: [PhotosPickerItem] = []
    /// Photos picked but not yet sent — staged as thumbnails in the composer bar; words can be added first.
    @State private var pendingPhotos: [PendingPhoto] = []
    /// The fil sheet's current detent, bound so ArticleView knows when it's expanded to full.
    @State private var filSheetDetent: PresentationDetent = .fraction(0.6)
    /// Navigation path inside the fil sheet, so filaments (and linked fils) can push. Without this,
    /// tapping "filament" / a highlighted word had nowhere to go — the feature was unreachable.
    @State private var filSheetPath: [FilSheetRoute] = []
    /// Fils mid-landfil: they shrink to nothing (like the timeline) before the actual delete.
    @State private var landfillingIDs: Set<UUID> = []
    /// Recent search terms, newline-joined, most-recent first (persisted on-device, capped).
    @AppStorage("recentSearchesRaw") private var recentSearchesRaw = ""

    /// Focus for the composer bar's text field (raises/dismisses the keyboard).
    @FocusState private var composerFocused: Bool
    /// To-do "pills" being composed alongside the current thought in the composer bar.
    @State private var composeTodos: [ComposerTodo] = []

    private var notesByID: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.uuid, $0) })
    }

    /// Search mode: the composer is the query input and the results (or a blank canvas) sit behind it.
    private var isSearching: Bool { phase == .querying || phase == .results }
    /// True when fils are swipe/long-press selected — drives the floating move/copy/delete chips.
    private var hasSelection: Bool { !FilSelectionStore.shared.isEmpty }
    /// The Bin has unfiled fils to browse (root only). Drives the floating switcher chip's visibility.
    private var binHasItems: Bool { !folderInteriorOpen && notes.contains { $0.folder == nil } }
    /// Which dock set is shown — shared between the floating switcher chip and HomeBasket's blob row.
    @State private var dockTab: DockTab = .bin

    var body: some View {
        ZStack {
            // One stable background: plain, with the folder-browser gray wash present whenever the
            // folders/search surface is up. Keeping it on during composing (hidden behind the folder
            // browser's own gray) means the browser's fade-out on entering search reveals the same
            // gray underneath — no crossfade dip through the darker base. Off during creation states.
            Theme.background.ignoresSafeArea()
            Theme.primaryText
                .opacity((phase == .composing || isSearching) ? (colorScheme == .dark ? 0.15 : 0.05) : 0)
                .ignoresSafeArea()

            // The folders browser stays MOUNTED and just fades on `phase` — destroying/recreating it
            // (as a switch case did) flashed the List's default black background for a frame when it
            // remounted on exiting search. Results overlay it when a search runs.
            composer
                .opacity(phase == .composing ? 1 : 0)
                .allowsHitTesting(phase == .composing)

            if phase == .results { resultsList }

            // Recording and creating share ONE gooey blob so it never tears down between them; it
            // then morphs into the settled note blob, which pops out the same way it popped in.
            if phase == .recording || phase == .creating {
                creatingGooey
            }
            if phase == .formed {
                formedBlob
            }

        }
        // A Lock Screen tap must land on the folders home (where the Bin dock + folders live), not a
        // leftover search/results screen. Flip to composing so FoldersHomeSection mounts + routes it.
        .onChange(of: deepLink) { _, link in
            guard let link else { return }
            if phase != .composing {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .composing }
            }
            // Control Center capture links are home-level: consume + clear them here (folder/bin are
            // consumed by FoldersHomeSection instead).
            switch link {
            case .compose:
                DispatchQueue.main.async { composerFocused = true }
                deepLink = nil
            case .voice:
                DispatchQueue.main.async { startVoiceCapture() }
                deepLink = nil
            case .bin, .folder:
                break
            }
        }
        // The home dock: one liquid-glass container holding the selection + Bin baskets ABOVE the
        // composer input — one surface, no overlap. Floats at the bottom, rides above the keyboard.
        // Shown while composing (incl. inside a folder interior, where the composer is contextual).
        .overlay(alignment: .bottom) {
            if phase == .composing || isSearching {
                VStack(spacing: 10) {
                    // Settings + add-folder live in the top nav bar (root) and the folder switcher moved
                    // into the folder interior's header, so there are no bottom FABs anymore.

                    // The floating liquid-glass row above the dock: Bin | Selected switcher (leftmost)
                    // + move/copy/delete chips when selected. Present whenever the dock has fils; hidden
                    // during search.
                    if (hasSelection || binHasItems) && !isSearching {
                        DockChipsRow(
                            tab: $dockTab,
                            showBin: !folderInteriorOpen,
                            onFile: fileOrOrganize
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    VStack(spacing: 12) {
                        // Above the composer: recent-search chips in search (when the query's empty),
                        // else the Bin / selection baskets.
                        if isSearching {
                            if query.isEmpty && !recentSearches.isEmpty {
                                recentChipsRow
                                    .transition(.scale.combined(with: .opacity))
                            }
                        } else {
                            HomeBasket(
                                onOpen: { note, container in basketPager = FilPagerSelection(notes: container, startID: note.uuid) },
                                showBin: !folderInteriorOpen,
                                tab: $dockTab
                            )
                        }
                        composerBar
                    }
                    .padding(14)
                    // Recent-search capsules scale in/out as the query empties/fills and on exit.
                    .animation(.snappy(duration: 0.2), value: query.isEmpty)
                    .animation(.snappy(duration: 0.2), value: isSearching)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                // Quick snappy minimize/maximize for the FABs as focus toggles.
                .animation(.snappy(duration: 0.2), value: composerFocused)
                .animation(.snappy(duration: 0.2), value: hasSelection)
                .animation(.snappy(duration: 0.2), value: binHasItems)
                // Measure the WHOLE dock (floating buttons + composer) so scroll content clears it all.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
            }
        }
        // While recording, a stop button sits below the pulsing gooey blob.
        .overlay(alignment: .bottom) {
            if phase == .recording {
                stopButton
                    .padding(.bottom, 90)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hasText)
        .sheet(item: $selectedNote, onDismiss: { filSheetDetent = .fraction(0.6); filSheetPath.removeAll() }) { note in
            NavigationStack(path: $filSheetPath) {
                // Match the timeline's presentation: the X toolbar item + respecting the top safe
                // area render the nav bar and space the fil's content correctly.
                ArticleView(note: note, ignoresTopSafeArea: false, showsCloseButton: true, filSheetPath: $filSheetPath, selectedPresentationDetent: $filSheetDetent)
                    .navigationDestination(for: FilSheetRoute.self) { route in
                        filSheetDestination(route)
                    }
            }
            // Link fils stay at the medium detent (no expand-to-full); photos open taller (0.8);
            // other fils rest at 0.6. All non-link fils can expand to full.
            .presentationDetents(note.isLinkFil ? [.fraction(0.6)] : note.isImageFil ? [.fraction(0.8), .large] : [.fraction(0.6), .large], selection: $filSheetDetent)
            .presentationBackground { FolderBrowserBackground() }
        }
        .sheet(item: $basketPager) { sel in
            BrowserFilPager(notes: sel.notes, startID: sel.startID)
        }
        .sheet(item: $resultsPager) { sel in
            FilFullScreenPlayer(notes: sel.notes, startID: sel.startID) { resultsPager = nil }
        }
        // Photos open taller (0.8); everything else rests at 0.6. Set before the sheet reads it.
        .onChange(of: selectedNote) { _, note in
            filSheetDetent = (note?.isImageFil ?? false) ? .fraction(0.8) : .fraction(0.6)
        }
        // If an open fil gets landfil'd (from within its own modal or elsewhere), close the modal —
        // a nested pager/sheet can otherwise linger showing a deleted fil.
        .onChange(of: notes.map(\.uuid)) { _, ids in
            let live = Set(ids)
            if let note = selectedNote, !notes.contains(where: { $0 === note }) { selectedNote = nil }
            // Close the pager if ANY fil it's paging got landfil'd, not just the one it opened on.
            if let pager = basketPager, !pager.noteIDs.allSatisfy({ live.contains($0) }) { basketPager = nil }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
        .sheet(item: $binFiling) { proposal in
            BinFilingSheet(input: proposal, onFiled: { previous in lastFiling = previous })
                .presentationBackground(Theme.background)
        }
        .alert("Couldn't file the Bin", isPresented: .init(
            get: { filingError != nil },
            set: { if !$0 { filingError = nil } }
        )) {
            Button("OK", role: .cancel) { filingError = nil }
        } message: {
            Text(filingError ?? "")
        }
        // The undo the gesture owes you. Shake is the system's undo, and this moved a batch of
        // fils at once, so the reversal has to be one tap and it has to be visible without
        // hunting. Sits at the top: the Bin and composer own the bottom of this screen.
        .overlay(alignment: .top) { filingUndoBar }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(context: "smart search fell back to keyword for: “\(query)”")
        }
        .sheet(isPresented: $showMicPriming) {
            MicPrimingSheet(
                onEnable: {
                    showMicPriming = false
                    Task { if await recorder.requestPermissions() { await beginRecording() } }
                },
                onNotNow: { showMicPriming = false }
            )
            .presentationDetents([.medium])
            .presentationBackground(Theme.background)
        }
        .alert("Fil didn't hear you", isPresented: $showEmptyVoicePrompt) {
            Button("Redo") { Task { await beginRecording() } }
            Button("Exit", role: .cancel) { composerFocused = true }
        } message: {
            Text("Want to try again?")
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var seenIDs = Set(pendingPhotos.compactMap(\.itemID))
                var seenData = Set(pendingPhotos.map(\.data))
                var loaded: [PendingPhoto] = []
                for item in items {
                    let itemID = item.itemIdentifier
                    if let itemID, seenIDs.contains(itemID) { continue }   // already staged — skip re-pick
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
                    if seenData.contains(data) { continue }                // fallback: identical bytes
                    loaded.append(PendingPhoto(itemID: itemID, image: image, data: data))
                    if let itemID { seenIDs.insert(itemID) }
                    seenData.insert(data)
                }
                photoItems = []
                if !loaded.isEmpty {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { pendingPhotos.append(contentsOf: loaded) }
                }
                composerFocused = true   // keep composing — words can be added to the photos before sending
            }
        }
        .landfilConfirmation(item: $pendingLandfilNote, message: { _ in
            "This thought will be deleted. This cannot be undone."
        }, onConfirm: { note in
            landfil(note)
        })
        // A fil deleted anywhere (notably from its opened fil sheet) should leave the search results
        // too — otherwise a landfilled to-do fil lingered in the checklist.
        .onChange(of: notes.map(\.uuid)) { _, _ in pruneDeletedResults() }
        // The header search/back button toggles searchActive: enter the query screen or return to
        // the composer. (There's no tap-anywhere-to-go-back; the header button is the switcher.)
        .onChange(of: searchActive) { _, active in
            if active {
                // Returning to search: restore the search that was on screen, else start fresh.
                if let saved = savedSearchPhase {
                    savedSearchPhase = nil
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = saved }
                    if saved == .querying { composerFocused = true }
                } else if phase != .querying && phase != .results {
                    beginSurface()
                }
            } else {
                // Going home: keep the query + results so they're still there on return. Don't clear.
                if phase == .querying || phase == .results { savedSearchPhase = phase }
                composerFocused = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .composing }
                // Tap-to-focus: return to the resting home (folders visible); don't raise the keyboard.
            }
        }
        // A screensaver overrides the keyboard: drop focus while it's up, restore it on dismiss.
        .onChange(of: screensaverActive) { _, active in
            if active {
                composerFocused = false
                // A screensaver launched from Settings dismisses its sheet ~0.35s later, and SwiftUI
                // would otherwise restore first responder to the composer — re-clear once it settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if screensaverActive {
                        composerFocused = false
                    }
                }
            } else {
                switch phase {
                case .composing: break   // tap-to-focus: don't auto-raise the composer keyboard
                case .querying:  composerFocused = true
                default:         break
                }
            }
        }
        // Tap-to-focus: the compose bar rests unfocused at launch (folders are browsable); the
        // keyboard rises only when the user taps the bar.
    }

    /// Start a fresh search: clear any prior results and the remembered search, and open an empty
    /// query field. The header refresh button is the only way to reach this once results are up.
    /// Destinations pushed inside the fil sheet: a filament (keyword) popup, or a linked fil.
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
                // Share the sheet's detent so a pushed image fil gets the caption + full-detent expand.
                ArticleView(note: linkedNote, showsThreadedFilRows: false, ignoresTopSafeArea: false, filSheetPath: $filSheetPath, selectedPresentationDetent: $filSheetDetent)
            } else {
                MissingLinkedFilView()
            }
        }
    }

    private func beginSurface() {
        savedSearchPhase = nil
        query = ""
        summary = ""
        surfaceError = nil
        results = []
        todoFilIDs = []
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .querying }
        composerFocused = true
    }

    // MARK: - Capture states

    /// The home's resting state: the folders. Pulling the top grabber down (or tapping it) inserts the
    /// "New" compose card inline above the folders (which slide down beneath it) — not an overlay.
    private var composer: some View {
        FoldersHomeSection(
            bottomInset: dockHeight + 16,   // clear the measured dock (composer + baskets)
            onContextFolderChange: { folder in
                withAnimation(.easeInOut(duration: 0.2)) {
                    contextFolder = folder
                    folderInteriorOpen = (folder != nil)
                }
            },
            deepLink: $deepLink,
            newFolderRequest: $newFolderRequest,
            organizeRequest: $organizeRequest,
            onSettings: onSettings
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }

    /// In search mode the composer edits the query; otherwise the capture text.
    private var composerText: Binding<String> {
        Binding(
            get: { isSearching ? query : text },
            set: { if isSearching { query = $0 } else { text = $0 } }
        )
    }

    /// The always-on composer bar, pinned at the bottom over the keyboard (see body overlay).
    private var composerBar: some View {
        ComposerBar(
            text: composerText,
            todos: $composeTodos,
            selectedPhotos: $photoItems,
            stagedImageData: pendingPhotos.map(\.data),
            isProcessing: false,
            contextLabel: contextFolder.map { "Add to \($0.name)" },
            focus: $composerFocused,
            searchMode: isSearching,
            searchShowingResults: phase == .results,
            searchPrompts: searchPrompts,
            onSend: { Task { await createFil() } },
            onRecordVoice: startVoiceCapture,
            onRemoveStagedImage: { index in
                if pendingPhotos.indices.contains(index) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { _ = pendingPhotos.remove(at: index) }
                }
            },
            onCapturePhoto: { data in stageCapturedPhoto(data) },
            onEnterSearch: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searchActive = true } },
            onSubmitSearch: { Task { await runQuery() } },
            onRestartSearch: { beginSurface() },
            onExitSearch: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searchActive = false } }
        )
    }

    /// Rotating search placeholders: the Pro smart-query examples (quoted), or the free keyword hint.
    private var searchPrompts: [String] {
        guard StoreManager.shared.isPro else { return ["search by keyword"] }
        return Self.queryPrompts.map { $0 == "search your thoughts" ? $0 : "“\($0)”" }
    }

    /// A stop button, shown below the gooey blob while recording. Tapping it ends the recording and
    /// the same blob morphs straight into the settled fil.
    private var stopButton: some View {
        Button { Task { await finishRecording() } } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
        .transition(.scale.combined(with: .opacity))
    }

    /// The gooey blob shown while a fil forms — during a voice recording and while any fil is being
    /// created. It pulses gently, then morphs into the settled note blob (`formedBlob`). Recording
    /// and creating render this same view, so stopping never flashes a second blob.
    private var creatingGooey: some View {
        CreatingFilBlobView()
            .frame(width: 190, height: 190)
            .scaleEffect(recordingPulse ? 1.04 : 0.96)
            .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: recordingPulse)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.2).combined(with: .opacity),
                removal: .opacity
            ))
            .onAppear { recordingPulse = true }
            .onDisappear { recordingPulse = false }
    }

    /// The fil's final, settled randomized blob — same shape/gradient the grid card shows. It pops in
    /// over the gooey creating blob (the "blob turns into a fil" morph), holds, then pops back out —
    /// both driven by `formedShown` (scale + opacity), so the outro is guaranteed.
    @ViewBuilder
    private var formedBlob: some View {
        if let note = formedNote {
            Group {
                if hasBlobArtwork(note) {
                    // Photo / link / voice reveal their artwork as they settle, like in the grid.
                    NoteCardView(note: note, cardHeight: 190)
                } else {
                    NoteBlobShape(seed: note.blobShapeSeed)
                        .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                }
            }
            .frame(width: 190, height: 190)
            .scaleEffect(formedShown ? 1 : 0.02)
            .opacity(formedShown ? 1 : 0)
        }
    }

    // MARK: - Surfacing states

    /// Recently-searched terms as tappable chips, shown in the dock's top slot (above the composer)
    /// while searching with an empty query. Tap to re-run.
    private var recentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        query = term
                        Task { await runQuery() }
                    } label: {
                        Text(term)
                            .font(Theme.dmSans(14, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.primaryText.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shimmering placeholder shown while a query is retrieving: a summary line plus a few card
    /// silhouettes that mirror the folder-browser result cards.
    private var searchSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            SkeletonView(Capsule()).frame(height: 12).frame(maxWidth: 220)
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonView(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .frame(height: 76)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Everything — query, summary, and the fil cards — scrolls together in one ScrollView.
    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                resultsHeader

                if isRetrieving {
                    searchSkeleton
                } else {
                    if let surfaceError {
                        // Gentle, non-blocking note when smart search fails and we fall back to keyword.
                        VStack(alignment: .leading, spacing: 6) {
                            AnimatedGradientRevealText.search(surfaceError)
                                .font(Theme.fredoka(15, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            // Offer feedback only when we actually fell back to keyword matches (path E).
                            if !results.isEmpty {
                                Button("Open feedback form") { showFeedback = true }
                                    .font(Theme.fredoka(14, weight: .medium))
                                    .tint(Theme.filProAmber)
                            }
                        }
                    }
                    if !summary.isEmpty && !results.isEmpty {
                        AnimatedGradientRevealText.search(summary)
                            .font(Theme.fredoka(16, weight: .regular))
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !StoreManager.shared.isPro && !results.isEmpty && !isFilterQuery {
                        freeSurfaceInvite
                    }
                    if results.isEmpty {
                        // Free users get an upgrade invite (AI can find by meaning, not just words)
                        // exactly when keyword search comes up empty; Pro users — and any metadata
                        // filter, where Pro wouldn't help — see the plain miss.
                        if !StoreManager.shared.isPro && !isFilterQuery {
                            freeEmptyInvite
                        } else if surfaceError == nil {
                            emptyResultPrompt
                        }
                    } else {
                        scrapbook
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 80)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, dockHeight + 16, for: .scrollContent)   // clear the composer dock
        .transition(.opacity)
    }

    /// Shown to free users in place of the AI summary: a calm, non-pushy invitation to Pro
    /// surfacing (their keyword results still render below).
    private var freeSurfaceInvite: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                AnimatedGradientRevealText.search("Found by keyword.")
                    .font(Theme.fredoka(15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                filProInviteLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Shown to free users when keyword search finds nothing — the moment AI would help most.
    private var freeEmptyInvite: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                AnimatedGradientRevealText.search("Nothing came up for \(query)")
                    .font(Theme.fredoka(15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                filProInviteLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// The Pro empty state as one flowing sentence with an inline tappable link. When the model found a
    /// genuinely related nearby query, "try X instead" runs it; otherwise "write one about it" drops back
    /// into the composer, seeded with what they searched for, so a dead end still leads somewhere.
    private var emptyResultPrompt: some View {
        var line: AttributedString

        if !suggestedQuery.isEmpty {
            line = AttributedString("Nothing came up for it. Want to try ")
            line.foregroundColor = Theme.secondaryText
            var link = AttributedString(suggestedQuery)
            link.foregroundColor = Theme.filProAmber
            link.link = URL(string: "fil-action://suggest")
            var tail = AttributedString(" instead?")
            tail.foregroundColor = Theme.secondaryText
            line.append(link); line.append(tail)
        } else {
            line = AttributedString("Nothing came up for it. Do you have a ")
            line.foregroundColor = Theme.secondaryText
            var link = AttributedString("thought?")
            link.foregroundColor = Theme.filProAmber
            link.link = URL(string: "fil-action://compose")
            line.append(link)
        }

        return Text(line)
            .font(Theme.fredoka(15, weight: .medium))
            .tint(Theme.filProAmber)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                switch url.host {
                case "suggest": query = suggestedQuery; Task { await runQuery() }
                case "compose": composeAboutQuery()
                default: break
                }
                return .handled
            })
    }

    /// Leave the empty search and open the composer seeded with what they searched for — the "write one
    /// about it" path, turning a missed search into a new thought.
    private func composeAboutQuery() {
        text = query
        searchActive = false   // drives the transition back to the composer (see .onChange(of: searchActive))
        // The searchActive handler unfocuses on the way home; re-raise the keyboard next tick so the
        // user can keep typing the thought they searched for.
        DispatchQueue.main.async { composerFocused = true }
    }

    /// "check out fil pro for a smart search" with the "fil pro" wordmark in the multicolor accent
    /// gradient. The full sentence lays out (and wraps) normally in secondary text; the gradient is
    /// masked to show through only the "fil pro" glyphs via an aligned overlay.
    private var filProInviteLine: some View {
        let full = "Check out Fil Extra for a smarter search."
        let word = "Fil Extra"

        // Base sentence: gray, with the wordmark punched out (clear) so the gradient overlay shows.
        var base = AttributedString(full)
        if let range = base.range(of: word) { base[range].foregroundColor = .clear }

        // Mask: only the wordmark opaque, rest clear — so the gradient fills just those glyphs.
        var mask = AttributedString(full)
        mask.foregroundColor = .clear
        if let range = mask.range(of: word) { mask[range].foregroundColor = .black }

        return Text(base)
            .font(Theme.fredoka(14))
            .foregroundStyle(Theme.secondaryText)
            .overlay { Theme.accentGradient.mask(Text(mask).font(Theme.fredoka(14))) }
            .fixedSize(horizontal: false, vertical: true)
    }

    // Results mirror the folder browser: typed sections of full-width cards, tapping one opens the
    // Full Screen player over the whole result set. The to-do split is captured once per query
    // (`todoFilIDs`, set in runQuery) so completing a to-do can't reflow a fil out of its section
    // mid-tap. The rest split by kind — photos, notes, links, voice — matching the folder interior.
    private var todoResults: [Note] { results.filter { todoFilIDs.contains($0.uuid) } }
    private var gridResults: [Note] { results.filter { !todoFilIDs.contains($0.uuid) } }
    private var photoResults: [Note] { gridResults.filter { $0.isImageFil } }
    private var linkResults: [Note] { gridResults.filter { !$0.isImageFil && $0.isLinkFil } }
    private var voiceResults: [Note] { gridResults.filter { !$0.isImageFil && !$0.isLinkFil && !$0.audioFilePath.isEmpty } }
    private var noteResults: [Note] { gridResults.filter { !$0.isImageFil && !$0.isLinkFil && $0.audioFilePath.isEmpty } }
    /// The player deck for tapped results — the same top-to-bottom order the sections render in.
    private var resultDeck: [Note] { todoResults + photoResults + noteResults + linkResults + voiceResults }

    /// Sections top to bottom: to-dos, photos, notes, links, voice — the folder-browser order.
    private var scrapbook: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !todoResults.isEmpty { resultSection("To-dos", "checklist", todoResults, isTodo: true) }
            if !photoResults.isEmpty { resultSection("Photos", "photo", photoResults) }
            if !noteResults.isEmpty { resultSection("Notes", "note.text", noteResults) }
            if !linkResults.isEmpty { resultSection("Links", "link", linkResults) }
            if !voiceResults.isEmpty { resultSection("Voice", "waveform", voiceResults) }
        }
        .padding(.top, 4)
    }

    /// One type container: the header, then its full-width cards. To-do sections count their open
    /// items (like the folder browser); the rest count fils.
    @ViewBuilder
    private func resultSection(_ label: String, _ icon: String, _ notes: [Note], isTodo: Bool = false) -> some View {
        let count = isTodo ? notes.reduce(0) { $0 + $1.todoRowItems.count } : notes.count
        VStack(alignment: .leading, spacing: 10) {
            FilSectionHeader(label: label, icon: icon, count: count)
            ForEach(notes, id: \.uuid) { note in
                Group {
                    if isTodo { FilTodoCard(note: note) { toggleTodo(note, $0) } } else { FilCard(note: note) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .onTapGesture { resultsPager = FilPagerSelection(notes: resultDeck, startID: note.uuid) }
                .contextMenu { filContextMenu(note) }
                .blur(radius: isLandfilling(note) ? 8 : 0)
                .opacity(isLandfilling(note) ? 0 : 1)
            }
        }
    }

    /// Long-press menu on a surfaced fil: landfil it (confirmed). (Pinning is being reworked.)
    @ViewBuilder
    private func filContextMenu(_ note: Note) -> some View {
        Button(role: .destructive) {
            pendingLandfilNote = note
        } label: {
            Label("Landfil", systemImage: "trash")
        }
    }

    private func isLandfilling(_ note: Note) -> Bool { landfillingIDs.contains(note.uuid) }

    /// Drop surfaced results whose fil no longer exists (deleted from its opened sheet, say). Compares
    /// by object identity so we never read a property off a deleted SwiftData model.
    private func pruneDeletedResults() {
        let survivors = results.filter { result in notes.contains { $0 === result } }
        guard survivors.count != results.count else { return }
        withAnimation(.easeOut(duration: 0.2)) { results = survivors }
        todoFilIDs = todoFilIDs.intersection(Set(survivors.map(\.uuid)))
    }

    private func landfil(_ note: Note) {
        FilLandfil.cleanUpResources(for: note)
        let id = note.uuid
        SoundscapeManager.shared.playLandfilSound(); Haptics.destructive()
        // Timeline-style deletion: the fil shrinks + blurs away first, then it's removed + deleted.
        withAnimation(.easeOut(duration: 0.45)) {
            _ = landfillingIDs.insert(id)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.2)) {
                results.removeAll { $0.uuid == id }
                todoFilIDs.remove(id)
            }
            modelContext.delete(note)
            modelContext.saveOrLog()
            landfillingIDs.remove(id)
        }
    }

    /// Toggle a surfaced fil's to-do: shared model mutation + this surface's sound + animation.
    private func toggleTodo(_ note: Note, _ index: Int) {
        SoundscapeManager.shared.playTodoArticleToggleSound(); Haptics.toggle()
        withAnimation(.snappy) { _ = note.toggleCompletedTodo(at: index) }
    }
    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(query)
                .font(Theme.instrumentSerif(28))
                .foregroundStyle(Theme.primaryText)
            Spacer()
        }
    }

    // MARK: - Logic

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recentSearches: [String] {
        recentSearchesRaw.split(separator: "\n").map(String.init)
    }

    /// Record a run query: dedup (case-insensitive), move to front, cap at 6, persist.
    private func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        recentSearchesRaw = list.prefix(6).joined(separator: "\n")
    }

    private func createFil() async {
        let composedTodos = composeTodos.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        composeTodos = []
        // Photos pending → this is a photo fil (the text becomes its caption).
        if !pendingPhotos.isEmpty {
            await createImageFil(images: pendingPhotos.map(\.data), caption: text, todos: composedTodos)
            return
        }

        let thought = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else { return }

        text = ""

        // Inline creation (no full-screen animation): the fil just pops into the Bin/folder, so the
        // composer's context (and the folder you're in) stays put.
        let gradient = Theme.randomGradientPair()
        let note: Note
        if let url = LinkFil.normalizedURL(from: thought) {
            note = LinkFil.make(url: url, gradient: gradient, in: modelContext)
        } else {
            note = Note(
                title: "",
                transcript: thought,
                keyword: "",
                gradientStartHex: gradient.start,
                gradientEndHex: gradient.end
            )
            modelContext.insert(note)
        }
        for todo in composedTodos { note.addTodo(todo) }
        note.folder = contextFolder   // file into the folder the composer is scoped to (nil = Bin)
        modelContext.saveOrLog()
        SoundscapeManager.shared.playArticleMadeSound(); Haptics.success()

        await afterUserFilCreated()
    }

    // MARK: - Voice capture

    /// Mic tapped: record if allowed, prime on first use, or route to Settings after a denial.
    private func startVoiceCapture() {
        switch recorder.permissionStatus {
        case .authorized:    Task { await beginRecording() }
        case .notDetermined: showMicPriming = true
        case .denied:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #endif
        }
    }

    private func beginRecording() async {
        composerFocused = false
        await recorder.startRecording()
        guard recorder.isRecording else { return }   // setup failed → stay in the composer
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { phase = .recording }
    }

    /// Stop, transcribe on-device, and create the voice fil — then hand off to the shared creation
    /// animation (gooey blob → settled fil → composer), exactly like a typed fil.
    private func finishRecording() async {
        guard let (url, duration) = recorder.stopRecording() else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .composing }
            composerFocused = true
            return
        }

        beginCreation()

        let transcript = ((try? await recorder.transcribe(url: url)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing transcribed (silence / failed) → don't create a ghost voice fil. Discard the clip and
        // offer to redo or exit, so an empty recording never lands in the Bin.
        guard !transcript.isEmpty else {
            SoundscapeManager.shared.stopMeshDuringProcessSound()
            try? FileManager.default.removeItem(at: url)
            withAnimation(.snappy(duration: 0.2)) { phase = .composing }
            showEmptyVoicePrompt = true
            return
        }

        let gradient = Theme.randomGradientPair()
        // No AI title: the first line of the transcript is the title (see Note.titleLine).
        let note = Note(
            title: "",
            transcript: transcript,
            audioFilePath: url.lastPathComponent,   // bare filename; resolved against the docs dir
            duration: duration,
            keyword: "",
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.folder = contextFolder
        modelContext.insert(note)
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound(); Haptics.success()

        await settleCreatedFil(note)
    }

    // MARK: - Photo capture

    /// Turn a picked image into an image fil, flowing through the same gooey-blob creation animation.
    /// Stage a camera-captured photo just like a picked one: it joins `pendingPhotos` (caption still
    /// required to send), keeping the compose flow identical to the photo picker.
    private func stageCapturedPhoto(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            pendingPhotos.append(PendingPhoto(itemID: nil, image: image, data: data))
        }
        composerFocused = true   // keep composing — a caption can be added before sending
    }

    /// Turn the pending photos (+ optional caption) into one image fil, flowing through the same
    /// gooey-blob creation animation typed fils use.
    /// Shake → ask Claude where each loose fil belongs among the folders you already have, then
    /// open the review tray. Nothing moves here; `BinFilingSheet` writes, and only on commit.
    ///
    /// Requires folders to file INTO. With none, there is nothing to propose — that is smart
    /// organize's job (it invents folders), and sending an empty list is a 400 from the proxy.
    /// "Filed 6 fils · Undo", shown after a commit and cleared on a timer.
    @ViewBuilder
    private var filingUndoBar: some View {
        if let filed = lastFiling, !filed.isEmpty {
            HStack(spacing: 12) {
                // "thoughts", the word the rest of the app uses when it talks to you about them
                // — "These thoughts will be deleted", "Your thoughts will return to the Bin".
                // "fil" is the object's name; "thought" is what it is.
                Text("Filed \(filed.count) \(filed.count == 1 ? "thought" : "thoughts")")
                    .font(.system(size: 14, weight: .medium))
                Button("Undo") { undoFiling() }
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: filed.count) {
                // Long enough to notice and reach, short enough not to loiter. Keyed to .task so
                // it cancels automatically when the bar is replaced or dismissed.
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.snappy) { lastFiling = nil }
            }
        }
    }

    /// Put every fil in the last batch back where it was — including back to the Bin (nil).
    private func undoFiling() {
        guard let filed = lastFiling else { return }
        let byID = Dictionary(notes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for (filID, previousFolder) in filed {
            byID[filID]?.folder = previousFolder
        }
        modelContext.saveOrLog()
        Haptics.success()
        withAnimation(.snappy) { lastFiling = nil }
    }

    /// The chip's action. With no folders yet there is nothing to file into, and inventing
    /// folders is smart organize's job — so the same control routes to whichever mode the
    /// library can actually use, instead of erroring and telling you to go elsewhere.
    private func fileOrOrganize() {
        if folders.isEmpty { organizeRequest = true } else { fileTheBin() }
    }

    /// Reached only from the "File for me" chip, which is a labelled, deliberate tap — so the
    /// paywall here is always answering something the person asked for.
    private func fileTheBin() {
        // Two taps in the same frame are the only double-tap left to guard: once the sheet is up
        // it covers the chip, and the request lives inside it.
        guard binFiling == nil else { return }

        // Scope: a selection if you made one, the whole Bin otherwise. Selecting first is how you
        // file part of the Bin, reusing the selection model rather than inventing a second.
        //
        // Inside a folder there is no Bin on screen, so a selection is the only thing that can be
        // meant — falling back to the Bin there would file fils you can't see from a screen that
        // never mentioned them.
        let selected = FilSelectionStore.shared.selectedNotes()
        let loose = !selected.isEmpty ? selected
            : (folderInteriorOpen ? [] : notes.filter { $0.folder == nil })
        guard !loose.isEmpty else { return }
        guard !folders.isEmpty else {
            filingError = "Filing needs folders to file into. Make one first, or use Organize to have them made for you."
            return
        }
        guard StoreManager.shared.isPro else { showPaywall = true; return }

        // Acknowledge the tap, then hand everything to the sheet — it owns the request so it can
        // open immediately and fill in, rather than making you watch the dock for two seconds.
        Haptics.move()
        binFiling = BinFilingProposal(
            notes: Array(loose.prefix(200)),
            folders: folders,
            transactionID: StoreManager.shared.proTransactionID ?? ""
        )
    }

    private func createImageFil(images: [Data], caption: String, todos: [String] = []) async {
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { pendingPhotos = [] }

        // Photos carry no generated title — the caption words (if any) are their only text, and the
        // search-grid label falls back to them (or blank when there's no caption).
        let gradient = Theme.randomGradientPair()
        let note = Note(
            title: caption,
            transcript: caption,
            keyword: caption,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.imageFilImages = images.enumerated().map { index, data in NoteImage(data: data, order: index, note: note) }
        for todo in todos { note.addTodo(todo) }
        note.folder = contextFolder
        modelContext.insert(note)
        modelContext.saveOrLog()
        SoundscapeManager.shared.playArticleMadeSound(); Haptics.success()

        await afterUserFilCreated()
    }

    // MARK: - Creation tail + first-run payoff

    /// Start the creating animation for a user fil: the full-screen gooey blob.
    private func beginCreation() {
        composerFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { phase = .creating }
        SoundscapeManager.shared.startMeshDuringProcessSound()
    }

    /// Shared tail for every user creation path: settle the gooey blob into the note's final blob,
    /// hold a beat, then return to the composer — and run the first-run payoff after a real fil.
    private func settleCreatedFil(_ note: Note) async {
        formedNote = note
        formedShown = false
        // Gooey fades out (phase) as the settled blob pops in (formedShown) — the "blob → fil" morph.
        withAnimation(.easeOut(duration: 0.25)) { phase = .formed }
        withAnimation(Self.popAnimation) { formedShown = true }
        try? await Task.sleep(for: .milliseconds(1100))
        // Only return to the composer if the user hasn't navigated away (e.g. opened search) meanwhile.
        if phase == .formed {
            // Fixed-duration outro (not a spring): its settle time is deterministic, so the wait
            // below always outlasts it and the blob is fully gone before we swap back to the composer.
            withAnimation(.easeIn(duration: 0.28)) { formedShown = false }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.2)) { phase = .composing }
            // Tap-to-focus: settle back to the resting home; the new fil is in the Bin below.
        }
        await afterUserFilCreated()
    }

    /// After a user's own fil: the gentle review ask, and — on their first ever fil — a quiet
    /// congrats beat followed by the one-time "from mason" seed reveal.
    private func afterUserFilCreated() async {
        maybeRequestReview()
        // Seed only once, and only when we're back on the composer (not if the user navigated away
        // during the settle) — otherwise wait and reveal after their next fil.
        guard firstUserFilAt == 0, phase == .composing, !didSeedWelcomeFil else { return }
        firstUserFilAt = Date.now.timeIntervalSince1970
        await revealWelcomeFil()
    }

    /// Seeds the one-time "from mason" welcome quietly, as real content: a "From Mason" folder holding
    /// the welcome fil — no congrats overlay, no creating-blob animation. Runs once, ever.
    private func revealWelcomeFil() async {
        didSeedWelcomeFil = true
        // Insert inside an animation so the new folder eases into the home's folder list.
        withAnimation(.snappy(duration: 0.35)) {
            _ = insertWelcomeFil()
        }
        modelContext.saveOrLog()
        SoundscapeManager.shared.playArticleMadeSound()
        Haptics.success()
    }

    /// Builds the fixed "from mason" seed fil (no AI) with two filaments: "filament", a text note
    /// explaining the idea, and "here", a stack of getting-started notes. Deletable like any fil.
    private func insertWelcomeFil() -> (folder: Folder, note: Note) {
        // The seed lands as real content: a "From Mason 👋" folder holding the welcome fil.
        let folder = Folder(
            name: "From Mason 👋",
            gradientStartHex: WelcomeFil.gradientStart,
            gradientEndHex: WelcomeFil.gradientEnd
        )
        let note = Note(
            title: WelcomeFil.title,
            transcript: WelcomeFil.transcript,
            keyword: WelcomeFil.title,
            gradientStartHex: WelcomeFil.gradientStart,
            gradientEndHex: WelcomeFil.gradientEnd
        )
        note.folder = folder

        let filament = KeywordAttachment(keyword: WelcomeFil.filamentKeyword, note: note)
        filament.entries = [AttachmentEntry(kind: .textNote, text: WelcomeFil.filamentNote, noteTitle: WelcomeFil.filamentNoteTitle)]
        // The "here" filament: the getting-started notes. They previously hung off a "tips"
        // keyword that never appeared in the transcript, so nothing highlighted and the notes were
        // unreachable. "here" is in the text.
        let example = KeywordAttachment(keyword: WelcomeFil.exampleKeyword, note: note)
        example.entries = [
            AttachmentEntry(kind: .textNote, text: WelcomeFil.voiceNote, noteTitle: WelcomeFil.voiceNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.linksNote, noteTitle: WelcomeFil.linksNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.searchNote, noteTitle: WelcomeFil.searchNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.landfilNote, noteTitle: WelcomeFil.landfilNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.signoffNote, noteTitle: WelcomeFil.signoffNoteTitle),
        ]

        note.attachments = [filament, example]

        modelContext.insert(folder)
        modelContext.insert(note)
        return (folder, note)
    }

    /// Requests an App Store review after a genuine "aha" moment — a fil the user just made — but
    /// only once, and only after a few fils, so the ask lands on a happy beat. StoreKit throttles
    /// how often the prompt actually shows.
    private func maybeRequestReview() {
        guard !didRequestReview, notes.count >= 3 else { return }
        didRequestReview = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }


    private func runQuery() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        recordSearch(q)
        composerFocused = false
        summary = ""
        surfaceError = nil
        results = []
        isFilterQuery = false
        suggestedQuery = ""
        searchToken &+= 1
        let token = searchToken
        isRetrieving = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .results }

        // Metadata/filter queries (type, time, to-dos) are answered deterministically from the fils'
        // real fields — reliable and free for everyone, no model call, no text-matching gaps. Only
        // content/semantic queries fall through to keyword (free) or cloud (Pro) search.
        if let filter = MetadataQuery.classify(q) {
            isFilterQuery = true
            runMetadataFilter(filter)
            // Pro: the filter is instant, but reflect on the text-bearing fils in the set and stream the
            // summary in above the grid once it returns (a photo/pdf/video-only set has nothing to read,
            // so this no-ops). Not awaited, so the grid reveals immediately.
            if StoreManager.shared.isPro {
                Task { await summarizeMetadataResults(query: q, filter: filter, token: token) }
            }
        } else if StoreManager.shared.isPro {
            // Capability split: Pro (and active trial) get cloud AI surfacing + summary; everyone else
            // gets free on-device keyword search. See docs/monetization/blank-canvas-pivot-plan.md.
            await runCloudSurfacing(q)
        } else {
            runLocalSearch(q)
        }

        isRetrieving = false
    }

    /// Fils whose blob carries its own artwork (photo image, link favicon, or voice waveform) render
    /// via NoteCardView; plain text fils get the gradient blob.
    private func hasBlobArtwork(_ note: Note) -> Bool {
        note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty
    }

    /// Pro path: send the fil corpus + query to the surfacing proxy (Claude) for a warm summary and
    /// semantic/temporal/thematic selection.
    private func runCloudSurfacing(_ q: String) async {
        // Send a shortlist, not the whole library, so cost + latency don't scale with library size.
        let candidates = candidateNotes(for: q)
        let inputs = candidates.map { note in
            FilClusterInput(id: note.uuid, text: clusterText(note), keyword: displayTitle(note), metadata: filMetadata(note))
        }

        // Search tracing (off by default; see FilLog.searchTracing): confirm the payload, incl. link page text.
        if FilLog.searchTracing {
            FilLog.search.notice("query=\"\(q, privacy: .public)\" candidates=\(candidates.count, privacy: .public) links=\(candidates.filter { $0.isLinkFil }.count, privacy: .public)")
            for note in candidates where note.isLinkFil {
                FilLog.search.notice("LINK payload: \(self.clusterText(note), privacy: .public)")
            }
        }

        let txn = StoreManager.shared.proTransactionID ?? ""
        do {
            let outcome = try await ClaudeSurfacingService.shared.surface(query: q, fils: inputs, transactionID: txn)
            let surfaced = outcome.relevantIDs.compactMap { notesByID[$0] }
            if FilLog.searchTracing {
                FilLog.search.notice("MODEL picked \(surfaced.count, privacy: .public): [\(surfaced.map { "\(self.filKind($0)):\(self.displayTitle($0))" }.joined(separator: " | "), privacy: .public)] summaryLen=\(outcome.summary.count, privacy: .public)")
            }

            if surfaced.isEmpty {
                // The model couldn't place the query semantically (e.g. an invented project name).
                // Fall back to the literal keyword floor, and if it found anything, ask the proxy for a
                // reflection of just those — so keyword-first results still get a summary.
                let keyword = keywordMatches(for: q, requireAll: true)
                if FilLog.searchTracing {
                    FilLog.search.notice("KEYWORD-FALLBACK \(keyword.count, privacy: .public): [\(keyword.map { "\(self.filKind($0)):\(self.displayTitle($0))" }.joined(separator: " | "), privacy: .public)]")
                }
                results = keyword
                if keyword.isEmpty {
                    summary = ""
                    // Nothing matched at all — offer the model's nearby query the corpus can answer.
                    suggestedQuery = outcome.suggestion
                    if FilLog.searchTracing {
                        FilLog.search.notice("SUGGESTION: \"\(outcome.suggestion, privacy: .public)\"")
                    }
                } else {
                    // Cap the summarize payload: `keyword` (best-first) can be hundreds for a common
                    // word, and every one would be billed tokens. The grid still shows them all.
                    let kwInputs = keyword.prefix(Self.timeWindowCap).map { FilClusterInput(id: $0.uuid, text: clusterText($0), keyword: displayTitle($0), metadata: filMetadata($0)) }
                    summary = (try? await ClaudeSurfacingService.shared.summarize(query: q, fils: kwInputs, transactionID: txn)) ?? ""
                }
            } else {
                // The model made a semantic selection — use it + its summary, and union any all-term
                // literal matches it missed (recall floor).
                summary = outcome.summary
                var merged = surfaced
                var seen = Set(surfaced.map(\.uuid))
                for note in keywordMatches(for: q, requireAll: true) where seen.insert(note.uuid).inserted {
                    merged.append(note)
                }
                results = merged
            }
            // Capture the checklist membership once, so it's stable while the user toggles to-dos.
            todoFilIDs = Set(results.filter { !$0.isImageFil && hasOpenTodos($0) }.map(\.uuid))
        } catch {
            // Graceful fallback: run keyword search, and word the note by whether it found anything.
            runLocalSearch(q)
            surfaceError = results.isEmpty
                ? "smart search couldn't be reached, and no keyword matches either."   // path F
                : "smart search is unavailable right now, so here are keyword matches." // path E
        }
    }

    /// Answer a metadata/filter query from the fils' real fields (type, timestamp, to-do flag) — the
    /// deterministic path that makes "photos", "links", "today", "todos" reliable for every tier.
    private func runMetadataFilter(_ filter: MetadataQuery.Filter) {
        var matched = notes   // newest-first from the @Query sort

        // Type + to-do filters FIRST, so a combined query like "recent photos" means "the newest
        // photos", not "photos among the 30 newest fils" (which drops photos outside that window).
        if !filter.types.isEmpty {
            matched = matched.filter { note in filter.types.contains { matchesType(note, $0) } }
        }
        if filter.todosOnly {
            matched = matched.filter(hasOpenTodos)
        }

        // Then the time window / cap over what remains. `recent`/`forgotten` are count-based (top/bottom
        // N); every other spec resolves to a calendar-aligned date interval.
        switch filter.time {
        case .none:            break
        case .some(.recent):   matched = Array(matched.prefix(Self.timeWindowCap))
        case .some(.forgotten): matched = Array(matched.reversed().prefix(Self.timeWindowCap))   // oldest first
        case .some(let spec):
            if let interval = spec.interval(now: Date()) {
                matched = matched.filter { interval.contains($0.timestamp) }
            }
        }

        results = matched
        todoFilIDs = Set(matched.filter { !$0.isImageFil && hasOpenTodos($0) }.map(\.uuid))
    }

    /// Pro extra on a metadata/filter result: once the grid is on screen, ask the proxy to reflect on
    /// the fils that actually carry text (notes, voice, links) and stream that summary in above the
    /// grid. A set with nothing readable (only photos/pdfs/videos, which need vision/extraction we don't
    /// have yet) or a lone fil is skipped — no weak reflections, no wasted call. A newer search bumps
    /// `searchToken`, so a late reply here discards itself instead of clobbering fresher results.
    private func summarizeMetadataResults(query q: String, filter: MetadataQuery.Filter, token: Int) async {
        let all = results.filter(isSummarizable)
        guard all.count >= 2 else { return }

        // For a window bigger than the cap, sample across its span (front-weighted to earlier buckets)
        // so a "this year" reflection covers the whole arc, not just the freshest fils.
        let window = filter.time?.interval(now: Date())
        let fils = summarySample(all, window: window, cap: Self.timeWindowCap)
        if FilLog.searchTracing {
            FilLog.search.notice("META-SUMMARY query=\"\(q, privacy: .public)\" window=\"\(filter.time?.label ?? "-", privacy: .public)\" sampled=\(fils.count, privacy: .public)/\(all.count, privacy: .public) shown=\(self.results.count, privacy: .public)")
        }
        let inputs = fils.map { FilClusterInput(id: $0.uuid, text: clusterText($0), keyword: displayTitle($0), metadata: filMetadata($0)) }
        let txn = StoreManager.shared.proTransactionID ?? ""
        guard let text = try? await ClaudeSurfacingService.shared.summarize(query: q, fils: inputs, transactionID: txn, window: filter.time?.label),
              !text.isEmpty, token == searchToken else { return }
        withAnimation(.easeOut(duration: 0.3)) { summary = text }
    }

    /// Choose up to `cap` fils to summarize. When the set fits, take it whole. When a dated `window`
    /// overflows, slice the window into time-buckets and allocate the budget front-weighted (earlier
    /// buckets get more, every non-empty bucket at least one), picking evenly-spaced fils within each —
    /// so the summary spans the whole window instead of collapsing onto the most recent fils. With no
    /// window (recent/forgotten, already position-capped), just take the first `cap`. Returns fils
    /// chronologically (oldest first).
    private func summarySample(_ fils: [Note], window: DateInterval?, cap: Int) -> [Note] {
        guard fils.count > cap else { return fils.sorted { $0.timestamp < $1.timestamp } }
        let sorted = fils.sorted { $0.timestamp < $1.timestamp }
        guard let window, window.duration > 0 else { return Array(sorted.suffix(cap)) }

        // Up to 12 buckets (≈months for a year, ≈weeks for a month), one per day for short spans.
        let days = window.duration / 86_400
        let bucketCount = min(12, max(2, Int(days.rounded())))
        let width = window.duration / Double(bucketCount)
        var buckets = Array(repeating: [Note](), count: bucketCount)
        for note in sorted {
            let offset = note.timestamp.timeIntervalSince(window.start)
            let idx = min(bucketCount - 1, max(0, Int(offset / width)))
            buckets[idx].append(note)
        }

        // Non-empty buckets, oldest first, with a linear-decay weight (oldest = M ... newest = 1).
        let nonEmpty = buckets.indices.filter { !buckets[$0].isEmpty }
        let m = nonEmpty.count
        let weights = (0..<m).map { m - $0 }
        let totalWeight = max(1, weights.reduce(0, +))

        var picked: [Note] = []
        for (rank, b) in nonEmpty.enumerated() {
            let slots = max(1, Int((Double(cap) * Double(weights[rank]) / Double(totalWeight)).rounded()))
            picked += evenlySpaced(buckets[b], slots)
        }
        // Rounding + the min-1 floor can overshoot; trim from the end (newest, lowest priority).
        if picked.count > cap { picked = Array(picked.prefix(cap)) }
        return picked
    }

    /// `n` items from `arr`, evenly spaced by index (endpoints included); the whole array if `n` covers
    /// it, the middle element if `n == 1`.
    private func evenlySpaced(_ arr: [Note], _ n: Int) -> [Note] {
        guard n > 0, !arr.isEmpty else { return [] }
        guard n < arr.count else { return arr }
        guard n > 1 else { return [arr[arr.count / 2]] }
        return (0..<n).map { arr[Int((Double($0) * Double(arr.count - 1) / Double(n - 1)).rounded())] }
    }

    /// A fil carries enough text to reflect on: typed notes, voice (transcript), and links (captured
    /// page text). Photos have no readable text, and pdfs/videos need extraction we haven't built, so
    /// they're excluded from summaries.
    private func isSummarizable(_ note: Note) -> Bool {
        switch filKind(note) {
        case "note", "voice", "link": return true
        default:                       return false
        }
    }

    /// How many fils a "recent" / "forgotten" query returns.
    private static let timeWindowCap = 30

    private func matchesType(_ note: Note, _ type: MetadataQuery.FilType) -> Bool {
        switch type {
        case .photo: return note.isImageFil
        case .link:  return note.isLinkFil
        case .voice: return !note.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .video: return noteHasEntry(note, .video)
        case .pdf:   return noteHasEntry(note, .pdf)
        case .note:  return filKind(note) == "note"
        }
    }

    private func noteHasEntry(_ note: Note, _ kind: AttachmentEntry.Kind) -> Bool {
        note.attachments.contains { $0.entries.contains { $0.kind == kind } }
    }

    /// Free path: case-insensitive match over each fil's full text (title, transcript, and
    /// filaments). No network, no summary, no counter — the free tier's way to find fils by words you
    /// remember. (Semantic / temporal / thematic queries and the summary are the Pro upgrade.)
    private func runLocalSearch(_ q: String) {
        let matched = keywordMatches(for: q)
        results = matched
        todoFilIDs = Set(matched.filter { !$0.isImageFil && hasOpenTodos($0) }.map(\.uuid))
    }

    /// Literal keyword matches across a fil's full text, best-first (most terms matched, then newest).
    /// The free tier's whole search, and the Pro tier's recall floor so a word that's actually written
    /// in a fil is never missed by the model's stricter semantic judgment.
    /// - Parameter requireAll: when true, a fil must contain EVERY query term (a strong literal match)
    ///   to count — used by the Pro recall floor so a multi-word query like "app development links"
    ///   doesn't union in a fil that merely mentions one word ("links"). Free keyword search stays OR
    ///   (any term), the familiar search-engine behavior.
    private func keywordMatches(for q: String, requireAll: Bool = false) -> [Note] {
        let terms = q.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        return notes
            .compactMap { note -> (note: Note, hits: Int)? in
                let haystack = searchableText(note)
                let hits = terms.reduce(0) { $0 + (Self.containsWord(haystack, $1) ? 1 : 0) }
                let ok = requireAll ? (hits == terms.count) : (hits > 0)
                return ok ? (note, hits) : nil
            }
            .sorted { ($0.hits, $0.note.timestamp) > ($1.hits, $1.note.timestamp) }
            .map(\.note)
    }

    /// Whole-word containment: the term must appear bounded by non-alphanumerics, so "app" matches
    /// "app" but not "appeared" / "application" / "app.notion.com" (the substring pollution the
    /// keyword floor was pulling in). Haystack is already lowercased.
    private static func containsWord(_ haystack: String, _ term: String) -> Bool {
        guard !term.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }

    /// A fil's full searchable text, lowercased: title, transcript, its own keyword, and every
    /// filament (attachment keyword + entry text / link captions / linked-note titles). Shared by
    /// free local search and the cloud pre-filter.
    private func searchableText(_ note: Note) -> String {
        [note.title, note.transcript, note.keyword, todoText(note), filamentContent(note), linkPageText(note)]
            .joined(separator: " ")
            .lowercased()
    }

    /// The fil's to-do item text (open + done), so searches match a to-do's words, not just its
    /// presence. Blank rows dropped.
    private func todoText(_ note: Note) -> String {
        note.todos
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The meaningful text carried by a fil's filaments — attached notes, links (caption + URL),
    /// linked-fil titles, PDF names, and simple markers for media. Shared by the free keyword
    /// haystack and the Pro cloud payload so rich content is searchable in both.
    private func filamentContent(_ note: Note) -> String {
        var parts: [String] = []
        for attachment in note.attachments {
            parts.append(attachment.keyword)
            for entry in attachment.entries {
                switch entry.kind {
                case .textNote:   if let t = entry.text { parts.append(t) }
                case .link:       parts.append(contentsOf: [entry.linkCaption, entry.text].compactMap { $0 })
                case .linkedNote: if let t = entry.text { parts.append(t) }   // the linked fil's title
                case .pdf:        if let n = entry.pdfName { parts.append(n) }
                case .file:       if let n = entry.fileName { parts.append(n) }
                case .video:      parts.append("video")
                case .recording:  parts.append("voice memo")
                case .image:      parts.append("photo")
                }
                if let noteTitle = entry.noteTitle { parts.append(noteTitle) }
            }
        }
        return parts.joined(separator: " ")
    }

    /// Shortlist the fils sent to the cloud so cost (and latency) don't scale with library size.
    /// Small libraries send everything; larger ones send the fils that match the query across all
    /// text fields (best first), then fill with the most-recent fils for temporal context — capped.
    /// A generous net, not a precise answer: Claude still does the fine selection on what it's given.
    private func candidateNotes(for q: String) -> [Note] {
        let sendAllThreshold = 50   // at or below this, the whole library is already cheap to send
        guard notes.count > sendAllThreshold else { return notes }

        let recentFloor = 40        // always include this many newest fils (covers "recently"/"today")
        let maxCandidates = 60      // hard cap on what we send

        var picked: [Note] = []
        var seen = Set<UUID>()
        func add(_ note: Note) {
            if seen.insert(note.uuid).inserted { picked.append(note) }
        }

        // 1) Query-term matches across all fields, best first.
        let terms = q.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if !terms.isEmpty {
            let matches = notes.compactMap { note -> (note: Note, hits: Int)? in
                let haystack = searchableText(note)
                let hits = terms.reduce(0) { $0 + (Self.containsWord(haystack, $1) ? 1 : 0) }
                return hits > 0 ? (note, hits) : nil
            }
            .sorted { ($0.hits, $0.note.timestamp) > ($1.hits, $1.note.timestamp) }
            matches.forEach { add($0.note) }
        }

        // 2) Fill with the most-recent fils (notes is newest-first).
        notes.prefix(recentFloor).forEach(add)

        return Array(picked.prefix(maxCandidates))
    }

    /// Text handed to retrieval: the fil's title + a short content snippet, so topical relevance keys
    /// on the actual thought, not just the title.
    private func clusterText(_ note: Note) -> String {
        let title = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var text: String
        switch (title.isEmpty, body.isEmpty) {
        case (false, false): text = "\(title): \(String(body.prefix(140)))"
        case (false, true):  text = title
        case (true, false):  text = String(body.prefix(140))
        case (true, true):   text = "thought"
        }
        // Include filament content so Claude can surface a fil by what's attached to it (a linked
        // note, a link, a PDF), capped so per-fil payload cost stays bounded.
        let todos = todoText(note).trimmingCharacters(in: .whitespacesAndNewlines)
        if !todos.isEmpty {
            text += " — to-dos: \(String(todos.prefix(160)))"
        }
        let filaments = filamentContent(note).trimmingCharacters(in: .whitespacesAndNewlines)
        if !filaments.isEmpty {
            text += " — attached: \(String(filaments.prefix(200)))"
        }
        // A link fil's captured page (title + description) — the actual content, not just the URL, so
        // "app development links" can match by what the page is about.
        let page = linkPageText(note).trimmingCharacters(in: .whitespacesAndNewlines)
        if !page.isEmpty {
            text += " — link: \(String(page.prefix(300)))"
        }
        return text
    }

    /// A link fil's fetched page text (title + og:description), shared by the cloud payload and the
    /// keyword haystack so link fils are findable by their content, not just their URL. Empty for
    /// non-link fils.
    private func linkPageText(_ note: Note) -> String {
        guard note.isLinkFil else { return "" }
        return [note.sourceTitle, note.sourceDescription]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Compact "(when, type, to-dos)" tag so Claude can answer temporal / type / to-do queries,
    /// not just semantic ones. e.g. "2d ago, photo, open to-dos".
    private func filMetadata(_ note: Note) -> String {
        var parts = [relativeDate(note.timestamp), filKind(note)]
        if hasOpenTodos(note) { parts.append("open to-dos") }
        return parts.joined(separator: ", ")
    }

    private func filKind(_ note: Note) -> String {
        if note.isLinkFil { return "link" }
        if note.isImageFil { return "photo" }
        if !note.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "voice" }
        return "note"
    }

    private func hasOpenTodos(_ note: Note) -> Bool {
        guard !note.todos.isEmpty else { return false }
        return note.todos.indices.contains { index in
            index >= note.completedTodos.count || !note.completedTodos[index]
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1:      return "today"
        case 1:         return "yesterday"
        case 2...6:     return "\(days)d ago"
        case 7...29:    return "\(days / 7)w ago"
        case 30...364:  return "\(days / 30)mo ago"
        default:        return "\(days / 365)y ago"
        }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Text fils no longer carry a title, so fall back to a snippet of the thought itself.
        let title = !trimmed.isEmpty ? trimmed : (body.isEmpty ? "thought" : String(body.prefix(80)))
        return title
    }
}
