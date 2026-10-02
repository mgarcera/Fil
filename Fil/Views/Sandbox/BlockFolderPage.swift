#if DEBUG
import SwiftUI
import PhotosUI
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A folder's own ground: its photograph if it has one — blurred, and veiled by however much its
/// own brightness requires so white on it clears 7:1 — otherwise its palette gradient.
/// Shared by the cover and the nest so the two read as one place.
struct FolderGround: View {
    let folder: Folder
    let coverImage: Data?

    var body: some View {
        let palette = Palette(folder)
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
}

/// One folder's page in the vertical pager: the cover, and nothing else.
///
/// The nest is no longer a card beside it. It was — a `TabView(.page)` per folder, which put a
/// `UIPageViewController` between the SwiftUI pager and the nest's own scroll view. Three
/// scrolling containers across two frameworks: the page controller turned pages whether or not
/// the `card` binding accepted the write, `folderIndex` drifted on lazy neighbours' `onAppear`,
/// and safe area and keyboard had to survive three boundaries to reach the composer. Every
/// composer bug on 2026-09-29 was one of those. Now a folder OPENS: the nest is pushed as its
/// own screen and gets one plain container, the way the shipped home's composer has.
struct CoverPage: View {
    let folder: Folder
    let open: () -> Void

    @State private var pick: PhotosPickerItem?
    @State private var coverImage: Data?
    @State private var choosing = false
    @Environment(\.homeInset) private var homeInset

    var body: some View {
        editorial
            .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The cover control, lower right: an image glyph in a hairline circle, line art like the
        // capsule it replaced rather than the glass the back button wears — a cover is an image
        // choice, not navigation. The controls that sat under the title live in here now, so the
        // cover is the name and the ground and nothing else.
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button {
                    choosing = true
                } label: {
                    Label(coverImage == nil ? "Add cover" : "Change cover",
                          systemImage: "photo.on.rectangle.angled")
                }
                if coverImage != nil {
                    Button(role: .destructive) {
                        FolderCoverStore.clear(folder.id)
                        coverImage = nil
                    } label: {
                        Label("Remove cover", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            // The pager ignores the container's bottom inset so pages run full height; the
            // control adds it back, the same way the composer does.
            .padding(.bottom, 16 + homeInset)
        }
        .photosPicker(isPresented: $choosing, selection: $pick, matching: .images)
        // Into the folder: a tap anywhere on the cover. Buttons above still win their own taps.
        //
        // No swipe. A leading drag was here as a simultaneous gesture, and a drag that competes
        // with a scroll view loses — after coming back from the nest the pager would not page
        // until you swiped slowly enough for the scroll to win the touch. Same lesson the nest
        // learned with swipe-to-reveal: on a surface whose job is scrolling, nothing else drags.
        .onTapGesture { open() }
        .background { FolderGround(folder: folder, coverImage: coverImage) }
        .task(id: folder.id) { coverImage = FolderCoverStore.load(folder.id) }
        .task(id: pick) {
            guard let pick,
                  let data = try? await pick.loadTransferable(type: Data.self) else { return }
            FolderCoverStore.save(data, for: folder.id)
            coverImage = FolderCoverStore.load(folder.id)
            self.pick = nil
        }
    }

    // MARK: - The cover
    //
    // Real data only: the folder's name at its real length. The hard case is the longest name,
    // which wraps to three lines and scales down from there.

    /// Editorial, in Fraunces. Settled 2026-09-30 from three setups: this structure won,
    /// carrying the face from the Plate setup (Fraunces Black) in place of Newsreader. The deck
    /// The months and count that were the deck now open the summary's own text:
    /// "(4 from May to Aug 2026) - …" — see `CoverSummary.lead`. Poster (Anton all-caps, the count as a numeral) and Plate (the same
    /// face centred in a hairline frame) are in archive/2026-09-28-paged-home/why.md.
    private var editorial: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pinned to the top, not centred, so the summary's slot is fixed beneath the name.
            // 84 clears the status bar on a page that ignores the top inset.
            Text(folder.name)
                .font(.custom("Fraunces-Black", size: 54))
                .lineLimit(3)
                .minimumScaleFactor(0.55)
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
                // A 2pt black outline on the glyphs themselves (2026-10-01). It read as "2D, flat,
                // paper" — the language the rest of this page now follows. See `TextOutline`.
                .modifier(TextOutline(color: .black, width: 2))
            // The summary as a run of message bubbles, leading: the folder's voice answering
            // yours, the first turn of the conversation the nest continues. The stamp that sat
            // above it went on 2026-10-01; the name and the bubbles are the whole cover.
            CoverSummary(folder: folder)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.top, 84)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

/// The folder's summary as a run of short messages from Apple's Foundation Models — Private Cloud
/// Compute where it can be reached, the on-device model beneath it. Two to four bubbles, one line
/// each, a briefing in a casual lowercase voice. Cached per folder and content for the session,
/// and on disk beneath that.
struct CoverSummary: View {
    let folder: Folder
    @State private var messages: [String] = []
    @State private var thinking = false
    /// Flipped once the messages land; the bubbles spring in off it, staggered.
    @State private var shown = false

    private static var cache: [String: [String]] = [:]

    /// What the summary was written for: the count and the newest timestamp, plus a format
    /// version, so a reworded prompt never reads a stale answer back (v6: a briefing, one observation last).
    private var signature: String {
        let newest = folder.notes.map(\.timestamp).max().map { "\(Int($0.timeIntervalSince1970))" } ?? "0"
        return "v6-\(folder.notes.count)-\(newest)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if thinking {
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonView(Capsule(), .black.opacity(0.12)).frame(height: 12)
                    SkeletonView(Capsule(), .black.opacity(0.12)).frame(height: 12).frame(maxWidth: 160)
                }
                .padding(.vertical, 5)
                .frame(width: 240, alignment: .leading)
                .modifier(PaperBubble(tail: .leading))
            } else {
                ForEach(Array(messages.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.custom("Lexend-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.9))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(PaperBubble(tail: i == messages.count - 1 ? .leading : .none))
                        // Pop: from 0.8 with a slight overshoot and settle, each 120ms after the
                        // last — successive texts arriving. One Bool drives it; Core Animation
                        // tweens the scale and opacity (Pattern 1).
                        .scaleEffect(shown ? 1 : 0.8, anchor: .bottomLeading)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.36, dampingFraction: 0.58).delay(Double(i) * 0.12), value: shown)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
        .task(id: "\(folder.id)-\(signature)") { await load() }
        .onChange(of: messages) { _, new in
            shown = false
            if !new.isEmpty { Task { @MainActor in try? await Task.sleep(for: .milliseconds(30)); shown = true } }
        }
    }

    /// Whether this build was signed with an entitlement, read from the embedded provisioning
    /// profile — `SecTask` is not in the public iOS SDK. An App Store build has no embedded profile
    /// and answers false, which is fine for a study.
    private static func hasEntitlement(_ name: String) -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let open = data.range(of: Data("<plist".utf8)),
              let close = data.range(of: Data("</plist>".utf8), in: open.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[open.lowerBound..<close.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return false }
        return (entitlements[name] as? Bool) == true
    }

    /// A briefing, in casual lowercase texting — settled 2026-10-01 after four rounds that aimed
    /// at a mirror ("what you keep returning to") and got keyword-counting from the on-device
    /// model. The reframe: every bubble but the last restates one particular thing the entries
    /// say; the last is the one place a single observation is allowed, so a wrong reading is
    /// contained by position. No example sentences — an earlier draft's example came back as
    /// the next folder's first line, word for word. The shape is described, never shown.
    private var instructions: String {
        "you're texting the person who wrote these notes. you know them well. write the way you'd "
        + "actually text: all lowercase, contractions, short, direct, kind. the person is always "
        + "'you' and their notes are 'your notes'. "
        + "your job is a briefing: tell them what's in this folder, fast. "
        + "write two to four messages, one per line, each one plain sentence under eighteen words. "
        + "every message except the last says one particular thing the entries say — a plan, a "
        + "name, a place, a how-to, a worry — in your own short words. "
        + "the last message is the one place you may add a single modest observation about what "
        + "the entries have in common. "
        + "the folder's title and its topic words are not the content; what's written is. "
        + "everything comes from these entries and nothing else. "
        + "no greeting and no opener: the first word is already about what's in the notes. "
        + "no slang that will sound dated in a year, no hashtags, no emoji."
    }

    private func load() async {
        let key = "\(folder.id)-\(signature)"
        if let hit = Self.cache[key] { messages = hit; return }
        if let (text, _) = CoverSummaryStore.load(folder.id, signature: signature) {
            let lines = Self.split(text); Self.cache[key] = lines; messages = lines; return
        }
        guard !folder.notes.isEmpty else { messages = []; return }
        thinking = true
        defer { thinking = false }
        let thoughts = folder.notes.sorted { $0.timestamp > $1.timestamp }.prefix(24)
            .map { String((($0.transcript.isEmpty ? $0.title : $0.transcript)).prefix(400)) }
            .filter { !$0.isEmpty }
        var result = ""
        #if canImport(FoundationModels)
        // The name goes in unquoted and the entries as plain lines: the model mirrors the
        // format it is shown, and a quoted name came back as a quoted word in every message.
        let prompt = "notebook: \(folder.name)\nentries, newest first:\n\n"
            + thoughts.joined(separator: "\n\n") + "\n\nwrite the messages."
        // 1. Private Cloud Compute — entitlement first; constructing the model without it traps.
        if #available(iOS 27.0, *), Self.hasEntitlement("com.apple.developer.private-cloud-compute") {
            let pcc = PrivateCloudComputeLanguageModel()
            if case .available = pcc.availability, !pcc.quotaUsage.isLimitReached {
                let session = LanguageModelSession(model: pcc, instructions: instructions)
                if let r = try? await session.respond(to: prompt) { result = r.content }
            }
        }
        // 2. The on-device model.
        if result.isEmpty, case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: instructions)
            if let r = try? await session.respond(to: prompt) { result = r.content }
        }
        #endif
        let lines = Self.split(result)
        Self.cache[key] = lines
        if !lines.isEmpty { CoverSummaryStore.save(lines.joined(separator: "\n"), source: "casual", for: folder.id, signature: signature) }
        messages = lines
    }

    /// One message per line, bullets and numbering stripped, at most four.
    private static func split(_ text: String) -> [String] {
        let lines: [String] = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^(\d+[.)]|[-•*])\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(4))
    }
}

/// The nest as a screen of its own. One scroll view, the composer as its bottom inset, the
/// folder's ground behind it, and a drawn back control to leave — hiding the navigation bar
/// takes the edge swipe with it.
struct NestScreen: View {
    let folder: Folder
    @State private var coverImage: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Nest(folder: folder, palette: Palette(folder))
            .background { FolderGround(folder: folder, coverImage: coverImage) }
            .toolbar(.hidden, for: .navigationBar)
            // Hiding the navigation bar disables the system's edge-swipe pop; the recognizer is
            // still on the navigation controller and comes back with a delegate that allows it
            // whenever there is something to pop. UIKit's own gesture, so it coexists with the
            // scroll view — unlike the drag that was tried on the cover.
            .background(PopGestureEnabler())
            // A back control of our own as well, upper left where the system's would be, in the
            // same glass as the composer.
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.leading, 16)
                .padding(.top, 4)
            }
            // OUTERMOST, after the overlay. The whole screen in the dark scheme — its ground is
            // always dark — so every glass on it is the same smoky variant. This sat above the
            // overlay for a day, and an overlay's content inherits from outside the modifier it
            // is attached to: the back control rendered the light variant while the bubbles and
            // composer rendered dark.
            .environment(\.colorScheme, .dark)
            .task(id: folder.id) { coverImage = FolderCoverStore.load(folder.id) }
    }
}

/// The nest: one vertical page of blocks.
private struct Nest: View {
    let folder: Folder
    let palette: Palette
    /// Whether the composer has the keyboard up. Local: the nest is the only thing that reacts,
    /// by returning to the end of the thread so the newest thought sits above the keyboard.
    @State private var composing = false

    @State private var order: [UUID] = []
    /// Rests at the end of the thread and is nudged back there whenever a thought arrives.
    @State private var position = ScrollPosition(edge: .bottom)

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

    /// Scroll to the end of the thread, one runloop turn late.
    ///
    /// The delay is the whole point. `onChange` fires while SwiftUI is still processing the update
    /// that added the bubble, so scrolling right then goes to the PREVIOUS bottom — the new
    /// thought lands below the fold, underneath the composer, which is exactly what it looked
    /// like. Yielding once lets the new content and any clearance change be laid out first.
    private func toBottom() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(RealComposerBar.morph) { position.scrollTo(edge: .bottom) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // No running header. It named the folder, and so does the composer's placeholder
            // ("Add to CommunityHealth"), permanently and without costing a row.
            Color.clear.frame(height: 12)

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
                // The 22 lives on the content, not around the scroll view: the composer is the
                // scroll view's safe-area inset and must run to the dock's own 12, as in prod.
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // THE SAME LAYER. The composer was an overlay on the pager while this scroll view
            // sat three levels inside it, so every attempt to clear it was arithmetic between two
            // coordinate spaces the scroll view could not see — content padding, then a content
            // margin, then a measured dock height, each adjusting a number on a relationship that
            // only ever agreed by accident. As a bottom safe-area inset the scroll view reserves
            // exactly the composer's height, whatever it grows to, and nothing is measured.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RealComposerBar(folder: folder, focused: $composing)
            }

            // Opens on the newest thought and returns there when one arrives.
            //
            // The CONTENT's bottom edge, not the last bubble's. `scrollTo(anchor: .bottom)` lines
            // an item up with the scroll view's own bottom edge, which runs underneath the
            // composer — so the thought you just sent was scrolled to exactly where you could not
            // see it. Scrolling to the edge respects the composer's inset instead.
            //
            // One mechanism: `.scrollPosition` seeded at `.bottom` gives the resting position too,
            // so there is no `.defaultScrollAnchor` alongside it to disagree with.
            .scrollPosition($position)
            // Two things send it back to the end, and both go through `toBottom()` so the scroll
            // is only ever driven from one place.
            .onChange(of: blocks.count) { _, _ in toBottom() }
            .onChange(of: composing) { _, up in if up { toBottom() } }
        }
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
    @State private var filament: FilamentTarget?

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
                            TodoStatusCircle(isCompleted: item.done, onColor: false)
                            Text(item.text)
                                .font(.custom("Lexend-Regular", size: 14))
                                .strikethrough(item.done)
                                .foregroundStyle(.black.opacity(item.done ? 0.4 : 0.9))
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
                                .font(.custom("Lexend-Medium", size: 14))
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
                    // written, at one size, and the bubble is what says where it ends. Lexend 14
                    // (2026-10-01), the summary's face, so the cover and its thoughts read as one
                    // voice; Newsreader 16 before that.
                    // Filaments, lit: each attached keyword's range in the fil's lighter gradient
                    // colour and a heavier weight, as FilCard.highlighted does, and a link so a
                    // tap on the word opens its filament. The bubble's own tint and dark ground
                    // are the only differences from the card.
                    Text(Self.lit(note))
                        .font(.custom("Lexend-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.9))
                        .lineSpacing(4)
                }
            }
        }
        // Filaments as chips: the keywords in a row beneath whatever the bubble holds, each a
        // tap to its filament. Works for every kind — a photo or a voice fil has no words to
        // light, so chips are the only form that reaches them.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "fil-filament", let k = url.host()?.removingPercentEncoding else { return .systemAction }
            filament = FilamentTarget(keyword: k); return .handled
        })
        .sheet(item: $filament) { KeywordPopup(note: note, keyword: $0.keyword) }
        // A bubble, trailing, the way your own messages sit. Transparent with a hairline rather
        // than filled: on a photograph ground a filled bubble becomes a second surface and the
        // cover stops showing through, which is the thing the cover was for.
        //
        // Photographs get no bubble, which is what iMessage does too — a picture is already an
        // object and a border around it reads as a frame nobody asked for.
        .modifier(PaperBubble(tail: .trailing))
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
private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The shipped `ComposerBar`, in the home's own glass dock, as the nest's bottom inset.
///
/// It won the 2026-09-29 bake-off against a grouped Add | Ask row built for the nest (that row
/// is in archive/2026-09-29-nest-composer/why.md, with the one thing it did better: capture
/// types as peers instead of a `+` menu). Adapted, not ported: it gets `CanvasHome`'s dock
/// treatment, is forced to the dark scheme so its asset-catalogue colours resolve on the nest's
/// ground, and is handed a `contextLabel` for its placeholder.
struct RealComposerBar: View {
    /// The one spring the nest moves on: the scroll to the end of the thread, and the composer's
    /// bottom inset going to zero as the keyboard takes over as the floor. Snappy rather than the
    /// Island's own settle, because this is tapped constantly. (It once also carried a hand-rolled
    /// page lift; the system raises the nest now, and that lift is gone.)
    static let morph: Animation = .spring(response: 0.34, dampingFraction: 0.86)

    let folder: Folder?
    /// Reported to the nest so it can scroll to the end when the keyboard comes up.
    @Binding var focused: Bool

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var todos: [ComposerTodo] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var staged: [Data] = []
    @FocusState private var focus: Bool

    var body: some View {
        ComposerBar(text: $text,
                    todos: $todos,
                    selectedPhotos: $photos,
                    stagedImageData: staged,
                    isProcessing: false,
                    // `ComposerBar` renders this verbatim; the shipped caller supplies the
                    // prefix itself (CanvasHome: "Add to \(name)"). Passing the bare name
                    // printed "CommunityHealth" as the placeholder.
                    contextLabel: folder.map { "Add to \($0.name)" },
                    focus: $focus,
                    onSend: send,
                    onRecordVoice: {},
                    onRemoveStagedImage: { staged.remove(at: $0) },
                    onCapturePhoto: { staged.append($0) })
            // The home's own dock treatment, lifted from `CanvasHome`: pad 14, glass at a 30
            // radius, then inset 12 / 8 so it FLOATS rather than meeting the screen edges. The
            // glass lives in the dock, not in `ComposerBar` — which is why mounting the composer
            // on a slab was the wrong comparison.
            .padding(14)
            // The home dock's own 30. Glass, settled 2026-10-01 against paper and line art.
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .padding(.horizontal, 12)
            // 8 beneath, as the shipped dock has. A pushed screen keeps the window's bottom inset
            // on its own, so adding the measured one here stacked two — the dock sat high.
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            // Forced dark because the nest's ground always is, and `Theme.primaryText` resolves
            // from the asset catalogue — in light it would be dark text on dark glass.
            .environment(\.colorScheme, .dark)
            // No offset of its own. The keyboard region is alive all the way down, so the
            // system raises it — this is the nest's bottom inset, and the nest shrinks.
            .onChange(of: focus) { _, f in focused = f }

            .task(id: photos.map(\.itemIdentifier)) {
                guard !photos.isEmpty else { return }
                var loaded: [Data] = []
                for item in photos {
                    if let d = try? await item.loadTransferable(type: Data.self) { loaded.append(d) }
                }
                staged = loaded
            }
    }

    /// Text or to-do rows unlock send, the same rule the shipped composer enforces. Staged
    /// photographs ride along on that one note.
    private func send() {
        let body = text.trimmed
        let items = todos.map(\.text).map { $0.trimmed }.filter { !$0.isEmpty }
        // Rows alone are enough; the composer's own send rule says the same.
        guard !body.isEmpty || !items.isEmpty else { return }
        let note = Note(transcript: body,
                        timestamp: .now,
                        todos: items,
                        imageData: staged.first)
        note.folder = folder
        context.insert(note)
        try? context.save()
        text = ""
        todos = []
        photos = []
        staged = []
    }
}

/// The bottom safe-area inset as read before any ancestor ignores it — see `SandboxRoute`.
private struct HomeInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var homeInset: CGFloat {
        get { self[HomeInsetKey.self] }
        set { self[HomeInsetKey.self] = newValue }
    }
}

/// The keyword whose filament a tap asked for; `Identifiable` so a sheet can present it.
private struct FilamentTarget: Identifiable { let keyword: String; var id: String { keyword } }

private extension Block {
    /// `FilCard.highlighted`'s treatment, carried into the bubble: every attached keyword's range
    /// in the fil's lighter gradient colour at a heavier weight, each range a link the bubble's
    /// `openURL` handler turns into the keyword's popup.
    /// A lit word on paper: black at Lexend Medium on a yellow highlight band — one colour for
    /// every fil, a marker pen on a page (settled 2026-10-01 over the fil's own colour and an
    /// underline). Each range is a link the bubble's `openURL` handler turns into the popup.
    static let highlight = Color(red: 1.0, green: 0.92, blue: 0.35)
    static func lit(_ note: Note) -> AttributedString {
        var a = AttributedString(note.transcript)
        let keywords = note.attachments.map(\.keyword)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return a }
        for k in keywords {
            let enc = k.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? k
            var start = a.startIndex
            while start < a.endIndex, let range = a[start...].range(of: k, options: .caseInsensitive) {
                a[range].font = .custom("Lexend-Medium", size: 14)
                a[range].foregroundColor = .black
                a[range].backgroundColor = Self.highlight
                a[range].link = URL(string: "fil-filament://\(enc)")
                start = range.upperBound
            }
        }
        return a
    }
}

/// The cover summaries on disk, so a relaunch does not re-ask the model for every folder. One JSON
/// file beside the cover images, keyed by folder id, each entry carrying the signature it was
/// written for. Study-only, like `FolderCoverStore`: if this ships it becomes fields on `Folder`,
/// the way the Claude caption already has `summary` and `summarySignature`.
enum CoverSummaryStore {
    private struct Entry: Codable { var signature: String; var text: String; var source: String }

    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SandboxFolderCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("summaries.json")
    }

    private static var entries: [String: Entry] = {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }()

    /// The stored summary if it was written for THIS signature; a stale one is a miss.
    static func load(_ id: UUID, signature: String) -> (String, String)? {
        guard let e = entries[id.uuidString], e.signature == signature else { return nil }
        return (e.text, e.source)
    }

    static func save(_ text: String, source: String, for id: UUID, signature: String) {
        entries[id.uuidString] = Entry(signature: signature, text: text, source: source)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// Re-enables `interactivePopGestureRecognizer` on the enclosing navigation controller. SwiftUI
/// turns it off when the bar is hidden; the delegate here says yes whenever the stack has more
/// than one screen, which is the only condition the system itself uses.
private struct PopGestureEnabler: UIViewRepresentable {
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigation: UINavigationController?
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            (navigation?.viewControllers.count ?? 0) > 1
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var r: UIResponder? = view
            while let next = r?.next { if let vc = next as? UIViewController { r = vc; break }; r = next }
            guard let nav = (r as? UIViewController)?.navigationController,
                  let pop = nav.interactivePopGestureRecognizer else { return }
            context.coordinator.navigation = nav
            pop.delegate = context.coordinator
            pop.isEnabled = true
        }
    }
}

/// A stroke around text, drawn as eight offset copies of the same text beneath it. Every copy
/// carries the view's full modifier chain (font, line limit, scale, wrapping), so the outline
/// wraps and scales exactly as the text does. `width` is the outline's reach in points.
private struct TextOutline: ViewModifier {
    let color: Color
    let width: CGFloat

    private var offsets: [CGSize] {
        let d = width, h = width * 0.7071
        return [CGSize(width: d, height: 0), CGSize(width: -d, height: 0),
                CGSize(width: 0, height: d), CGSize(width: 0, height: -d),
                CGSize(width: h, height: h), CGSize(width: -h, height: h),
                CGSize(width: h, height: -h), CGSize(width: -h, height: -h)]
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    ForEach(Array(offsets.enumerated()), id: \.offset) { _, o in
                        content.foregroundStyle(color).offset(o)
                    }
                }
            }
    }
}

/// The paper bubble: white, a 2pt black border, the chat tail on one side — or none, for a
/// bubble mid-run; only the last of a sender's run has a tail, as in Messages. The direction the
/// cover's black-edged name named (2026-10-01).
private struct PaperBubble: ViewModifier {
    enum Tail { case leading, trailing, none }
    let tail: Tail

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.leading, tail == .leading ? 22 : 16)
            .padding(.trailing, tail == .trailing ? 22 : 16)
            .background {
                // Softened from full white: "a bit aggressive on the eyes". One shape; the tail is
                // drawn trailing and a leading bubble is the same shape mirrored.
                ZStack {
                    if tail == .none {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.86))
                        RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black, lineWidth: 2)
                    } else {
                        ChatBubble().fill(.white.opacity(0.86))
                        ChatBubble().stroke(.black, lineWidth: 2)
                    }
                }
                .scaleEffect(x: tail == .leading ? -1 : 1)
            }
    }
}

#endif
