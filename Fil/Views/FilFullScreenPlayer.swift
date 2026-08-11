import SwiftUI
import SwiftData
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// A full-screen "player" for a single fil, swipeable like a deck of tracks (up/down = prev/next fil).
/// The fil's own gooey blob moves up top, with its title, meta, and to-dos below and a transport bar
/// that adapts: voice fils get real play/scrub (the blob pulses while playing); other types get
/// prev/next. Links are excluded upstream. Background is a static blurred wash (kind to the battery
/// for a screen meant to be left open).
struct FilFullScreenPlayer: View {
    let notes: [Note]
    let startID: UUID
    var onClose: () -> Void = {}

    @Environment(\.modelContext) private var context
    @AppStorage("prefersLowercase") private var prefersLowercase = false

    @State private var index: Int
    @State private var navForward = true       // last nav direction, drives the slide transition
    @State private var noteHeight: CGFloat = 0  // measured note-body height, capped at noteMaxHeight
    @State private var audio = AudioPlayerViewModel()
    @State private var showLandfil = false
    @State private var showAddTodo = false
    @State private var newTodoText = ""
    @State private var editing = false          // expand-focused note editor
    @State private var draft = ""               // editor buffer; committed to note.transcript on Done
    @State private var carouselSwiping = false   // true while a horizontal drag is paging the photo carousel
    @State private var filamentKeyword: FilamentKeyword?   // presents the tapped/selected keyword's filament sheet
    @State private var browserLink: BrowserLink?           // presents the in-app browser for a link fil
    @State private var linkCopied = false                  // brief "copied" state on the URL capsule
    @State private var pendingLandfilTarget: Note?          // deleted in onDisappear, after the sheet is gone
    @FocusState private var editorFocused: Bool

    private let noteMaxHeight: CGFloat = 200

    init(notes: [Note], startID: UUID, onClose: @escaping () -> Void = {}) {
        self.notes = notes
        self.startID = startID
        self.onClose = onClose
        _index = State(initialValue: max(0, notes.firstIndex { $0.uuid == startID } ?? 0))
    }

    private var note: Note { notes[min(index, notes.count - 1)] }
    private var colors: [Color] { [Color(hex: note.gradientStartHex), Color(hex: note.gradientEndHex)] }
    private var isVoice: Bool { !note.audioFilePath.isEmpty }

    private func cased(_ s: String) -> String { prefersLowercase ? s.lowercased() : s }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // The per-fil content slides on button navigation (no swipe).
            ZStack {
                filContent
                    .id(note.uuid)
                    .transition(.asymmetric(
                        insertion: .move(edge: navForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: navForward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(navSwipe)
            if !editing { transport }
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        // A tall sheet: the blurred gradient IS the sheet's background, native swipe-down reveals the
        // dimmed page behind. No custom drag needed.
        .presentationBackground { BlurredFilBackground(colors: colors) }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task(id: note.uuid) { loadAudio(); await backfillLinkDescription() }
        .alert("Landfil this fil?", isPresented: $showLandfil) {
            Button("Landfil", role: .destructive) { landfil() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This thought will be deleted. This cannot be undone.")
        }
        .alert("Add to-do", isPresented: $showAddTodo) {
            TextField("New to-do", text: $newTodoText)
            Button("Add") { addTodo() }
            Button("Cancel", role: .cancel) { newTodoText = "" }
        }
        .sheet(item: $filamentKeyword) { fk in
            KeywordPopup(note: note, keyword: fk.keyword)
        }
        .sheet(item: $browserLink) { bl in
            InAppBrowserView(url: bl.url).ignoresSafeArea()
        }
        #if canImport(UIKit)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; audio.stop(); performPendingLandfil() }
        #else
        .onDisappear { audio.stop(); performPendingLandfil() }
        #endif
    }

    // MARK: - Deck

    /// Horizontal swipe pages between fils (mirrors the ◀ ▶ buttons). Only fires on a clearly
    /// horizontal drag, so the sheet's vertical swipe-down and the note's scroll are unaffected.
    private var navSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !editing, !carouselSwiping else { return }   // let the photo carousel own its own swipe
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 60 else { return }
                advance(value.translation.width < 0 ? 1 : -1)
            }
    }

    private func advance(_ delta: Int) {
        let next = index + delta
        guard notes.indices.contains(next) else { return }
        audio.stop()
        carouselSwiping = false   // a torn-down photo carousel never emits .idle; don't wedge fil-nav
        // Don't reset noteHeight here: it would collapse the still-current outgoing note mid-swipe
        // (the "jump"). The incoming note is a fresh identity (.id(note.uuid)) and re-measures itself.
        navForward = delta > 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            index = next
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    private func loadAudio() {
        audio.stop()
        guard isVoice else { return }
        audio.load(path: note.audioFilePath)
    }

    // MARK: - Actions

    /// Open the filament (keyword attachments) sheet for a tapped highlight or a selected phrase.
    private func openFilament(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filamentKeyword = FilamentKeyword(keyword: trimmed)
    }

    /// Promote a selected phrase in the note into a to-do.
    private func addSelectionTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.snappy) { note.addTodo(trimmed) }
        try? context.save()
    }

    /// Append a to-do to the current fil (mutates in place — the deck array holds live objects).
    private func addTodo() {
        let text = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        newTodoText = ""
        guard !text.isEmpty else { return }
        withAnimation(.snappy) { note.addTodo(text) }
        try? context.save()
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Delete the current fil. The deck array is a snapshot holding this (soon-deleted) object, so we
    /// dismiss FIRST and defer the delete to `onDisappear` — the view is provably gone by then, so it
    /// can never re-render a deleted model (no fixed-delay race).
    private func landfil() {
        pendingLandfilTarget = note
        audio.stop()
        onClose()
    }

    private func performPendingLandfil() {
        guard let target = pendingLandfilTarget else { return }
        pendingLandfilTarget = nil
        FilLandfil.cleanUpResources(for: target)
        context.delete(target)
        try? context.save()
    }

    // MARK: - Edit (expand-focused)

    private func enterEdit() {
        draft = note.transcript
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { editing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editorFocused = true }
    }

    private func finishEdit() {
        note.transcript = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        editorFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { editing = false }
    }

    private func cancelEdit() {
        editorFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { editing = false }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            if editing {
                Button("Cancel") { cancelEdit() }.font(Theme.fredoka(13, weight: .medium))
            } else {
                Button(action: onClose) {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
            Spacer()
            Text(editing ? "editing" : "\(cased(typeLabel))  ·  \(index + 1) / \(notes.count)")
                .font(Theme.fredoka(12, weight: .medium)).monospacedDigit().opacity(0.7)
            Spacer()
            if editing {
                Button("Done") { finishEdit() }.font(Theme.fredoka(13, weight: .semibold))
            } else {
                Menu {
                    if !note.isLinkFil {
                        Button { enterEdit() } label: { Label("Edit note", systemImage: "pencil") }
                    }
                    Button { newTodoText = ""; showAddTodo = true } label: { Label("Add to-do", systemImage: "checklist") }
                    Button(role: .destructive) { showLandfil = true } label: { Label("Landfil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        // Breathing room beneath the "editing" label so the editor doesn't crowd the top bar.
        .padding(.bottom, editing ? 14 : 0)
    }

    /// The hero art: a photo fil shows its image carousel; everything else (including links) shows its
    /// blob. Tapping a link's blob opens the in-app browser.
    @ViewBuilder private var heroArt: some View {
        if note.isImageFil, !note.sortedImageFilImages.isEmpty {
            PhotoStackHero(images: note.sortedImageFilImages.map(\.data), compact: editing, swiping: $carouselSwiping)
        } else if note.isLinkFil {
            linkHero
        } else {
            blob
        }
    }

    /// A link fil's hero: a gradient card with the site's favicon + domain; tap to open the in-app browser.
    private var linkHero: some View {
        Button { openLink() } label: {
            VStack(spacing: 12) {
                linkIcon
                Text(cased(note.sourceDomain ?? "link"))
                    .font(Theme.fredoka(13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.forward").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).padding(14)
            }
            .padding(.horizontal, 26)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
    }

    @ViewBuilder private var linkIcon: some View {
        if let data = note.sourceFaviconData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit().frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: "link").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var blob: some View {
        // The blob pulses to the voice fil's live amplitude while playing (real meter, smoothed a
        // touch since it updates at ~20Hz); otherwise it just wobbles.
        let amp: CGFloat = (isVoice && audio.isPlaying) ? CGFloat(min(1, audio.level * 1.6)) : 0
        return FilPlayerBlob(colors: colors, seed: note.blobShapeSeed, amplitude: amp)
            .frame(height: editing ? 90 : 260)
            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
            .animation(.easeOut(duration: 0.08), value: amp)
    }

    /// The per-fil block that slides on navigation: blob + title/meta/note/to-dos.
    private var filContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            if note.isLinkFil {
                linkURLRow.padding(.horizontal, 26).padding(.bottom, 12)
            }
            heroArt
            Spacer(minLength: 8)
            info
            if !editing { Spacer(minLength: 12) }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                Text(cased(displayTitle))
                    .font(Theme.instrumentSerif(22))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $draft)
                    .font(Theme.fredoka(16, weight: .regular))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(maxHeight: .infinity)
            } else if note.isImageFil {
                // Photo-forward: title + caption shrink to header-style so the carousel dominates.
                photoCaption
                todosBlock
            } else if note.isLinkFil {
                Text(cased(linkTitle))
                    .font(Theme.instrumentSerif(30))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                linkDescription
                todosBlock
            } else {
                Text(cased(displayTitle))
                    .font(Theme.instrumentSerif(30))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                noteBody
                todosBlock
            }
        }
        .frame(maxWidth: .infinity, maxHeight: editing ? .infinity : nil, alignment: .leading)
    }

    /// The link's URL with a copy button. Opening is the hero's job, so the capsule only shows + copies.
    @ViewBuilder private var linkURLRow: some View {
        if let url = note.sourceURL {
            HStack(spacing: 8) {
                // Honest: a lock only for https; a neutral globe for http (no false security claim).
                Image(systemName: url.scheme?.lowercased() == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(url.absoluteString).font(Theme.dmMono(12)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Button { copyLink(url) } label: {
                    Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link")
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14).frame(height: 40)
            .background(.white.opacity(0.12), in: Capsule())
        }
    }

    private func copyLink(_ url: URL) {
        #if canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        withAnimation(.snappy) { linkCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.snappy) { linkCopied = false }
        }
    }

    /// The link page's description (fetched in the background when the fil was made).
    @ViewBuilder private var linkDescription: some View {
        if let d = note.sourceDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            Text(cased(d))
                .font(Theme.fredoka(16, weight: .regular)).opacity(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A photo fil's small header-style title + caption (Fredoka), sitting under the carousel.
    @ViewBuilder private var photoCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cased(displayTitle))
                .font(Theme.instrumentSerif(24))
                .frame(maxWidth: .infinity, alignment: .leading)
            let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Text(cased(body))
                    .font(Theme.fredoka(15, weight: .regular)).opacity(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The fil's own text — selectable (keyword highlights + select→Filament/To-do, tap a highlight to
    /// open its filament). Sized to content; long notes cap at `noteMaxHeight` and scroll with a fade.
    @ViewBuilder private var noteBody: some View {
        let text = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let capped = noteHeight > noteMaxHeight
            ScrollView {
                SelectableTextView(
                    text: cased(text),
                    highlightedKeywords: note.attachments.map(\.keyword),
                    gradientStartHex: note.gradientStartHex,
                    gradientEndHex: note.gradientEndHex,
                    onSelectText: { keyword, _ in openFilament(keyword) },
                    onTapHighlight: { keyword in openFilament(keyword) },
                    onMakeTodo: { addSelectionTodo($0) },
                    height: $noteHeight,
                    textColor: .white
                )
                .frame(height: noteHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!capped)
            .frame(height: noteHeight == 0 ? nil : min(noteHeight, noteMaxHeight))
            .mask(capped
                  ? AnyView(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                  : AnyView(Color.black))
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var todosBlock: some View {
        let todos = note.todoRowItems
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(todos) { item in
                    HStack(spacing: 12) {
                        playerCheckbox(done: item.done)
                        Text(cased(item.text))
                            .font(Theme.fredoka(16, weight: .light))
                            .strikethrough(item.done, color: .white.opacity(0.6))
                            .opacity(item.done ? 0.55 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleTodo(item) }
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder private var transport: some View {
        if isVoice {
            VStack(spacing: 16) {
                scrubber
                HStack(spacing: 44) {
                    Button { advance(-1) } label: {
                        Image(systemName: "backward.fill").font(.system(size: 22))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                    Button { audio.togglePlayback() } label: {
                        Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 58))
                    }
                    Button { advance(1) } label: {
                        Image(systemName: "forward.fill").font(.system(size: 22))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(index == notes.count - 1).opacity(index == notes.count - 1 ? 0.3 : 1)
                }
                .foregroundStyle(.white)
            }
        } else {
            HStack(spacing: 80) {
                Button { advance(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                Button { advance(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 22))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(index == notes.count - 1).opacity(index == notes.count - 1 ? 0.3 : 1)
            }
            .foregroundStyle(.white)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let progress = CGFloat(audio.progress)
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: max(4, w * progress))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { audio.seek(to: Double(max(0, min(1, $0.location.x / w)))) }
                    )
            }
            .frame(height: 5)

            HStack {
                Text(timeString(audio.currentTime)).font(Theme.fredoka(11, weight: .regular)).opacity(0.6)
                Spacer()
                Text(timeString(audio.duration)).font(Theme.fredoka(11, weight: .regular)).opacity(0.6)
            }
        }
    }

    // MARK: - To-dos

    /// A bordered 22pt chip mirroring the app's `TodoStatusCircle`, tinted for the dark player.
    private func playerCheckbox(done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(done ? Color.white.opacity(0.9) : Color.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(done ? 0 : 0.5), lineWidth: 1.5)
            }
            .overlay {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
            .frame(width: 22, height: 22)
    }

    private func toggleTodo(_ item: FilTodoItem) {
        note.normalizeCompletedTodos()
        guard note.completedTodos.indices.contains(item.index) else { return }
        withAnimation(.snappy) { note.completedTodos[item.index].toggle() }
        try? context.save()
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    // MARK: - Text

    private var displayTitle: String {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? note.displayBadgeText : t
    }

    private var typeLabel: String {
        if note.isLinkFil { return "link" }
        if note.isImageFil { return "photo" }
        if isVoice { return "voice" }
        return "note"
    }

    private var linkTitle: String {
        let t = note.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (note.sourceDomain ?? "Link") : title
    }

    private func openLink() {
        guard let url = note.sourceURL else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        browserLink = BrowserLink(url: url)
    }

    /// Backfill a link's description if it's missing (made before descriptions existed, or first fetch failed).
    private func backfillLinkDescription() async {
        guard note.isLinkFil, (note.sourceDescription?.isEmpty ?? true), let url = note.sourceURL else { return }
        if let description = await LinkFil.fetchDescription(for: url) {
            note.sourceDescription = description
            try? context.save()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A tapped/selected keyword, wrapped so it can drive `.sheet(item:)`.
private struct FilamentKeyword: Identifiable {
    let id = UUID()
    let keyword: String
}

/// A link fil's URL, wrapped so it can drive the in-app browser `.sheet(item:)`.
private struct BrowserLink: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Background

/// The fil gradient scaled up, heavily blurred and darkened — the soft wash behind the player. As a
/// sheet's `presentationBackground` it's static (no bloom, since the sheet slides rather than
/// opacity-crossfading a blurred layer).
private struct BlurredFilBackground: View {
    let colors: [Color]
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .scaleEffect(1.6)
            .blur(radius: 90)
            .overlay(Color.black.opacity(0.34))
            .ignoresSafeArea()
    }
}

// MARK: - Photo hero (native responsive carousel)

/// A photo fil's images as a native horizontal carousel: each card is sized to its true aspect (box-fit
/// within maxCardW × maxCardH, so verticals grow tall), peeking neighbors via content margins. Scrolls
/// with real momentum/snapping. A single photo is centered (no scroll). Images are decoded once so the
/// band-height change during scroll doesn't re-decode them (which flashed gray). While the carousel is
/// scrolling it flips `swiping` so the player's fil-nav swipe stands down (the band owns its own swipe).
private struct PhotoStackHero: View {
    let images: [Data]
    var compact: Bool
    @Binding var swiping: Bool

    private let aspects: [CGFloat]   // width/height per image, from its pixel dimensions
    private let decoded: [Image?]    // decoded once (avoids per-render decode → no gray flash)

    @State private var scrollID: Int? = 0

    private let maxCardW: CGFloat = 340   // wide landscapes cap here
    private let maxCardH: CGFloat = 560   // portraits get to grow tall
    private let radius: CGFloat = 24
    private var hasMany: Bool { images.count > 1 }
    private var current: Int { scrollID ?? 0 }

    init(images: [Data], compact: Bool, swiping: Binding<Bool>) {
        self.images = images
        self.compact = compact
        self._swiping = swiping
        self.aspects = images.map(Self.aspectRatio)
        self.decoded = images.map { Image(data: $0) }
    }

    /// Cheap pixel-dimension read (no full decode) → width / height aspect ratio.
    private static func aspectRatio(_ data: Data) -> CGFloat {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, h > 0
        else { return 1 }
        return CGFloat(w / h)
    }

    /// Box-fit within maxCardW × maxCardH, preserving aspect: portraits fill the height and stay narrow;
    /// landscapes fill the width and are shorter. Verticals therefore read much larger than landscapes.
    private func cardSize(_ i: Int) -> CGSize {
        let ar = aspects.indices.contains(i) ? aspects[i] : 1
        var h = maxCardH, w = maxCardH * ar
        if w > maxCardW { w = maxCardW; h = maxCardW / ar }
        return CGSize(width: w, height: h)
    }

    var body: some View {
        if compact {
            imageView(current)
                .scaledToFill()
                .frame(height: 90).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if images.count <= 1 {
            // A single photo is simply centered — no carousel.
            let s = cardSize(0)
            imageView(0)
                .scaledToFit()
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 14) {
                carousel
                dots
            }
        }
    }

    @ViewBuilder private func imageView(_ i: Int) -> some View {
        if decoded.indices.contains(i), let image = decoded[i] {
            image.resizable()
        } else {
            Color.white.opacity(0.1)
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(images.indices, id: \.self) { i in
                    let s = cardSize(i)
                    imageView(i)
                        .scaledToFit()
                        .frame(width: s.width, height: s.height)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 44, for: .scrollContent)   // peek + lets ends center
        .scrollPosition(id: $scrollID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(height: cardSize(current).height)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: current)
        .onScrollPhaseChange { _, phase in swiping = (phase != .idle) }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(images.indices, id: \.self) { i in
                Circle().fill(.white.opacity(i == current ? 0.95 : 0.35)).frame(width: 6, height: 6)
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { scrollID = i } }
            }
        }
    }
}

// MARK: - The moving fil blob

/// The gooey animated blob (same look as fil creation) tinted to this fil and seeded so each fil
/// wobbles differently; `amplitude` (0…1) drives a gentle pulse during voice playback.
private struct FilPlayerBlob: View {
    let colors: [Color]
    var seed: Double = 0
    var amplitude: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 0.9 + CGFloat(seed) * 12
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                BlobShape(points: 5, amplitude: max(2, side * 0.03), time: time)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1 + amplitude * 0.06)
            }
        }
    }
}
