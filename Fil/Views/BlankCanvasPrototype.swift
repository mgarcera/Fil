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

    private enum Phase { case idle, composing, creating, formed, querying, results }

    /// The settled fil blob pops in — scales up from near-zero with a snappy, punchy spring.
    private static let popTransition = AnyTransition.scale(scale: 0.01).combined(with: .opacity)
    private static let popAnimation = Animation.spring(response: 0.24, dampingFraction: 0.46)

    @State private var phase: Phase = .idle
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
                .onLongPressGesture(minimumDuration: 0.35) { onCanvasLongPress() }

            switch phase {
            case .idle:      idleHint
            case .composing: composer
            case .creating:  creatingBlob
            case .formed:    formedBlob
            case .querying:  queryField
            case .results:   resultsList
            }

            closeButton
        }
        .sheet(item: $selectedNote) { note in
            NavigationStack { ArticleView(note: note) }
                .presentationDetents([.fraction(0.6), .large])
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showKeyEntry) { keyEntrySheet }
    }

    // MARK: - Capture states

    /// The one affordance on an otherwise blank canvas — the whole discoverability of the home.
    private var idleHint: some View {
        VStack(spacing: 6) {
            AnimatedGradientRevealText(text: "tap to begin", maxDuration: 1.2, settledOpacity: 0.35)
                .font(Theme.dmSans(16, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text("press and hold to surface")
                .font(Theme.dmMono(11))
                .foregroundStyle(Theme.tertiaryText)
        }
        .allowsHitTesting(false)
    }

    /// Centered writing surface: a calm blob focal point above a centered field. Return commits.
    private var composer: some View {
        VStack(spacing: 24) {
            CreatingFilBlobView()
                .frame(width: 76, height: 76)
                .opacity(0.9)

            TextField("", text: $text, axis: .vertical)
                .font(Theme.dmSans(20, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1...6)
                .focused($fieldFocused)
                .submitLabel(.return)
                .padding(.horizontal, 32)
                .overlay(alignment: .center) {
                    if text.isEmpty {
                        Text("let a thought be")
                            .font(Theme.dmSans(20, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
                .onSubmit { Task { await createFil() } }

            Button(action: { Task { await createFil() } }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 40, height: 40)
                    .background(Theme.primaryText, in: Circle())
                    .opacity(hasText ? 1 : 0.3)
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
        }
        .padding(.bottom, 80)
        .transition(.opacity)
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

    /// Long-press summons this: a centered query field to surface past fils by domain.
    private var queryField: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.secondaryText)

            TextField("", text: $query, axis: .horizontal)
                .font(Theme.dmSans(22, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
                .focused($queryFocused)
                .submitLabel(.search)
                .padding(.horizontal, 32)
                .overlay(alignment: .center) {
                    if query.isEmpty {
                        Text("surface a thought — try “work”")
                            .font(Theme.dmSans(22, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
                .onSubmit { Task { await runQuery() } }
        }
        .padding(.bottom, 80)
        .transition(.opacity)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultsHeader

            if isRetrieving {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("surfacing…")
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
            } else if let surfaceError {
                Text(surfaceError)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !summary.isEmpty {
                            AnimatedGradientRevealText(text: prefersLowercase ? summary.lowercased() : summary, maxDuration: 2.0)
                                .font(Theme.dmSans(16, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if results.isEmpty {
                            Text("nothing surfaced for “\(query)”")
                                .font(Theme.dmSans(15))
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(results, id: \.uuid) { note in
                                    resultRow(note)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .transition(.opacity)
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

    private func resultRow(_ note: Note) -> some View {
        Button { selectedNote = note } label: {
            HStack(spacing: 12) {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                    .frame(width: 24, height: 24)
                Text(displayTitle(note))
                    .font(Theme.dmSans(15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func onCanvasTap() {
        switch phase {
        case .idle:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .composing }
            fieldFocused = true
        case .composing:
            fieldFocused = false
            if !hasText { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .idle } }
        case .querying:
            queryFocused = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .idle }
        case .results:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .idle }
        case .creating, .formed:
            break
        }
    }

    private func onCanvasLongPress() {
        guard phase == .idle else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .querying }
        queryFocused = true
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
        withAnimation(.easeOut(duration: 0.4)) { phase = .idle }
    }

    private func runQuery() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        guard !devKey.isEmpty else { showKeyEntry = true; return }

        queryFocused = false
        summary = ""
        surfaceError = nil
        results = []
        isRetrieving = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .results }

        let inputs = notes.map { note in
            FilClusterInput(id: note.uuid, text: clusterText(note), keyword: displayTitle(note))
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

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "fil" : trimmed
        return prefersLowercase ? title.lowercased() : title
    }
}
