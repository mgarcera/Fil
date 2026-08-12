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
    @State private var scrollY: CGFloat = 0                 // reading-scroll offset; drives shrink/parallax/dim
    @State private var canScrollDown = false                // more text below the fold → show the floating arrow
    @State private var scrollPosition = ScrollPosition()    // lets the arrow scroll the reader to the bottom
    @State private var showPhotoDetails = false             // photo fil: the ⌄ flips to a title/caption/to-do section
    @FocusState private var editorFocused: Bool

    private let heroFull: CGFloat = 260
    private let heroCollapsed: CGFloat = 90
    /// Gap between the blob and the text at rest.
    private let heroToTextGap: CGFloat = 40
    /// Scroll distance over which the backdrop blob fully shrinks from `heroFull` to `heroCollapsed`.
    private let heroCollapseDistance: CGFloat = 240

    init(notes: [Note], startID: UUID, onClose: @escaping () -> Void = {}) {
        self.notes = notes
        self.startID = startID
        self.onClose = onClose
        _index = State(initialValue: max(0, notes.firstIndex { $0.uuid == startID } ?? 0))
    }

    private var note: Note { notes[min(index, notes.count - 1)] }
    private var colors: [Color] { [Color(hex: note.gradientStartHex), Color(hex: note.gradientEndHex)] }
    private var isVoice: Bool { !note.audioFilePath.isEmpty }
    /// Note/voice fils use the gooey blob as a scrolled-over backdrop; photos/links keep their media hero.
    private var heroCentersBlob: Bool { !note.isLinkFil && !note.isImageFil }
    /// Scroll progress 0…1 over `heroCollapseDistance` — drives the backdrop blob's shrink, drift, and dim.
    private var heroProgress: CGFloat { min(1, max(0, scrollY / heroCollapseDistance)) }
    /// The blob's height: compact while editing; full at rest; shrinking to `heroCollapsed` as you scroll.
    private var heroVisualHeight: CGFloat {
        if editing { return heroCollapsed }
        guard heroCentersBlob else { return heroFull }
        return heroFull - heroProgress * (heroFull - heroCollapsed)
    }

    private func cased(_ s: String) -> String { prefersLowercase ? s.lowercased() : s }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // The per-fil content slides on button navigation (no swipe).
            ZStack {
                filContent
                    .id(note.uuid)
                    // Slides in the nav direction AND scales up as it lands (hero pop), slides out plainly.
                    .transition(.asymmetric(
                        insertion: .move(edge: navForward ? .trailing : .leading)
                            .combined(with: .opacity).combined(with: .scale(scale: 0.92)),
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
        scrollY = 0               // the incoming fil opens with a full, undimmed backdrop blob
        canScrollDown = false     // re-evaluated once the new fil reports its scroll geometry
        showPhotoDetails = false  // the incoming photo starts on the image, not its details
        navForward = delta > 0
        // Unified deck timing: hero slide + scale pop, header, and transport all ride this snappy.
        withAnimation(.snappy(duration: 0.2)) {
            index = next
        }
        Haptics.navigate()
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
        Haptics.destructive()
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
            Group {
                if editing {
                    Text("editing")
                } else {
                    Text("\(cased(typeLabel))  ·  \(index + 1) / \(notes.count)")
                        .id(index)   // new identity per fil so it scale-pops to the new value on nav
                        .transition(.scale.combined(with: .opacity))
                }
            }
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

    /// A link fil's hero: a compact, centered gradient card with the site's favicon + domain; tap to open
    /// the in-app browser. Sized to roughly the blob's footprint (not full-width) so its soft shadow has
    /// margin and isn't clipped by the scroll bounds — matching the blob's shadow.
    private var linkHero: some View {
        Button { openLink() } label: {
            VStack(spacing: 12) {
                linkIcon
                Text(cased(note.sourceDomain ?? "link"))
                    .font(Theme.fredoka(13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 240, height: 210)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.forward").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).padding(14)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
        .frame(maxWidth: .infinity)   // center the compact card
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
        // Freeze the wobble (and its every-frame blur re-render) once the blob is fully collapsed and
        // dimmed away — imperceptible there, and this screen keeps the idle timer disabled, so it's a
        // real battery win. It resumes as soon as you scroll back up.
        return FilPlayerBlob(colors: colors, seed: note.blobShapeSeed, amplitude: amp, paused: heroProgress >= 1)
            .frame(height: heroVisualHeight)
            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
            .animation(.easeOut(duration: 0.08), value: amp)
    }

    /// The per-fil block that slides on navigation: blob + title/meta/note/to-dos. Reading wraps the
    /// whole thing in one scroll so a long note scrolls the hero up off the top; editing fills instead.
    @ViewBuilder private var filContent: some View {
        if editing {
            editingContent
        } else if note.isImageFil, !note.sortedImageFilImages.isEmpty {
            if showPhotoDetails { photoDetailsSection } else { photoContent }
        } else {
            readingContent
        }
    }

    /// Photo fils: the image fills the player and is **static** (no vertical scroll — that was the lag).
    /// Title/caption/to-dos live in a separate `photoDetailsSection`, reached via the transport's ⌄.
    private var photoContent: some View {
        PhotoStackHero(images: note.sortedImageFilImages.map(\.data), compact: false, swiping: $carouselSwiping)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The photo's "back side": title, caption, and to-dos — a separate section from the image. Opened and
    /// dismissed by the transport's center ⓘ/✕ (which stays under the thumb — no top chevron). Scrolls if
    /// long (text only, so no image-decode lag).
    private var photoDetailsSection: some View {
        let caption = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(cased(displayTitle)).font(Theme.instrumentSerif(30))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !caption.isEmpty {
                    Text(cased(caption)).font(Theme.fredoka(16, weight: .regular)).opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                todosBlock
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// Editing: the text editor fills the space below a compact hero (no scroll — the editor scrolls).
    private var editingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            heroArt
            Spacer(minLength: 8)
            info
        }
    }

    /// Reading: a "now playing" composition (Spotify / Apple Music). The blob (note/voice) is a backdrop
    /// in the upper third; the text scrolls up **over** it. As you scroll, the blob shrinks, drifts up
    /// slower than the text (parallax), and dims/blurs so the text passing over it stays readable. Short
    /// fils don't scroll, so the blob just sits above the text. Photos/links keep their inline hero.
    private var readingContent: some View {
        GeometryReader { geo in
            let blobTop = max(24, geo.size.height * 0.12)
            let maxDrift = max(0, blobTop - 8)
            ZStack(alignment: .top) {
                if heroCentersBlob {
                    heroArt   // blob, sized by heroVisualHeight (shrinks with scroll)
                        .frame(maxWidth: .infinity)
                        .padding(.top, blobTop)
                        .offset(y: -min(scrollY * 0.3, maxDrift))          // parallax: drifts up slowly
                        .opacity(1 - heroProgress * 0.55)                   // dim as text covers it
                        .blur(radius: heroProgress * 6)
                        .allowsHitTesting(false)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        if heroCentersBlob {
                            // Note/voice: reserve the blob's slot; the backdrop blob (above) shows through
                            // and the text rises over it as you scroll.
                            Color.clear.frame(height: blobTop + heroFull + heroToTextGap - 8)
                        } else if note.isLinkFil {
                            // Link: aligned to the note — the hero region begins at the same upper-third
                            // anchor with the same gap below, so nav between note↔link doesn't jump. The
                            // card stays crisp inline (no scroll-over/dim); the URL capsule rides above it.
                            Color.clear.frame(height: blobTop)
                            linkURLRow.padding(.horizontal, 26).padding(.bottom, 12)
                            heroArt.frame(maxWidth: .infinity)
                            Spacer().frame(height: heroToTextGap)
                        } else {
                            // Photo: media-forward — the carousel leads, unchanged.
                            heroArt.frame(maxWidth: .infinity)
                            Spacer().frame(height: heroToTextGap)
                        }
                        info
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ScrollSnapshot.self) { g in
                    ScrollSnapshot(offset: g.contentOffset.y,
                                   canScrollDown: g.contentSize.height - g.containerSize.height - g.contentOffset.y > 24)
                } action: { _, snap in
                    scrollY = snap.offset
                    withAnimation(.easeOut(duration: 0.2)) { canScrollDown = snap.canScrollDown }
                }
            }
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
    /// open its filament). Self-sizing (see `SelectableTextView.sizeThatFits`), so it lays out at its
    /// true height on the first frame — no reflow when swiping between fils. The whole reading pane
    /// scrolls (see `readingContent`), so a long note simply carries the hero up as you read.
    @ViewBuilder private var noteBody: some View {
        let text = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            SelectableTextView(
                text: cased(text),
                highlightedKeywords: note.attachments.map(\.keyword),
                gradientStartHex: note.gradientStartHex,
                gradientEndHex: note.gradientEndHex,
                onSelectText: { keyword, _ in openFilament(keyword) },
                onTapHighlight: { keyword in openFilament(keyword) },
                onMakeTodo: { addSelectionTodo($0) },
                textColor: .white
            )
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: audio.isPlaying)   // subtle scale pop on toggle
                    }
                    Button { advance(1) } label: {
                        Image(systemName: "forward.fill").font(.system(size: 22))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(index == notes.count - 1).opacity(index == notes.count - 1 ? 0.3 : 1)
                }
                .foregroundStyle(.white)
            }
            .transition(.scale.combined(with: .opacity))   // scale-pop the voice controls in on a type-swap
        } else {
            HStack(spacing: 44) {
                Button { advance(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                transportCenterButton
                Button { advance(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 22))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(index == notes.count - 1).opacity(index == notes.count - 1 ? 0.3 : 1)
            }
            .foregroundStyle(.white)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// The transport's center button — styled like the audio play button (filled circle), always in the
    /// same spot. Photos: an ⓘ that toggles the details section (stays put, becomes ✕ in details — no top
    /// chevron). Notes/links: a ⌄ that glides to the end, fading in place only when there's more below.
    @ViewBuilder private var transportCenterButton: some View {
        if note.isImageFil {
            Button { withAnimation(.snappy(duration: 0.3)) { showPhotoDetails.toggle() } } label: {
                Image(systemName: showPhotoDetails ? "xmark.circle.fill" : "info.circle.fill")
                    .font(.system(size: 50))
                    .contentTransition(.symbolEffect(.replace))   // swaps in place, no drift
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPhotoDetails ? "Back to photo" : "Show details")
        } else {
            // Fade the button in its own spot (opacity, not an insertion transition) so it doesn't drift
            // in at an angle; keep it in the layout at all times so ◀ ▶ spacing never shifts.
            Button { withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) } } label: {
                Image(systemName: "chevron.down.circle.fill").font(.system(size: 50)).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(canScrollDown ? 1 : 0)
            .allowsHitTesting(canScrollDown)
            .accessibilityHidden(!canScrollDown)
            .accessibilityLabel("Scroll to end")
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
        Haptics.toggle()
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
        Haptics.navigate()
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

/// The reading scroll's offset + whether more text sits below the fold, tracked together for the
/// backdrop collapse and the floating scroll-down arrow.
private struct ScrollSnapshot: Equatable {
    var offset: CGFloat
    var canScrollDown: Bool
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
        self.decoded = images.map { Self.downsampled($0) }
    }

    /// Decode to roughly display size instead of full resolution — full-res bitmaps composited live
    /// (over the blurred wash) were the photo player's scroll/swipe lag. Crisp on any card at 3×.
    private static let maxDecodePixel: CGFloat = 1680
    private static func downsampled(_ data: Data) -> Image? {
        #if canImport(UIKit)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDecodePixel
        ]
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
            return Image(uiImage: UIImage(cgImage: cg))
        }
        return Image(data: data)
        #else
        return Image(data: data)
        #endif
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
    /// Stops the per-frame wobble/blur redraws when the blob is collapsed out of sight (battery).
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(paused: paused)) { timeline in
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
