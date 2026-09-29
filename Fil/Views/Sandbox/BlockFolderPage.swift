#if DEBUG
import SwiftUI
import PhotosUI
import SwiftData

/// A folder as one vertical page of blocks, 2026-09-28.
///
/// **The axes.** Horizontal moves between folders; vertical scrolls this page. Nothing pages
/// vertically any more, which is what frees that axis for a drag — long-press to reorder now
/// contests only the scroll, and iOS already arbitrates that pair. Under the crossed model the same
/// gesture would have been the third meaning on one axis.
///
/// **One face on the page.** Every word a user wrote or that names their content is Newsreader:
/// notes, to-dos, link titles, captions, the running header. Helvetica survives only in the
/// composer and the chrome, which is where a UI face belongs and a reading face does not.
///
/// **Blocks, not cards.** Every thought is a block in one document rather than a screen of its own,
/// so a folder is read by scrolling rather than by paging, and its order is something you arrange.
/// That is the Notion/Craft claim, and it is a different one from the feed's: the feed sorted by
/// recency because people find their own things by recognition, where blocks say the arrangement
/// itself carries meaning.
/// A folder's two cards: its cover, and one horizontal step across into the nest.
///
/// **The axes, by depth.** Down moves between folders while you are on a cover. Across takes you
/// into the nest. Inside the nest, down belongs to the content and folder paging is off — set by
/// the parent, which is why `card` is a binding rather than local state.
struct NestFolderPage: View {
    let folder: Folder
    @Binding var card: Int

    @State private var pick: PhotosPickerItem?
    @State private var coverImage: Data?

    private var palette: Palette { Palette(folder) }

    var body: some View {
        TabView(selection: $card) {
            cover.tag(0)
            Nest(folder: folder, palette: palette).tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background {
            // The folder's own photograph if it has one — blurred, and veiled by however much its
            // own brightness requires so white on it clears 7:1. Otherwise the gradient.
            Group {
                if let coverImage {
                    FolderCoverGround(data: coverImage, id: folder.id)
                } else {
                    LinearGradient(colors: [palette.groundFrom, palette.groundTo],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image("PaperNoise")
                                .resizable(resizingMode: .tile)
                                .blendMode(.multiply)
                                .opacity(0.07)
                                .allowsHitTesting(false)
                        }
                }
            }
            .ignoresSafeArea()
        }
        .task(id: folder.id) { coverImage = FolderCoverStore.load(folder.id) }
        .task(id: pick) {
            guard let pick,
                  let data = try? await pick.loadTransferable(type: Data.self) else { return }
            FolderCoverStore.save(data, for: folder.id)
            coverImage = FolderCoverStore.load(folder.id)
            self.pick = nil
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(folder.name)
                .font(StudyType.serif(46, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
            // The only control on a cover.
            PhotosPicker(selection: $pick, matching: .images) {
                Label(coverImage == nil ? "Add a cover" : "Change cover",
                      systemImage: "photo.on.rectangle.angled")
                    .font(StudyType.sans(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))
            }
            .padding(.top, 24)

            if coverImage != nil {
                Button("Remove") {
                    FolderCoverStore.clear(folder.id)
                    coverImage = nil
                }
                .font(Theme.dmMono(10))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 22)
        .padding(.trailing, 54)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The nest: one vertical page of blocks.
private struct Nest: View {
    let folder: Folder
    let palette: Palette

    @State private var order: [UUID] = []

    private var blocks: [Note] {
        let byID = Dictionary(folder.notes.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = order.compactMap { byID[$0] }
        // Anything created since the order was taken falls in at the END, oldest first — a new
        // thought belongs after the last one, the way a sent message does.
        let missing = folder.notes.filter { !order.contains($0.uuid) }
            .sorted { $0.timestamp < $1.timestamp }
        return ordered + missing
    }

    /// "TODAY 5:04 PM", "YESTERDAY 9:12 AM", "3 SEPTEMBER 11:40 AM" — day and time together, as
    /// Messages sets it, so the separator says how long a gap you just crossed rather than only
    /// what date it is.
    private static func stamp(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        let day: String
        if cal.isDateInToday(date) { day = "TODAY" }
        else if cal.isDateInYesterday(date) { day = "YESTERDAY" }
        else {
            let d = DateFormatter()
            d.dateFormat = "d MMMM"
            day = d.string(from: date).uppercased()
        }
        return "\(day)  \(time.string(from: date))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // No running header. It named the folder, and so does the composer at the bottom —
            // "add to CommunityHealth" — permanently and without costing a row.
            Color.clear.frame(height: 62)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if blocks.isEmpty {
                        Text("Nothing filed here yet")
                            .font(StudyType.serif(15))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    } else {
                        // No rules between them any more. A bubble already says where a thought
                        // starts and stops, so the line was saying it twice — and 14 points is
                        // the gap iMessage leaves between separate messages.
                        // A separator above the first message of each day, centred — the same
                        // place Messages puts it. Swipe-to-reveal came out: it fought the vertical
                        // scroll for the same touch, and a gesture that competes with scrolling
                        // loses every time on a surface whose main job is scrolling.
                        ForEach(Array(blocks.enumerated()), id: \.element.uuid) { i, note in
                            if i == 0 || !Calendar.current.isDate(note.timestamp,
                                                                  inSameDayAs: blocks[i - 1].timestamp) {
                                Text(Self.stamp(note.timestamp))
                                    .font(StudyType.sans(11))
                                    .tracking(0.6)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, i == 0 ? 0 : 16)
                                    .padding(.bottom, 16)
                            }
                            Block(note: note, palette: palette)
                                .padding(.bottom, 14)
                        }
                    }
                }
                // The bar's own height plus a margin. `.safeAreaInset` on the pager cannot do
                // this for us: `.ignoresSafeArea()` is applied to that scroll before the inset is
                // attached, so the inset sits outside a view that has already opted out.
                .padding(.bottom, BottomBar.clearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // Opens on the newest thought, and stays there as thoughts are added — the thread
            // behaviour, not a list's. `.defaultScrollAnchor` rather than a `ScrollViewReader`
            // because it sets the resting position instead of animating to one after layout,
            // so there is no visible jump on entering the nest.
            .defaultScrollAnchor(.bottom)
        }
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: folder.id) {
            if order.isEmpty {
                order = folder.notes.sorted { $0.timestamp < $1.timestamp }.map(\.uuid)
            }
        }
    }
}

/// One thought as a block./// One thought as a block. Each kind keeps the form it earned; what changed is that it now sits in
/// a document rather than on a screen of its own.
private struct Block: View {
    let note: Note
    let palette: Palette

    @State private var preview: PhotoPreview?

    var body: some View {
        Group {
            if !note.todoRowItems.isEmpty {
                // The checklist and nothing else. A to-do fil's own transcript is not shown here
                // — worth knowing what that costs: "LGL", "before the 30th", whatever context you
                // typed alongside the items, has no representation on this page.
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(note.todoRowItems) { item in
                        HStack(alignment: .top, spacing: 11) {
                            // No frame of our own: TodoStatusCircle sizes itself to 22 and its
                            // border is drawn at that edge, so a smaller frame clips the stroke
                            // into the flat side you saw.
                            TodoStatusCircle(isCompleted: item.done, onColor: true)
                            Text(item.text)
                                .font(StudyType.serif(16))
                                .strikethrough(item.done)
                                .foregroundStyle(.white.opacity(item.done ? 0.45 : 0.9))
                        }
                    }
                }
            } else if note.isImageFil,
                      let data = note.sortedImageFilImages.first?.data ?? note.imageData,
                      let image = UIImage(data: data) {
                VStack(alignment: .leading, spacing: 10) {
                    // A squircle, filled and cropped square rather than fitted. Inside a bubble a
                    // fitted photograph makes every bubble a different width, and a column of
                    // bubbles that each size to their picture stops reading as a conversation.
                    // Tapping opens the real thing uncropped in the system previewer.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .onTapGesture { preview = PhotoPreview(note: note) }
                    caption
                }
            } else if note.isLinkFil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 11) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.9)).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.sourceTitle ?? note.sourceURLString ?? "")
                                .font(StudyType.serif(15, weight: .semibold))
                                .foregroundStyle(.white)
                            if let host = note.sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") {
                                Text(host).font(Theme.dmMono(10.5)).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    // No border of its own any more: the bubble is the border, and two rounded
                    // outlines one inside the other read as a mistake.
                }
            } else if !note.audioFilePath.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CompactWaveformView(duration: note.duration, color: .white.opacity(0.85))
                        .scaleEffect(x: 1.8, y: 1.6, anchor: .leading)
                        .frame(height: 30)
                    caption
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // One voice: no heading weight, no first-line emphasis. A thought is what was
                    // written, at one size, and the rule beneath it is what says where it ends.
                    // 16 rather than the body's old 14.5 because Newsreader sets smaller than
                    // Helvetica at the same point size.
                    Text(note.transcript)
                        .font(StudyType.serif(16))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineSpacing(4)
                }
            }
        }
        // A bubble, trailing, the way your own messages sit. Transparent with a hairline rather
        // than filled: on a photograph ground a filled bubble becomes a second surface and the
        // cover stops showing through, which is the thing the cover was for.
        //
        // Photographs get no bubble, which is what iMessage does too — a picture is already an
        // object and a border around it reads as a frame nobody asked for.
        .padding(.vertical, 12)
        .padding(.leading, 16)
        // Room for the tail on the trailing side, so the text never runs into it.
        .padding(.trailing, 22)
        .background {
            ChatBubble().stroke(.white.opacity(0.4), lineWidth: 1)
        }
        // .trailing, not .leading. The bubble hugs its content, so a short one sat at the LEFT
        // of this 300-wide box — and the box was what got right-aligned, not the bubble.
        .frame(maxWidth: 300, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fullScreenCover(item: $preview) { target in
            NativePhotoViewer(urls: target.urls, start: 0) { preview = nil }
                .ignoresSafeArea()
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.titleLine)
                .font(StudyType.serif(15)).italic()
                .foregroundStyle(.white.opacity(0.75))
            if !note.bodyAfterTitle.isEmpty {
                Text(note.bodyAfterTitle)
                    .font(StudyType.serif(15)).italic()
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }
}

/// A chat bubble: a rounded rect with a tail on the bottom trailing corner.
///
/// Drawn rather than composed from a rounded rect plus a shape, because this is stroked — two
/// overlapping outlines would show their seam where the tail meets the body, and one path has no
/// seam to show.
struct ChatBubble: Shape {
    var radius: CGFloat = 20
    /// How far the tail reaches past the body, and how tall its curve is.
    var tail: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let right = rect.maxX - tail
        let bottom = rect.maxY

        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: right - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.minY + r),
                       control: CGPoint(x: right, y: rect.minY))
        // Down the trailing edge, then out into the tail and back under itself — the hook that
        // makes it read as spoken rather than as a box.
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: right + tail, y: bottom),
                       control: CGPoint(x: right, y: bottom - r / 2.4))
        p.addQuadCurve(to: CGPoint(x: right - tail * 0.7, y: bottom),
                       control: CGPoint(x: right + tail * 0.2, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: bottom - r),
                       control: CGPoint(x: rect.minX, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Where you are in the folders, now that the bottom bar has stopped being navigation.
struct FolderDots: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == index ? 0.95 : 0.38))
                    .frame(width: 6, height: 6)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4)
        .animation(.snappy, value: index)
    }
}

/// The bar, as a set of modes rather than one control.
///
/// **Navigate** is the resting state and costs no height — you are already navigating, so the bar
/// stays out of the way. The other three each expand it, because each is a place you type.
///
/// Text and Photo write real `Note`s into the real folder; To-Do writes a single-item one. Voice,
/// Chat and Search are shape only and say so on their own line rather than offering a dead control.
/// The real composer is `ComposerBar`, which already carries the field, the to-do pills, photo and
/// checklist controls, a send/mic button and a `contextLabel` reading "add to {folder}"; search is
/// `CanvasHome`'s existing query mode, which `ComposerBar` also already models with `searchMode`.
struct BottomBar: View {
    let folderName: String?
    let folder: Folder?
    /// How much of the screen the keyboard is covering right now, 0 when it is down.
    let keyboard: CGFloat
    /// Only inside a nest. Paging folders is navigation and carries no composer — a bar on that
    /// page can only name the folder it thinks is centred, which is a weaker claim than "the
    /// folder you opened", and it was already getting that wrong.
    let visible: Bool
    @Binding var mode: Mode

    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var pick: PhotosPickerItem?
    @FocusState private var writing: Bool

    /// Seven states, but never seven buttons. At rest the row offers two words; choosing one
    /// replaces the row with that group's members, so the most the bar ever shows is four.
    enum Mode: String, CaseIterable, Identifiable {
        case navigate, text, photo, todo, voice, chat, search
        var id: String { rawValue }

        var label: String {
            switch self {
            case .navigate: "Navigate"
            case .todo:     "To-Do"
            default:        rawValue.capitalized
            }
        }

        /// Which row this mode belongs to. `navigate` belongs to neither: it is the state of
        /// having nothing selected, so the row falls back to the two group names.
        var group: Group? {
            switch self {
            case .navigate:                     nil
            case .text, .photo, .todo, .voice:  .add
            case .chat, .search:                .ask
            }
        }

        /// What the field says in this mode.
        func placeholder(_ folder: String?) -> String {
            switch self {
            case .navigate: ""
            case .text:     folder.map { "add to \($0)" } ?? "a thought"
            case .photo:    "choose a photograph"
            case .todo:     "a thing to do"
            case .voice:    "hold to record"
            case .chat:     folder.map { "ask about \($0)" } ?? "ask about your thoughts"
            case .search:   "search your thoughts"
            }
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case add, ask
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var members: [Mode] {
            switch self {
            case .add: [.text, .photo, .todo, .voice]
            case .ask: [.chat, .search]
            }
        }

        /// What choosing the group lands on. Text and Chat are the ones you reach for without
        /// thinking, so they are what the group opens to.
        var entry: Mode { self == .add ? .text : .chat }
    }

    /// One spring for the whole movement: the bar rising and the page rising are the same
    /// gesture's consequence, so they cannot be tuned apart. Snappy rather than the Island's own
    /// slower settle, because this is tapped constantly. A spring also retargets when interrupted,
    /// so the keyboard's height arriving a beat late redirects the movement instead of starting a
    /// second one.
    static let morph: Animation = .spring(response: 0.34, dampingFraction: 0.86)

    /// The field line's height. There is no writing room any more: the field rides on top of the
    /// keyboard the way Messages does, so this plus the keyboard is the whole translation.
    static let field: CGFloat = 56

    /// Room plus keyboard: one number, so the page's translation and the bar's have a single
    /// source and a single animation. Two values here would be two movements — see Pattern 8 in
    /// `swiftui-animation-performance`.
    static func lift(keyboard: CGFloat) -> CGFloat { field + keyboard }

    /// What the scroll above has to leave clear: the options row plus its padding, with a margin.
    /// The page does not reflow when the bar opens — it translates — so this is the resting size.
    static let clearance: CGFloat = 96

    /// Far enough below the screen that the whole bar is gone. Offsetting it away rather than
    /// removing it with an `if`: an insertion cross-fades on top of the travel, and the swipe
    /// between cover and nest is exactly when that would show.
    static let hidden: CGFloat = 170

    /// How far the black is drawn past the bar's own bottom edge. The keyboard's top corners are
    /// rounded and it lives in a window above the app, so this slab is occluded everywhere except
    /// in those two corners — which is the only place it was needed.
    static let underlap: CGFloat = 90

    private var open: Bool { mode != .navigate }

    /// The words on the row right now: the two group names at rest, that group's members once one
    /// is chosen. Never both.
    private var row: [(id: String, label: String, lit: Bool, tap: () -> Void)] {
        if let group = mode.group {
            group.members.map { m in
                (m.id, m.label, mode == m, { mode = (mode == m) ? .navigate : m })
            }
        } else {
            Group.allCases.map { g in
                (g.id, g.label, false, { mode = g.entry })
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The row never moves within the bar. Everything that opens does so BENEATH it, so the
            // words are in the same place whether the bar is shut or open.
            HStack(spacing: 0) {
                ForEach(row, id: \.id) { item in
                    Button(action: item.tap) {
                        Text(item.label)
                            // ONE face for every state. Selection used to swap HelveticaNeue for
                            // HelveticaNeue-Medium, and a different face resource is a different
                            // view to SwiftUI — so mid-translation it cross-faded the old row
                            // against the new one at two heights. Opacity carries selection
                            // instead, which is a property rather than an identity.
                            .font(StudyType.sans(14))
                            .foregroundStyle(.white.opacity(item.lit ? 1 : 0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            // The row's WORDS change when a group opens, which is a view swap, and a swap
            // cross-fades on top of the bar's travel. Swapping instantly keeps the movement one
            // thing — the same fix the field line below needs.
            .id(mode.group?.id ?? "groups")
            .animation(nil, value: mode)

            // Always rendered at full height, in every mode. The line is never resized and never
            // inserted — it is simply below the screen when shut.
            field
                .frame(height: Self.field)
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background { Color.black.padding(.bottom, -Self.underlap) }
        // Shut, the field line hangs below the screen. Open, the whole bar is pushed up by the
        // keyboard so the line sits ON TOP of it. The page moves by the sum of the two.
        .offset(y: visible ? (open ? -keyboard : Self.field) : Self.hidden)
        // Focus follows the mode in the same transaction that moves the bar, so the keyboard comes
        // up with the movement rather than after it. Photo and Voice want no keyboard.
        .onChange(of: mode) { _, new in
            writing = [.text, .todo, .chat, .search].contains(new)
        }
        .task(id: pick) {
            guard let pick,
                  let data = try? await pick.loadTransferable(type: Data.self) else { return }
            let note = Note(timestamp: .now, imageData: data)
            note.folder = folder
            context.insert(note)
            try? context.save()
            self.pick = nil
        }
    }

    /// Writes a real `Note` into the real folder — the study reads the live store, so a thought
    /// sent here is a thought you have. The field clears and keeps focus: thoughts arrive in
    /// bursts, and closing the bar after each one would cost a tap per thought.
    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        let note: Note
        switch mode {
        case .text:  note = Note(transcript: text, timestamp: .now)
        case .todo:  note = Note(timestamp: .now, todos: [text])
        default:     return
        }
        note.folder = folder
        context.insert(note)
        try? context.save()
        draft = ""
    }

    /// One line, on the keyboard. Photo hands off to the picker and Voice is not built yet, so
    /// each mode says what it is rather than pretending to a field it does not have.
    private var field: some View {
        HStack(spacing: 14) {
            switch mode {
            case .photo:
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(mode.placeholder(folderName), systemImage: "photo.on.rectangle")
                        .font(StudyType.sans(17))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            case .voice:
                // Not built. Says so rather than offering a control that does nothing.
                Image(systemName: "mic.fill").font(.system(size: 18))
                Text("recording is not wired up yet")
                    .font(StudyType.sans(15))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            default:
                TextField("", text: $draft, prompt:
                            Text(mode.placeholder(folderName)).foregroundStyle(.white.opacity(0.4)),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(StudyType.sans(17))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($writing)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(draft.trimmed.isEmpty ? 0.35 : 0.9))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmed.isEmpty || ![.text, .todo].contains(mode))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 20)
        // The mode's own controls swap as the bar moves. Without a stable identity the same
        // cross-fade happens here, one layer down.
        .id(mode)
        .animation(nil, value: mode)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
