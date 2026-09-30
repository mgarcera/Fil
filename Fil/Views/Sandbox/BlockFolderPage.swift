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
    /// Axis B: what sits under the hairline.
    let line: String
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
    // Real data only: the folder's name at its real length, its real count, the months its
    // thoughts actually span. The hard case is the longest name, which wraps to three lines and
    // scales down from there.

    private var count: Int { folder.notes.count }

    /// "SEP 2026", or "JUL – SEP 2026" when the thoughts span months. Empty folder: nothing.
    private var span: String {
        let stamps = folder.notes.map(\.timestamp)
        guard let first = stamps.min(), let last = stamps.max() else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        let a = f.string(from: first).uppercased(), b = f.string(from: last).uppercased()
        if a == b { return a }
        let m = DateFormatter(); m.dateFormat = "MMM"
        return Calendar.current.isDate(first, equalTo: last, toGranularity: .year)
            ? "\(m.string(from: first).uppercased()) – \(b)" : "\(a) – \(b)"
    }

    /// "SEP 2026 • 15": the months and the bare count, a bullet between. No word for the count —
    /// on a cover the number is enough, and the unit is the notebook itself.
    private var deck: String {
        [span, count > 0 ? "\(count)" : ""].filter { !$0.isEmpty }.joined(separator: "  •  ")
    }

    /// Editorial, in Fraunces. Settled 2026-09-30 from three setups: this structure won,
    /// carrying the face from the Plate setup (Fraunces Black) in place of Newsreader. The deck
    /// moved from above the name to beneath the summary the same day — the name leads, the rule,
    /// then what's in here, then the deck. Poster (Anton all-caps, the count as a numeral) and Plate (the same
    /// face centred in a hairline frame) are in archive/2026-09-28-paged-home/why.md.
    private var editorial: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text(folder.name)
                .font(.custom("Fraunces-Black", size: 54))
                .lineLimit(3)
                .minimumScaleFactor(0.55)
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(.white.opacity(0.7)).frame(height: 1).padding(.top, 8)
            underline
                .padding(.top, 4)
            // The deck closes the cover: name, rule, what's in here, then the months and count.
            if !deck.isEmpty {
                Text(deck)
                    .font(.custom("ArchivoNarrow-SemiBold", size: 12))
                    .tracking(2.4)
                    .opacity(0.8)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Under the line
    //
    // The cover as the folder's surface: what is in here, in a few lines, without opening it.
    // Three kinds on axis B. The summary is written by Apple's Foundation Models: the server
    // model on Private Cloud Compute where it can be reached (iOS 27, the managed entitlement,
    // a network, quota left), the on-device model beneath it, and the newest thought's own
    // line beneath that. The app's Claude caption (`Folder.summary`) is a separate, shipped
    // feature and is left alone here.
    @ViewBuilder private var underline: some View {
        switch line {
        case "latest":
            if let newest = folder.notes.max(by: { $0.timestamp < $1.timestamp }) {
                Text(Self.firstLine(of: newest))
                    .font(.custom("Fraunces-Regular", size: 17))
                    .lineLimit(2)
                    .opacity(0.85)
            }
        case "themes":
            let keys = Array(folder.notes.sorted { $0.timestamp > $1.timestamp }
                .map { $0.keyword.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .prefix(3))
            if !keys.isEmpty {
                Text(keys.map { $0.uppercased() }.joined(separator: "   ·   "))
                    .font(.custom("ArchivoNarrow-Regular", size: 12))
                    .tracking(2.4)
                    .opacity(0.8)
            }
        default:
            CoverSummary(folder: folder)
        }
    }

    /// A thought's own first line: the transcript's, or the title when it has no transcript.
    static func firstLine(of note: Note) -> String {
        let body = note.transcript.isEmpty ? note.title : note.transcript
        return body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// A short summary of the folder from Apple's Foundation Models — Private Cloud Compute first,
/// for the larger context and stronger reasoning, the on-device model when PCC cannot be reached,
/// the newest thought's line when neither can. Cached per folder and count for the session.
struct CoverSummary: View {
    let folder: Folder
    @State private var text = ""
    @State private var source = ""
    @State private var thinking = false

    /// Keyed on the folder AND its count, so a new thought re-summarises and a page turn does
    /// not. Static: the study re-creates this view constantly (Pattern 9).
    private static var cache: [String: (String, String)] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if thinking {
                // Three dots while the model writes — the wait is a beat per folder on device,
                // and an empty slot for that beat read as a folder with nothing to say.
                ThinkingDots()
                    .padding(.vertical, 6)
            } else if !text.isEmpty {
                Text(text)
                    .font(.custom("Fraunces-Regular", size: 17))
                    .lineSpacing(3)
                    .opacity(0.85)
                // Study chrome: which model wrote the line, so the verdict is on the right one.
                Text(source)
                    .font(.custom("ArchivoNarrow-Regular", size: 11))
                    .tracking(2)
                    .opacity(0.55)
            }
            // Neither: the model is unavailable or declined, and the slot stays empty rather
            // than standing another line in for it.
        }
        .task(id: "\(folder.id)-\(folder.notes.count)") { await load() }
    }

    /// Whether this build was signed with an entitlement, read from the embedded provisioning
    /// profile — the plist inside its CMS blob carries the `Entitlements` dictionary. `SecTask`
    /// would be the direct question, but it is not in the public iOS SDK. An App Store build
    /// has no embedded profile and answers false; that is fine for a study, and a shipped feature
    /// would decide this at build time anyway.
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

    private func load() async {
        let key = "\(folder.id)-\(folder.notes.count)"
        if let hit = Self.cache[key] { (text, source) = hit; return }
        guard !folder.notes.isEmpty else { text = ""; source = ""; return }
        thinking = true
        defer { thinking = false }
        let thoughts = folder.notes.sorted { $0.timestamp > $1.timestamp }.prefix(24)
            .map { String((($0.transcript.isEmpty ? $0.title : $0.transcript)).prefix(400)) }
            .filter { !$0.isEmpty }
        var result = "", by = ""
        #if canImport(FoundationModels)
        let instructions = "You are a trusted friend who has read someone's notebook and is telling "
            + "them, warmly and plainly, what they see in it. Speak to them as 'you'. Notice what "
            + "they keep returning to, what seems to matter, and what these entries add up to — "
            + "the way a good advisor reflects a person back to themselves. Be specific to what is "
            + "actually written; never generic. Three or four sentences, under eighty words. No "
            + "quotation marks, no bullet points, no headings, no preamble."
        let prompt = "The notebook is called \"\(folder.name)\". Its recent entries, newest first:\n"
            + thoughts.map { "- " + $0 }.joined(separator: "\n") + "\nWrite the cover text."

        // 1. Private Cloud Compute. iOS 27, the managed entitlement, a network, and quota.
        //
        // The entitlement check comes FIRST and reads the signed binary, because constructing
        // the model without it is a fatal error, not an `.unavailable` — the app terminated on
        // signal 5 the moment a cover appeared, before `availability` could be asked:
        // "FoundationModels/ErrorConversion.swift:140: Fatal error: Missing entitlement". The
        // entitlement is granted by Apple on request; until then this tier is simply skipped.
        if #available(iOS 27.0, *), Self.hasEntitlement("com.apple.developer.private-cloud-compute") {
            let pcc = PrivateCloudComputeLanguageModel()
            if case .available = pcc.availability, !pcc.quotaUsage.isLimitReached {
                let session = LanguageModelSession(model: pcc, instructions: instructions)
                if let r = try? await session.respond(to: prompt) {
                    result = r.content.trimmingCharacters(in: .whitespacesAndNewlines); by = "PRIVATE CLOUD COMPUTE"
                }
            }
        }
        // 2. The on-device model — no network, no quota, no entitlement.
        if result.isEmpty, case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: instructions)
            if let r = try? await session.respond(to: prompt) {
                result = r.content.trimmingCharacters(in: .whitespacesAndNewlines); by = "ON DEVICE"
            }
        }
        #endif
        // No third tier. If neither model answers, the slot is empty — a stand-in line pretended
        // to be a summary and read as one.
        Self.cache[key] = (result, by)
        text = result; source = by
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
            // A back control of our own. Hiding the navigation bar also took the interactive pop
            // with it — the edge swipe did nothing on device — so the way out has to be drawn.
            // Same glass as the composer, upper left where the system's would be.
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
    @Environment(\.bubbleGlass) private var bubbleGlass

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
                    // written, at one size, and the bubble is what says where it ends.
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
            // Two treatments, flipped on the sandbox's first axis. The hairline was chosen so a
            // photograph ground keeps showing through; glass keeps that and gives the bubble the
            // composer's own material, so the two read as one family.
            if bubbleGlass {
                // `.regular`, the composer's own material. It looked milkier than the composer
                // once, and a round went to `.clear` for it — but the material was never the
                // difference. The composer is forced to the dark scheme and glass renders a
                // smokier variant there; the bubbles inherited the app's scheme and got the
                // light variant. The nest is dark now (see `NestScreen`), so they match.
                Color.clear.glassEffect(.regular, in: ChatBubble())
            } else {
                ChatBubble().stroke(.white.opacity(0.4), lineWidth: 1)
            }
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
    /// The home indicator's height, read above the pager's `ignoresSafeArea`. Added beneath the
    /// composer while the keyboard is down; when it is up the keyboard is the floor instead.
    @Environment(\.homeInset) private var homeInset

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
            // The home dock's own 30.
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .padding(.horizontal, 12)
            // 8 above the floor, the shipped dock's gap. The floor is the home indicator when the
            // keyboard is down and the keyboard when it is up, so the inset goes to zero with
            // focus — on the same spring, so it is one movement with the keyboard's.
            .padding(.bottom, 8 + (focus ? 0 : homeInset))
            .animation(Self.morph, value: focus)
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

    /// Text is what unlocks send, the same rule the shipped composer enforces. To-do rows and
    /// staged photographs ride along on that one note.
    private func send() {
        let body = text.trimmed
        guard !body.isEmpty else { return }
        let items = todos.map(\.text).map { $0.trimmed }.filter { !$0.isEmpty }
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

/// Whether a thought's bubble is drawn in glass or as a hairline — the sandbox's first axis.
private struct BubbleGlassKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var bubbleGlass: Bool {
        get { self[BubbleGlassKey.self] }
        set { self[BubbleGlassKey.self] = newValue }
    }
}

/// Three dots breathing in sequence. Driven by one Bool flipped on appear, so `body` runs once and
/// Core Animation carries the pulse — Pattern 1 in `swiftui-animation-performance`.
private struct ThinkingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .opacity(on ? 0.9 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.18), value: on)
            }
        }
        .onAppear { on = true }
    }
}
#endif
