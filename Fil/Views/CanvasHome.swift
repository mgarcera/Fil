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
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @AppStorage("prefersLowercase") private var prefersLowercase = false
    /// Handedness (shared with the header): the send FAB sits on the left when true, else right.
    @AppStorage("controlsOnLeft") private var controlsOnLeft = false
    /// When on, a created fil animates as a small blob in the recent-fils strip (like the "from
    /// mason" reveal) instead of the full-screen gooey → note blob. Off = the big center animation.
    @AppStorage("smallCreationAnimation") private var smallCreationAnimation = false

    // First-run onboarding, re-homed here because creation now happens on the canvas (not through
    // ContentView.createFil). See docs/onboarding/.
    @AppStorage("didSeedWelcomeFil") private var didSeedWelcomeFil = false
    /// Epoch seconds of the user's first real fil; 0 until then. Gates the one-time seed reveal.
    @AppStorage("firstUserFilAt") private var firstUserFilAt: Double = 0
    /// Ask for a rating at most once, after the user has felt the core loop a few times.
    @AppStorage("didRequestReview") private var didRequestReview = false
    @Environment(\.requestReview) private var requestReview
    /// True only while the quiet "that's a fil" congrats is on screen (before the seed reveal).
    @State private var showWelcomeCongrats = false
    @State private var seedStage: SeedStage = .none
    @State private var seedNote: Note?

    private enum Phase { case composing, recording, creating, formed, querying, results }
    /// The one-time "from mason" seed reveal is smaller than a user's own fil: a little creating
    /// blob morphs into the note blob right by the input, rather than the full-screen hero.
    private enum SeedStage { case none, creating, formed }

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

    /// The header (owned by ContentView) drives `searchActive`: true enters the query screen, false
    /// returns to the composer.
    @Binding var searchActive: Bool
    /// True while surfaced results are on screen, so the header can show a "new search" refresh.
    @Binding var showingResults: Bool
    /// Set true by the header's refresh button to start a fresh search; CanvasHome consumes it.
    @Binding var newSearchRequested: Bool
    /// True while a screensaver is on screen — it overrides the keyboard (resigns composer/query
    /// focus), and focus is restored to the current mode when it dismisses.
    var screensaverActive: Bool = false

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
    /// Surfaced grid blobs that have popped in. They reveal one-by-one like a fil being created;
    /// gating scale/opacity on this drives that entrance (and survives a home trip, so no re-pop).
    @State private var revealedResultIDs: Set<UUID> = []
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
    @State private var showPaywall = false
    @State private var showFeedback = false
    // Voice capture: the mic glyph starts recording; the gooey blob pulses while recording, then
    // flows into the same creation animation typed/link fils use.
    @State private var recorder = VoiceRecorderViewModel()
    @State private var showMicPriming = false
    @State private var recordingPulse = false
    // Photo capture: "add photo" in the composer edit menu opens the picker.
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    /// Photos picked but not yet sent — shown as a strip above the composer; words can be added first.
    @State private var pendingPhotos: [PendingPhoto] = []
    /// Staged photos tapped for a native QuickLook preview (temp file URLs; current + the full set).
    @State private var previewImageURL: URL?
    @State private var previewImageURLs: [URL] = []
    /// The fil sheet's current detent, bound so ArticleView knows when it's expanded to full.
    @State private var filSheetDetent: PresentationDetent = .fraction(0.6)
    /// Navigation path inside the fil sheet, so filaments (and linked fils) can push. Without this,
    /// tapping "filament" / a highlighted word had nowhere to go — the feature was unreachable.
    @State private var filSheetPath: [FilSheetRoute] = []
    /// Fils mid-landfil: they shrink to nothing (like the timeline) before the actual delete.
    @State private var landfillingIDs: Set<UUID> = []
    /// Recent search terms, newline-joined, most-recent first (persisted on-device, capped).
    @AppStorage("recentSearchesRaw") private var recentSearchesRaw = ""

    /// Composer focus. A plain Bool (not @FocusState) so it can drive ComposerTextView's first
    /// responder — the composer is a UITextView (for its custom edit menu), not a SwiftUI TextField.
    @State private var fieldFocused = false
    @FocusState private var queryFocused: Bool

    private var notesByID: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.uuid, $0) })
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch phase {
            case .composing: composer
            case .querying:  queryField
            case .results:   resultsList
            // The creation blobs are rendered below as boolean-gated views, not switch cases: a
            // switch animates a case's insertion but drops its removal transition, so the note blob
            // would pop in with no outro. Gating on `phase` animates both directions.
            case .recording, .creating, .formed: Color.clear
            }

            // Recording and creating share ONE gooey blob so it never tears down between them; it
            // then morphs into the settled note blob, which pops out the same way it popped in.
            if phase == .recording || phase == .creating {
                creatingGooey
            }
            if phase == .formed {
                formedBlob
            }

            if phase == .querying && query.isEmpty && !recentSearches.isEmpty {
                recentChipsBar
            }
            // Compose home: a quick shortcut to recently-made fils, above the keyboard while the
            // field is focused and empty, so it never competes with the blank page or writing.
            // Always shown while a mini creation/seed reveal is animating (even with the keyboard
            // down, e.g. voice/photo) — the new blob morphs in as the bar's leading chip.
            if phase == .composing && pendingPhotos.isEmpty
                && (seedStage != .none || (fieldFocused && !hasText && !recentFils.isEmpty)) {
                recentFilsBar
            }
        }
        // The send FAB floats as an overlay (not a ZStack sibling) so its Button reliably wins hit
        // testing over the full-screen background tap-catcher below.
        .overlay(alignment: controlsOnLeft ? .bottomLeading : .bottomTrailing) {
            // Send needs words — even with photos staged, the user types a caption first.
            if phase == .composing && hasText {
                sendFAB
                    .padding(controlsOnLeft ? .leading : .trailing, 24)
                    .padding(.bottom, 24)
            }
        }
        // While recording, a stop button sits below the pulsing gooey blob.
        .overlay(alignment: .bottom) {
            if phase == .recording {
                stopButton
                    .padding(.bottom, 90)
            }
        }
        // A quiet beat after the user's very first fil, before the "from mason" seed reveals.
        .overlay {
            if showWelcomeCongrats {
                welcomeCongratsOverlay
                    .transition(.opacity)
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
            // Link fils stay at the medium detent (no expand-to-full); other fils can go large.
            .presentationDetents(note.isLinkFil ? [.fraction(0.6)] : [.fraction(0.6), .large], selection: $filSheetDetent)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
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
        .quickLookPreview($previewImageURL, in: previewImageURLs)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 10, matching: .images, photoLibrary: .shared())
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
                fieldFocused = true   // keep composing — words can be added to the photos before sending
            }
        }
        .landfilConfirmation(item: $pendingLandfilNote, message: { _ in
            "this fil will be deleted. this cannot be undone."
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
                    if saved == .querying { queryFocused = true }
                } else if phase != .querying && phase != .results {
                    beginSurface()
                }
            } else {
                // Going home: keep the query + results so they're still there on return. Don't clear.
                if phase == .querying || phase == .results { savedSearchPhase = phase }
                queryFocused = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .composing }
                fieldFocused = true   // returning home: raise the composer keyboard
            }
        }
        // Header sync only. Composer focus is set at genuine entry points (launch, after creating a
        // fil, returning from search) — like the query field — not re-forced on every phase change.
        .onChange(of: phase) { _, newPhase in
            showingResults = (newPhase == .results)
        }
        // A screensaver overrides the keyboard: drop focus while it's up, restore it on dismiss.
        .onChange(of: screensaverActive) { _, active in
            if active {
                fieldFocused = false
                queryFocused = false
                // A screensaver launched from Settings dismisses its sheet ~0.35s later, and SwiftUI
                // would otherwise restore first responder to the composer — re-clear once it settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if screensaverActive {
                        fieldFocused = false
                        queryFocused = false
                    }
                }
            } else {
                switch phase {
                case .composing: fieldFocused = true
                case .querying:  queryFocused = true
                default:         break
                }
            }
        }
        .onAppear {
            // Cold launch lands in the composer — raise the keyboard once the view is ready.
            if phase == .composing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fieldFocused = true }
            }
        }
        // The header's refresh button asks for a fresh search.
        .onChange(of: newSearchRequested) { _, requested in
            if requested {
                beginSurface()
                newSearchRequested = false
            }
        }
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
        revealedResultIDs = []
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .querying }
        queryFocused = true
    }

    // MARK: - Capture states

    /// Writing surface: just the text input, left-aligned in the upper-left. Sending is the FAB.
    /// This is the home's resting state — "let thoughts be" is the entrance.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Staged photos ride above the input as a scrollable strip of rounded squares.
            if !pendingPhotos.isEmpty {
                photoThumbnailStrip
                    .padding(.bottom, 16)
            }
            // UITextView-backed so "record voice" / "add photo" live in its edit menu.
            ComposerTextView(
                text: $text,
                isFocused: $fieldFocused,
                onRecordVoice: startVoiceCapture,
                onAddPhoto: { showPhotoPicker = true }
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty && pendingPhotos.isEmpty {
                        AnimatedGradientRevealText(text: "let thoughts be")
                            .font(Theme.dmSans(20, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 80)
        .transition(.opacity)
    }

    /// Floating send button (positioned by the overlay), shown while composing. Rides above the keyboard.
    private var sendFAB: some View {
        Button { Task { await createFil() } } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    /// Write the staged photos to temp files and open the tapped one in native QuickLook (swipeable).
    private func openPendingPreview(_ tapped: PendingPhoto) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fil-compose-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        var urls: [URL] = []
        var tappedURL: URL?
        for photo in pendingPhotos {
            let url = tempDir.appendingPathComponent("pending-\(photo.id.uuidString).jpg")
            if (try? photo.data.write(to: url)) != nil {
                urls.append(url)
                if photo.id == tapped.id { tappedURL = url }
            }
        }
        previewImageURLs = urls
        previewImageURL = tappedURL
    }

    /// Staged photos as rounded squares in a horizontal scroller above the input; ✕ removes one.
    private var photoThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingPhotos) { photo in
                    Button { openPendingPreview(photo) } label: {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        // A generous (invisible) hit area around the small ✕, easier to tap.
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                pendingPhotos.removeAll { $0.id == photo.id }
                            }
                        } label: {
                            Color.clear
                                .frame(width: 40, height: 40)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(.black.opacity(0.5), in: Circle())
                                        .padding(3)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
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

    /// The query field to surface past fils, positioned exactly like the composer's "let a thought
    /// be" entrance — upper-left, left-aligned. Opened from the header search.
    private var queryField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $query, axis: .vertical)
                .font(Theme.dmSans(20, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .focused($queryFocused)
                .submitLabel(.search)
                .overlay(alignment: .topLeading) {
                    if query.isEmpty {
                        if StoreManager.shared.isPro {
                            // Pro: rotate through the smart-query examples (temporal/type/to-dos) —
                            // accurate suggestions because cloud surfacing can actually answer them.
                            TimelineView(.periodic(from: .now, by: Self.queryPromptInterval)) { context in
                                let index = Int(context.date.timeIntervalSinceReferenceDate / Self.queryPromptInterval) % Self.queryPrompts.count
                                let prompt = Self.queryPrompts[index]
                                let display = prompt == "search your thoughts" ? prompt : "“\(prompt)”"
                                AnimatedGradientRevealText(text: display, maxDuration: 1.2, settledOpacity: 0.4)
                                    .font(Theme.dmSans(20, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                            }
                            .allowsHitTesting(false)
                        } else {
                            // Free: keyword-only search, so don't dangle smart-query suggestions.
                            AnimatedGradientRevealText(text: "search by keyword", maxDuration: 1.2, settledOpacity: 0.4)
                                .font(Theme.dmSans(20, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                                .allowsHitTesting(false)
                        }
                    }
                }
                // A vertical-axis TextField wraps long queries, but the return key inserts a newline
                // instead of submitting; treat that newline as "search" so return still runs the query.
                .onChange(of: query) { _, newValue in
                    if newValue.contains("\n") {
                        query = newValue.replacingOccurrences(of: "\n", with: "")
                        Task { await runQuery() }
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 80)
        .transition(.opacity)
    }

    /// The most recently created fils — a small, capped shortcut, not a full browse.
    private var recentFils: [Note] { Array(notes.prefix(8)) }

    /// Recently-made fils as small blob chips, bottom-anchored so they ride above the keyboard on the
    /// compose home. Tap to open. Photo fils show their image, like the results grid.
    private var recentFilsBar: some View {
        VStack {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // The seed morphs in as the leading chip (gooey → note blob) right here in the bar;
                    // the real seed chip below is held back until the morph finishes so it doesn't dupe.
                    if seedStage != .none {
                        seedInlineReveal
                    }
                    ForEach(recentFils.filter { seedStage == .none || $0.uuid != seedNote?.uuid }) { note in
                        Button { selectedNote = note } label: {
                            Group {
                                if hasBlobArtwork(note) {
                                    NoteCardView(note: note, cardHeight: 36)
                                } else {
                                    NoteBlobShape(seed: note.blobShapeSeed)
                                        .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .scaleEffect(isLandfilling(note) ? 0.01 : 1, anchor: .center)
                            .blur(radius: isLandfilling(note) ? 8 : 0)
                            .opacity(isLandfilling(note) ? 0 : 1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { filContextMenu(note) }
                    }
                }
                .padding(.horizontal, 20)
                // Vertical room so the mini creation blob's pop-in apex (the spring overshoots past
                // 1.0) isn't clipped by the horizontal strip's bounds.
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 4)
    }

    /// Recently-searched terms as tappable glass chips, bottom-anchored so they ride above the
    /// keyboard on the search screen. Tap to re-run.
    private var recentChipsBar: some View {
        VStack {
            Spacer()
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
                                .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 12)
    }

    /// Two-column grid for the surfaced fils. Blobs fill the column width; tweak spacing here.
    private let gridColumns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
    /// Uniform blob size in the results grid. Titles are pinned to this width, so bigger = roomier titles.
    private let gridBlobSize: CGFloat = 150

    /// Everything — query, summary, and the fil grid — scrolls together in one ScrollView.
    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                resultsHeader

                if isRetrieving {
                    HStack(spacing: 10) {
                        ProgressView()
                        AnimatedGradientRevealText(text: "searching…", elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                            .font(Theme.dmSans(15, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 16)
                } else {
                    if let surfaceError {
                        // Gentle, non-blocking note when smart search fails and we fall back to keyword.
                        VStack(alignment: .leading, spacing: 6) {
                            AnimatedGradientRevealText(text: surfaceError, elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                                .font(Theme.dmSans(15, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            // Offer feedback only when we actually fell back to keyword matches (path E).
                            if !results.isEmpty {
                                Button("open feedback form") { showFeedback = true }
                                    .font(Theme.dmSans(14, weight: .medium))
                                    .tint(Theme.filProIndigo)
                            }
                        }
                    }
                    if !summary.isEmpty && !results.isEmpty {
                        AnimatedGradientRevealText(text: prefersLowercase ? summary.lowercased() : summary, elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                            .font(Theme.dmSans(16, weight: .medium))
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
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    /// Shown to free users in place of the AI summary: a calm, non-pushy invitation to Pro
    /// surfacing (their keyword results still render below).
    private var freeSurfaceInvite: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                AnimatedGradientRevealText(text: "found by keyword.", elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                    .font(Theme.dmSans(15, weight: .semibold))
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
                AnimatedGradientRevealText(text: "nothing came up for \(query)", elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                    .font(Theme.dmSans(15, weight: .semibold))
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
            line = AttributedString("nothing came up for it. want to try ")
            line.foregroundColor = Theme.secondaryText
            var link = AttributedString(suggestedQuery)
            link.foregroundColor = Theme.filProIndigo
            link.link = URL(string: "fil-action://suggest")
            var tail = AttributedString(" instead?")
            tail.foregroundColor = Theme.secondaryText
            line.append(link); line.append(tail)
        } else {
            line = AttributedString("nothing came up for it. do you have a ")
            line.foregroundColor = Theme.secondaryText
            var link = AttributedString("thought?")
            link.foregroundColor = Theme.filProIndigo
            link.link = URL(string: "fil-action://compose")
            line.append(link)
        }

        return Text(line)
            .font(Theme.dmSans(15, weight: .semibold))
            .tint(Theme.filProIndigo)
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
    }

    /// "check out fil pro for a smart search" with the "fil pro" wordmark in the multicolor accent
    /// gradient. The full sentence lays out (and wraps) normally in secondary text; the gradient is
    /// masked to show through only the "fil pro" glyphs via an aligned overlay.
    private var filProInviteLine: some View {
        let full = "check out fil pro for a smarter search."
        let word = "fil pro"

        // Base sentence: gray, with the wordmark punched out (clear) so the gradient overlay shows.
        var base = AttributedString(full)
        if let range = base.range(of: word) { base[range].foregroundColor = .clear }

        // Mask: only the wordmark opaque, rest clear — so the gradient fills just those glyphs.
        var mask = AttributedString(full)
        mask.foregroundColor = .clear
        if let range = mask.range(of: word) { mask[range].foregroundColor = .black }

        return Text(base)
            .font(Theme.dmSans(14))
            .foregroundStyle(Theme.secondaryText)
            .overlay { Theme.accentGradient.mask(Text(mask).font(Theme.dmSans(14))) }
            .fixedSize(horizontal: false, vertical: true)
    }

    private func blobCell(_ note: Note) -> some View {
        Button { selectedNote = note } label: {
            // Blob and title share the same 120pt-wide column, centered in the grid cell. The title
            // text is left-aligned *within* that 120pt block, so it reads left-aligned but lines up
            // under the blob rather than spanning the whole cell. Photo fils show their image (blob-
            // clipped, like the main-branch card) instead of a gradient blob.
            VStack(alignment: .center, spacing: 14) {
                Group {
                    if hasBlobArtwork(note) {
                        NoteCardView(note: note, cardHeight: gridBlobSize)
                    } else {
                        NoteBlobShape(seed: note.blobShapeSeed)
                            .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    }
                }
                .frame(width: gridBlobSize, height: gridBlobSize)
                gridTitle(note)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(blobShown(note) ? 1 : 0.01, anchor: .center)
            .blur(radius: isLandfilling(note) ? 8 : 0)
            .opacity(blobShown(note) ? 1 : 0)
        }
        .buttonStyle(.plain)
        .contextMenu { filContextMenu(note) }
    }

    /// A one-line title centers under the blob; a title that wraps to two+ lines left-aligns.
    /// ViewThatFits picks the single-line centered version when it fits the blob width, else the
    /// wrapping left-aligned version — no manual line counting.
    private func gridTitle(_ note: Note) -> some View {
        let title = displayTitle(note)
        return ViewThatFits(in: .horizontal) {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(title)
                .multilineTextAlignment(.leading)
                .frame(width: gridBlobSize, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.dmSans(15, weight: .medium))
        .foregroundStyle(Theme.primaryText)
        .frame(width: gridBlobSize)
    }

    // Mixed-type theme results: one uniform blob grid (photos render as images, same size as notes)
    // plus a to-do checklist section. The split is captured once per query (`todoFilIDs`, set in
    // runQuery) so completing a to-do can't reflow a fil out of the checklist mid-tap.
    private var todoResults: [Note] { results.filter { todoFilIDs.contains($0.uuid) } }
    private var gridResults: [Note] { results.filter { !todoFilIDs.contains($0.uuid) } }
    private var photoResults: [Note] { gridResults.filter { $0.isImageFil } }
    private var otherResults: [Note] { gridResults.filter { !$0.isImageFil } }

    /// Summary sits above; below it the results order is to-dos, then photos, then everything else
    /// (notes / links / voice).
    private var scrapbook: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !todoResults.isEmpty { todoChecklist(todoResults) }
            if !photoResults.isEmpty { blobGrid(photoResults) }
            if !otherResults.isEmpty { blobGrid(otherResults) }
        }
        .padding(.top, 4)
    }

    private func blobGrid(_ notes: [Note]) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 28) {
            ForEach(notes, id: \.uuid) { blobCell($0) }
        }
    }

    /// TodoSheet-style checklist: each fil as a bold header (blob + title), its open to-dos beneath.
    private func todoChecklist(_ notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(notes, id: \.uuid) { note in
                VStack(alignment: .leading, spacing: 10) {
                    Button { selectedNote = note } label: {
                        HStack(spacing: 12) {
                            NoteBlobShape(seed: note.blobShapeSeed)
                                .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                                .frame(width: 36, height: 36)
                            Text(displayTitle(note))
                                .font(Theme.dmSans(18, weight: .bold))
                                .foregroundStyle(Theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { filContextMenu(note) }

                    // All of the fil's to-dos (completed ones struck through), reusing the model's
                    // stable row items so completing one strikes in place instead of vanishing.
                    // Indented past the header blob (36) + spacing (12) so the circle sits under the title.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(note.todoRowItems, id: \.id) { item in
                            TodoRowContent(text: item.text, isCompleted: item.done) {
                                toggleTodo(note, item.index)
                            }
                        }
                    }
                    .padding(.leading, 48)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Long-press menu on a surfaced fil: pin to the lock screen, or landfil it (confirmed).
    @ViewBuilder
    private func filContextMenu(_ note: Note) -> some View {
        Button {
            togglePin(note)
        } label: {
            let pinned = PinnedFilStore.shared.isPinned(note)
            Label(pinned ? "unpin from lock screen" : "pin to lock screen",
                  systemImage: pinned ? "pin.slash" : "pin")
        }
        Button(role: .destructive) {
            pendingLandfilNote = note
        } label: {
            Label("landfil", systemImage: "trash")
        }
    }

    /// Mirrors ArticleView.togglePinnedFil (store + Live Activity).
    private func togglePin(_ note: Note) {
        SoundscapeManager.shared.playTabSound()
        if PinnedFilStore.shared.isPinned(note) {
            PinnedFilStore.shared.unpin()
            Task { await PinnedFilLiveActivityController.unpin() }
        } else {
            let snapshot = PinnedFilStore.shared.pin(note)
            Task { await PinnedFilLiveActivityController.pin(snapshot) }
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
        SoundscapeManager.shared.playLandfilSound()
        // Timeline-style deletion: the fil shrinks + blurs away first, then it's removed + deleted.
        withAnimation(.easeOut(duration: 0.45)) {
            landfillingIDs.insert(id)
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

    /// Mirrors ContentView.toggleTodoFromSheet: normalize, bound-check, sound, toggle, save.
    private func toggleTodo(_ note: Note, _ index: Int) {
        note.normalizeCompletedTodos()
        guard note.completedTodos.indices.contains(index) else { return }
        SoundscapeManager.shared.playTodoArticleToggleSound()
        withAnimation(.snappy) {
            note.completedTodos[index].toggle()
        }
        modelContext.saveOrLog()
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(query)
                .font(Theme.dmSans(24, weight: .bold))
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
        // Photos pending → this is a photo fil (the text becomes its caption).
        if !pendingPhotos.isEmpty {
            await createImageFil(images: pendingPhotos.map(\.data), caption: text)
            return
        }

        let thought = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else { return }

        text = ""

        // Gooey creating blob plops in (full-screen, or mini in the recents strip), holds while the fil forms.
        beginCreation()

        let gradient = Theme.randomGradientPair()
        let note: Note
        if let url = LinkFil.normalizedURL(from: thought) {
            // A bare URL becomes a link fil (favicon + real title fetched in the background), no AI
            // title. Let the gooey blob breathe a beat, since there's no title generation to fill it.
            note = LinkFil.make(url: url, gradient: gradient, in: modelContext)
            try? await Task.sleep(for: .milliseconds(700))
        } else {
            // Floor the creating beat so a near-instant title (e.g. a two-word thought) still lets
            // the gooey blob breathe rather than snapping straight to the settled fil.
            let started = Date()
            let title = await ArticleGenerationService.shared.generateTitle(from: thought)
            note = Note(
                title: title,
                transcript: thought,
                keyword: title,
                gradientStartHex: gradient.start,
                gradientEndHex: gradient.end
            )
            modelContext.insert(note)
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.7 { try? await Task.sleep(for: .seconds(0.7 - elapsed)) }
        }
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        await settleCreatedFil(note)
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
        fieldFocused = false
        await recorder.startRecording()
        guard recorder.isRecording else { return }   // setup failed → stay in the composer
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { phase = .recording }
    }

    /// Stop, transcribe on-device, and create the voice fil — then hand off to the shared creation
    /// animation (gooey blob → settled fil → composer), exactly like a typed fil.
    private func finishRecording() async {
        guard let (url, duration) = recorder.stopRecording() else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .composing }
            fieldFocused = true
            return
        }

        beginCreation()

        let transcript = ((try? await recorder.transcribe(url: url)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let gradient = Theme.randomGradientPair()
        let title = transcript.isEmpty
            ? "voice fil"
            : await ArticleGenerationService.shared.generateTitle(from: transcript)
        let note = Note(
            title: title,
            transcript: transcript,
            audioFilePath: url.lastPathComponent,   // bare filename; resolved against the docs dir
            duration: duration,
            keyword: title,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        modelContext.insert(note)
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        await settleCreatedFil(note)
    }

    // MARK: - Photo capture

    /// Turn a picked image into an image fil, flowing through the same gooey-blob creation animation.
    /// Turn the pending photos (+ optional caption) into one image fil, flowing through the same
    /// gooey-blob creation animation typed fils use.
    private func createImageFil(images: [Data], caption: String) async {
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { pendingPhotos = [] }
        beginCreation()

        // Photo fils always carry a caption (the send FAB requires text), so its title generation
        // fills the creating dwell.
        let title = await ArticleGenerationService.shared.generateTitle(from: caption)

        let gradient = Theme.randomGradientPair()
        let note = Note(
            title: title,
            transcript: caption,
            keyword: title,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        note.imageFilImages = images.enumerated().map { index, data in NoteImage(data: data, order: index, note: note) }
        modelContext.insert(note)
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        await settleCreatedFil(note)
    }

    // MARK: - Creation tail + first-run payoff

    /// Start the creating animation for a user fil. Full-screen gooey by default; when the
    /// small-creation setting is on, a mini gooey in the recent-fils strip while the composer stays.
    private func beginCreation() {
        if smallCreationAnimation {
            // Keep the composer in place; the little blob forms in the recent-fils strip.
            withAnimation(.easeOut(duration: 0.25)) { phase = .composing }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { seedStage = .creating }
        } else {
            fieldFocused = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { phase = .creating }
        }
        SoundscapeManager.shared.startMeshDuringProcessSound()
    }

    /// Shared tail for every user creation path: settle the gooey blob into the note's final blob,
    /// hold a beat, then return to the composer — and run the first-run payoff after a real fil.
    /// Mirrors the two creating styles set up by `beginCreation`.
    private func settleCreatedFil(_ note: Note) async {
        if smallCreationAnimation {
            // Mini: the little gooey in the recent strip morphs into the note blob, then hands off
            // to that fil's real recent chip (same blob, same spot — seamless).
            seedNote = note
            withAnimation(Self.popAnimation) { seedStage = .formed }
            try? await Task.sleep(for: .milliseconds(1500))
            seedStage = .none
            seedNote = nil
            fieldFocused = true
        } else {
            formedNote = note
            formedShown = false
            // Gooey fades out (phase) as the settled blob pops in (formedShown) — the "blob → fil" morph.
            withAnimation(.easeOut(duration: 0.25)) { phase = .formed }
            withAnimation(Self.popAnimation) { formedShown = true }
            try? await Task.sleep(for: .milliseconds(1100))
            // Only return to the composer if the user hasn't navigated away (e.g. opened search) meanwhile.
            if phase == .formed {
                // Fixed-duration outro (not a spring): its settle time is deterministic, so the wait
                // below always outlasts it and the blob is fully gone before we swap back to the
                // composer — otherwise the removal sometimes cut the shrink off (outro "only sometimes").
                withAnimation(.easeIn(duration: 0.28)) { formedShown = false }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.2)) { phase = .composing }
                fieldFocused = true   // ready to write the next thought
            }
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

    /// A quiet congratulation, then the "from mason" seed fil revealed as a small creating blob that
    /// morphs into the note blob right by the input — a gentle welcome, not the full-screen hero the
    /// user's own fils get. Stays on the composer throughout. Runs once, ever.
    private func revealWelcomeFil() async {
        didSeedWelcomeFil = true
        withAnimation(.smooth(duration: 0.5)) { showWelcomeCongrats = true }
        try? await Task.sleep(for: .seconds(2.2))
        withAnimation(.smooth(duration: 0.5)) { showWelcomeCongrats = false }
        try? await Task.sleep(for: .milliseconds(350))

        let note = insertWelcomeFil()
        modelContext.saveOrLog()
        seedNote = note

        // Small gooey creating blob by the input…
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { seedStage = .creating }
        SoundscapeManager.shared.startMeshDuringProcessSound()
        try? await Task.sleep(for: .milliseconds(900))
        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        // …morphs into the settled note blob, holds, then hands off to its real recent-fil chip.
        withAnimation(Self.popAnimation) { seedStage = .formed }
        try? await Task.sleep(for: .milliseconds(1500))
        // Instant, un-animated swap: the reveal chip and the real chip are the same blob at the same
        // spot, so dropping the reveal (and letting the ForEach include the seed) is seamless.
        seedStage = .none
        seedNote = nil
        fieldFocused = true
    }

    /// Builds the fixed "from mason" seed fil (no AI) with two sample filaments: a "filament" text
    /// note and a "here" word that opens a bundled tutorial video. Deletable like any fil.
    private func insertWelcomeFil() -> Note {
        let note = Note(
            title: WelcomeFil.title,
            transcript: WelcomeFil.transcript,
            keyword: WelcomeFil.title,
            gradientStartHex: WelcomeFil.gradientStart,
            gradientEndHex: WelcomeFil.gradientEnd
        )

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

        // The "tips" filament — a small stack of getting-started notes.
        let instructions = KeywordAttachment(keyword: WelcomeFil.tipsKeyword, note: note)
        var tipEntries: [AttachmentEntry] = [
            AttachmentEntry(kind: .textNote, text: WelcomeFil.voiceNote, noteTitle: WelcomeFil.voiceNoteTitle),
        ]
        // A screenshot of the capture menu sits beside the voice note (bundled webp → image entry).
        if let imageURL = Bundle.main.url(
            forResource: WelcomeFil.voiceTipImageResource,
            withExtension: WelcomeFil.voiceTipImageExtension
        ), let imageData = try? Data(contentsOf: imageURL) {
            tipEntries.append(.image(imageData))
        }
        tipEntries.append(contentsOf: [
            AttachmentEntry(kind: .textNote, text: WelcomeFil.linksNote, noteTitle: WelcomeFil.linksNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.searchNote, noteTitle: WelcomeFil.searchNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.landfilNote, noteTitle: WelcomeFil.landfilNoteTitle),
            AttachmentEntry(kind: .textNote, text: WelcomeFil.signoffNote, noteTitle: WelcomeFil.signoffNoteTitle),
        ])
        instructions.entries = tipEntries

        note.attachments = [filament, example, instructions]

        modelContext.insert(note)
        return note
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

    /// The "from mason" seed's small reveal, sized and placed like a recent-fil chip: a little
    /// creating blob that morphs into the note's settled blob (same transitions as the full-screen
    /// creation — gooey fades as the note blob pops in).
    @ViewBuilder
    private var seedInlineReveal: some View {
        ZStack {
            if seedStage == .creating {
                CreatingFilBlobView()
                    // The gooey blob wobbles past its frame; scale it down so it doesn't clip in the
                    // small chip slot (the settled note blob already fits at full size).
                    .scaleEffect(0.7)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if seedStage == .formed, let note = seedNote {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    .transition(Self.popTransition)
            }
        }
        .frame(width: 36, height: 36)
        .allowsHitTesting(false)
    }

    /// A quiet, calm beat after the user's first fil — no confetti. Fades before the seed reveal.
    private var welcomeCongratsOverlay: some View {
        ZStack {
            Theme.background.opacity(0.55).ignoresSafeArea()
            Text("that's a thought.\nit's yours.")
                .font(Theme.dmSans(24, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
        }
        .allowsHitTesting(false)
    }

    private func runQuery() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        recordSearch(q)
        queryFocused = false
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
        revealResults(gridResults)
    }

    /// Pop the surfaced blobs in one after another — each scales up from ~0 with the same bouncy
    /// spring a freshly created fil uses, for the scrapbook reveal.
    private func revealResults(_ blobs: [Note]) {
        revealedResultIDs = []
        for (i, note) in blobs.enumerated() {
            let id = note.uuid
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(Self.popAnimation) { _ = revealedResultIDs.insert(id) }
            }
        }
    }

    /// A grid blob is visible once it has popped in (revealed) and isn't being landfilled.
    private func blobShown(_ note: Note) -> Bool {
        revealedResultIDs.contains(note.uuid) && !isLandfilling(note)
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
        case (true, true):   text = "fil"
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
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
