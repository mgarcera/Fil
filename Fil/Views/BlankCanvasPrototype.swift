import SwiftUI
import SwiftData

/// TEMPORARY prototype — the "blank canvas" home direction (2026-07-10, see
/// docs/features/blank-canvas-home.md): the home is empty; you TAP to capture a thought and
/// LONG-PRESS to surface past fils by a domain query.
///
///   tap        → creation blob + centered field → type → fil pops into being → blank
///   long-press → query field → type a domain → matching fils surface
///
/// Phase-2 surfacing is retrieval only (no LLM summary yet) — validates that a query finds the
/// right fils before we commit to "only via query". Reached via the temporary ▦ button in the
/// ContentView header. Delete both when promoted.
struct BlankCanvasPrototype: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]
    @AppStorage("prefersLowercase") private var prefersLowercase = false

    private enum Phase { case composing, creating, formed, querying, results }

    /// The settled fil blob pops in — scales up from near-zero with a snappy, punchy spring.
    private static let popTransition = AnyTransition.scale(scale: 0.01).combined(with: .opacity)
    private static let popAnimation = Animation.spring(response: 0.24, dampingFraction: 0.46)

    /// Rotating search-field prompts — like the old composer's rotating placeholder — that also teach
    /// the flexible query types (semantic, temporal, type, to-dos).
    private static let queryPrompts = [
        "search your thoughts",
        "what have i been avoiding?",
        "recent to-dos",
        "photos i've saved",
        "things i might've forgotten",
        "what's been on my mind lately",
    ]
    private static let queryPromptInterval: TimeInterval = 3.5

    /// When embedded as the ContentView home, chrome (close) hides and the header owns it, and
    /// surfacing is triggered externally (the header search button) via `surfaceRequested`.
    var showsChrome: Bool = true
    @Binding var surfaceRequested: Bool

    @State private var phase: Phase = .composing
    @State private var text = ""
    /// The just-made fil, so the gooey creating blob can settle into its final randomized blob.
    @State private var formedNote: Note?

    // Surfacing (dev-key Claude spike)
    @State private var query = ""
    @State private var results: [Note] = []
    @State private var summary = ""
    @State private var surfaceError: String?
    @State private var isRetrieving = false
    @State private var selectedNote: Note?
    @State private var showKeyEntry = false
    /// TEMP: local-only Claude key for the spike. Never committed, never shipped.
    @AppStorage("claudeDevKey") private var devKey = ""
    /// Recent search terms, newline-joined, most-recent first (persisted on-device, capped).
    @AppStorage("recentSearchesRaw") private var recentSearchesRaw = ""

    @FocusState private var fieldFocused: Bool
    @FocusState private var queryFocused: Bool

    private var notesByID: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.uuid, $0) })
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCanvasTap() }

            switch phase {
            case .composing: composer
            case .creating:  creatingBlob
            case .formed:    formedBlob
            case .querying:  queryField
            case .results:   resultsList
            }

            if phase == .composing && hasText {
                sendFAB
            }

            if phase == .querying && query.isEmpty && !recentSearches.isEmpty {
                recentChipsBar
            }

            if showsChrome {
                closeButton
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hasText)
        .sheet(item: $selectedNote) { note in
            NavigationStack { ArticleView(note: note) }
                .presentationDetents([.fraction(0.6), .large])
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showKeyEntry) { keyEntrySheet }
        // The header search button (when embedded) requests surfacing; enter the query field.
        .onChange(of: surfaceRequested) { _, requested in
            if requested {
                beginSurface()
                surfaceRequested = false
            }
        }
    }

    private func beginSurface() {
        query = ""
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .querying }
        queryFocused = true
    }

    // MARK: - Capture states

    /// Writing surface: just the text input, left-aligned in the upper-left. Sending is the FAB.
    /// This is the home's resting state — "let a thought be" is the entrance.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $text, axis: .vertical)
                .font(Theme.dmSans(20, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(1...12)
                .focused($fieldFocused)
                .submitLabel(.return)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        AnimatedGradientRevealText(text: "let a thought be")
                            .font(Theme.dmSans(20, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
                .onSubmit { Task { await createFil() } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .transition(.opacity)
    }

    /// Floating send button, bottom-trailing, shown while composing. Rides above the keyboard.
    private var sendFAB: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
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
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var creatingBlob: some View {
        CreatingFilBlobView()
            .frame(width: 130, height: 130)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.2).combined(with: .opacity),
                removal: .opacity
            ))
    }

    /// The fil's final, settled randomized blob — same shape/gradient the grid card shows. It pops in
    /// over the gooey creating blob (the "blob turns into a fil" morph), holds, then fades.
    @ViewBuilder
    private var formedBlob: some View {
        if let note = formedNote {
            NoteBlobShape(seed: note.blobShapeSeed)
                .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                .frame(width: 130, height: 130)
                .transition(Self.popTransition)
        }
    }

    // MARK: - Surfacing states

    /// The query field to surface past fils, positioned exactly like the composer's "let a thought
    /// be" entrance — upper-left, left-aligned. Opened from the header search.
    private var queryField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $query, axis: .horizontal)
                .font(Theme.dmSans(20, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .focused($queryFocused)
                .submitLabel(.search)
                .overlay(alignment: .topLeading) {
                    if query.isEmpty {
                        TimelineView(.periodic(from: .now, by: Self.queryPromptInterval)) { context in
                            let index = Int(context.date.timeIntervalSinceReferenceDate / Self.queryPromptInterval) % Self.queryPrompts.count
                            AnimatedGradientRevealText(text: Self.queryPrompts[index], maxDuration: 1.2, settledOpacity: 0.4)
                                .font(Theme.dmSans(20, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onSubmit { Task { await runQuery() } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .transition(.opacity)
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
                        Text("surfacing…")
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 16)
                } else if let surfaceError {
                    Text(surfaceError)
                        .font(Theme.dmSans(15))
                        .foregroundStyle(.orange)
                        .padding(.top, 16)
                } else {
                    if !summary.isEmpty {
                        AnimatedGradientRevealText(text: prefersLowercase ? summary.lowercased() : summary, elementDuration: 0.2, perElementDelay: 0.006, minDuration: 0.4)
                            .font(Theme.dmSans(16, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if results.isEmpty {
                        Text("nothing surfaced for “\(query)”")
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        scrapbook
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private func blobCell(_ note: Note) -> some View {
        Button { selectedNote = note } label: {
            // Blob and title share the same 120pt-wide column, centered in the grid cell. The title
            // text is left-aligned *within* that 120pt block, so it reads left-aligned but lines up
            // under the blob rather than spanning the whole cell. Photo fils show their image (blob-
            // clipped, like the main-branch card) instead of a gradient blob.
            VStack(alignment: .center, spacing: 14) {
                Group {
                    if note.isImageFil {
                        NoteCardView(note: note, showsKeywordBadge: false)
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
        }
        .buttonStyle(.plain)
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
    // plus a to-do checklist section when to-do fils are present.
    private var todoResults: [Note] { results.filter { !$0.isImageFil && hasOpenTodos($0) } }
    private var gridResults: [Note] { results.filter { $0.isImageFil || !hasOpenTodos($0) } }

    /// Summary sits above; here photos + notes + links share the grid, and any to-do fils get a
    /// checklist beneath. A pure "to-dos" query shows just the checklist.
    private var scrapbook: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !gridResults.isEmpty {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 28) {
                    ForEach(gridResults, id: \.uuid) { blobCell($0) }
                }
            }
            if !todoResults.isEmpty { todoChecklist(todoResults) }
        }
        .padding(.top, 4)
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
                                .frame(width: 26, height: 26)
                            Text(displayTitle(note))
                                .font(Theme.dmSans(18, weight: .bold))
                                .foregroundStyle(Theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(openTodoItems(note), id: \.index) { item in
                        TodoRowContent(text: item.text, isCompleted: item.done) {
                            toggleTodo(note, item.index)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openTodoItems(_ note: Note) -> [(index: Int, text: String, done: Bool)] {
        note.todos.enumerated().compactMap { index, text in
            let done = index < note.completedTodos.count ? note.completedTodos[index] : false
            return done ? nil : (index, text, done)
        }
    }

    private func toggleTodo(_ note: Note, _ index: Int) {
        guard index < note.todos.count else { return }
        while note.completedTodos.count < note.todos.count { note.completedTodos.append(false) }
        note.completedTodos[index].toggle()
        modelContext.saveOrLog()
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(query)
                .font(Theme.dmSans(24, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Button("new") {
                query = ""
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .querying }
                queryFocused = true
            }
            .font(Theme.dmSans(14, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        }
    }

    /// TEMP dev-key entry for the Claude spike. The key is stored only on-device (AppStorage).
    private var keyEntrySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("claude dev key")
                .font(Theme.dmSans(18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("temporary — for the surfacing spike only. stored on this device, never shipped.")
                .font(Theme.dmSans(13))
                .foregroundStyle(Theme.secondaryText)
            SecureField("sk-ant-…", text: $devKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("done") { showKeyEntry = false }
                .font(Theme.dmSans(15, weight: .semibold))
            Spacer()
        }
        .padding(24)
        .presentationDetents([.height(240)])
        .presentationBackground(Theme.background)
    }

    private var closeButton: some View {
        VStack {
            HStack(spacing: 16) {
                Spacer()
                Button { showKeyEntry = true } label: {
                    Image(systemName: devKey.isEmpty ? "key" : "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("close") { dismiss() }
                    .font(Theme.dmSans(14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
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

    private func onCanvasTap() {
        switch phase {
        case .composing:
            // Tapping the canvas toggles the keyboard on the entrance field.
            fieldFocused.toggle()
        case .querying:
            queryFocused = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .composing }
        case .results:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .composing }
        case .creating, .formed:
            break
        }
    }

    private func createFil() async {
        let thought = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else { return }

        text = ""
        fieldFocused = false

        // Gooey creating blob plops in (its own regular color), holds while the fil forms.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { phase = .creating }
        SoundscapeManager.shared.startMeshDuringProcessSound()

        let title = await ArticleGenerationService.shared.generateTitle(from: thought)
        let gradient = Theme.randomGradientPair()
        let note = Note(
            title: title,
            transcript: thought,
            keyword: title,
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end
        )
        modelContext.insert(note)
        modelContext.saveOrLog()

        SoundscapeManager.shared.stopMeshDuringProcessSound()
        SoundscapeManager.shared.playArticleMadeSound()

        // The gooey blob gives way to the fil's final randomized blob (pop), holds a beat, then fades.
        formedNote = note
        withAnimation(Self.popAnimation) { phase = .formed }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(.easeOut(duration: 0.4)) { phase = .composing }
    }

    private func runQuery() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        guard !devKey.isEmpty else { showKeyEntry = true; return }

        recordSearch(q)
        queryFocused = false
        summary = ""
        surfaceError = nil
        results = []
        isRetrieving = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .results }

        let inputs = notes.map { note in
            FilClusterInput(id: note.uuid, text: clusterText(note), keyword: displayTitle(note), metadata: filMetadata(note))
        }

        do {
            let outcome = try await ClaudeSurfacingService.shared.surface(query: q, fils: inputs, apiKey: devKey)
            summary = outcome.summary
            results = outcome.relevantIDs.compactMap { notesByID[$0] }
        } catch {
            surfaceError = (error as? ClaudeSurfacingService.SurfacingError)?.errorDescription ?? error.localizedDescription
        }
        isRetrieving = false
    }

    /// Text handed to retrieval: the fil's title + a short content snippet, so topical relevance keys
    /// on the actual thought, not just the title.
    private func clusterText(_ note: Note) -> String {
        let title = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (title.isEmpty, body.isEmpty) {
        case (false, false): return "\(title): \(String(body.prefix(140)))"
        case (false, true):  return title
        case (true, false):  return String(body.prefix(140))
        case (true, true):   return "fil"
        }
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
