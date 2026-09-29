#if DEBUG
import SwiftUI
import SwiftData
import PhotosUI
import QuickLook

/// SPIKE — the paged folder home, ported from the HTML prototype 2026-09-28.
///
/// The HTML is design truth; this is the same design in the runtime it ships in. Every fidelity
/// question during a real port is answered by reading the prototype, not by remembering it:
/// `archive/2026-09-28-paged-home/` holds what lost and why, and the artifact holds what won.
///
/// **What the arc settled, in order.**
/// 1. Three directions on Mason's own axes — structure, weight, world. Structure won (D1); the
///    ledger and the deck are written up in the archive. The deck was built to test dropping the
///    blob on a light ground and lost, which is what proved black was load-bearing for it.
/// 2. Below the hero: by type, timeline, or type cards. Timeline won, on the finding that people
///    navigate to their own things by recency and recognition rather than by searching — what
///    Drive, Files and SharePoint all lead with.
/// 3. The blob comes out. Each kind now carries its own form instead: a note is text, a photo is a
///    small card that expands, voice is a waveform with its caption under it, a link is a link
///    card, a to-do is a line with a box.
/// 4. No dates, no type tags, no counts, no containers — the content is the whole row. A quiet week
///    marker is the one exception, because with nothing dated a long folder has nothing to orient
///    by, and recency was the reason the timeline won in the first place.
/// 5. **Monochrome on the parent folder.** Every mark on a page takes that folder's colour: the
///    rail, the markers, the waveform, the boxes, the link tile. Per-fil gradients appear nowhere.
///    A photograph is the one exception, because a photograph is not a mark.
///
/// **Composed, not redrawn.** `FolderShape`, `BlurredFilBackground`, `CompactWaveformView` and
/// `TodoStatusCircle` are the app's own, and the text comes from `Note.titleLine` and
/// `Note.bodyAfterTitle` rather than from a second line-splitting rule.
struct PagedHomeStudy: View {
    /// "none", "plates" or "mixed" — whether content sits on a plate or straight on the ground.
    let variant: String
    /// "transport", "bin" or "folder" — what the bottom bar carries.
    let bar: String
    var stressed: Bool

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)])
    private var folders: [Folder]
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]

    @State private var folderIndex = 0
    @State private var folderID: Int? = 0
    /// 0 is the cover, 1 is the nest. Lifted here because the outer pager has to know it: down
    /// belongs to the folders at 0 and to the content at 1.
    @State private var card = 0
    /// Navigate is the resting mode; the other three each open the bar.
    @State private var barMode: BottomBar.Mode = .navigate
    /// What the keyboard is covering. Observed rather than assumed, because the room sits above it.
    @State private var keyboard: CGFloat = 0

    /// The one number both translations read. Keying the animation to THIS rather than to `barMode`
    /// keeps the keyboard's arrival part of the same movement: the spring retargets mid-flight
    /// instead of starting a second one.
    private var lift: CGFloat { barMode == .navigate ? 0 : BottomBar.lift(keyboard: keyboard) }

    /// The bar belongs to the nest, so the page only rises when you are in one.
    private var inNest: Bool { card > 0 }

    private var pinned: Folder? { folders.first { PinnedFolderStore.shared.isPinned($0.id) } }

    /// Real folders, and at the stressed setting the same folders repeated to twelve — which keeps
    /// the longest title, the empty summary and the folder with no fils in the sample.
    private var pool: [Folder] {
        guard stressed, !folders.isEmpty else { return folders }
        return (0..<12).map { folders[$0 % folders.count] }
    }

    /// How many cards a folder's run has after the cover: one for the consolidated reading page
    /// when it has any prose, plus one per object.
    static func cardCount(_ folder: Folder) -> Int {
        let prose = folder.notes.filter {
            $0.todoRowItems.isEmpty && !$0.isImageFil && !$0.isLinkFil && $0.audioFilePath.isEmpty
        }
        return (prose.isEmpty ? 0 : 1) + (folder.notes.count - prose.count)
    }

    private var pages: [Folder] {
        let rest = pool.filter { $0.id != pinned?.id }
        guard let pinned else { return rest }
        return [pinned] + rest
    }

    var body: some View {
        ZStack {
            // Behind everything and never moved. A translation lifts the page off the bottom of
            // the screen, and whatever is under it is what you see for the length of the
            // animation — black, before this.
            (pages.indices.contains(folderIndex)
             ? AnyView(LinearGradient(colors: [Palette(pages[folderIndex]).groundFrom,
                                               Palette(pages[folderIndex]).groundTo],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
             : AnyView(Color.black))
                .ignoresSafeArea()

            if pages.isEmpty {
                Text("No folders yet — make one in the app, then come back.")
                    .font(StudyType.sans(14)).foregroundStyle(Theme.secondaryText).padding(40)
            } else {
                // Folders page DOWN. One horizontal step from a folder's cover leads into its
                // nest, and while you are in there the vertical axis belongs to the content — so
                // folder paging is switched off rather than competing with the scroll. The axis
                // changes meaning by DEPTH, which is safe in a way that changing it by scroll
                // position was not: you can only be in one place, and you swiped to get there.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { i, folder in
                            NestFolderPage(folder: folder,
                                           card: Binding(get: { folderIndex == i ? card : 0 },
                                                         set: { if folderIndex == i { card = $0 } }))
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(i)
                                // Only while you are paging folders. Translating the pager makes
                                // neighbouring pages appear, and trusting that inside a nest
                                // re-pointed everything at whichever folder drifted into view.
                                .onAppear { if card == 0 { folderIndex = i } }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $folderID)
                // The whole point: inside the nest, down is the content's.
                .scrollDisabled(card > 0)
                .ignoresSafeArea()
                .onChange(of: folderID) { _, new in
                    // Folder paging is off inside a nest, so a change reported while you are in
                    // one is the scroll view re-snapping under our own translation — never you
                    // moving. Put it back. Guarding on `old != new` was not enough: raising the
                    // keyboard moves the pager far enough that the snap is a genuine change, and
                    // it threw you out of the nest and onto another folder.
                    //
                    // The write-back re-fires this handler once with `new == folderIndex`, which
                    // takes the early return, so it settles rather than looping.
                    guard card == 0 else {
                        if new != folderIndex { folderID = folderIndex }
                        return
                    }
                    folderIndex = new ?? 0
                }
                // Swiping back out to the cover takes the composer with it, keyboard and all.
                .onChange(of: card) { _, new in if new == 0 { barMode = .navigate } }
                // Reachability, not a keyboard inset: everything on screen translates by the
                // height the bar gained. Padding only made the content taller, which moves nothing
                // unless you are already at the bottom — and left a black band where the page had
                // ended. A translation moves the page, the cover, the rail, all of it.
                .offset(y: -lift)
                .overlay(alignment: .trailing) {
                    // Hidden in the nest, because it moves between folders and that is exactly
                    // what this depth does not do.
                    FolderRail(count: pages.count,
                               index: Binding(get: { folderID ?? 0 }, set: { folderID = $0 }))
                        .opacity(card == 0 ? 1 : 0)
                        .allowsHitTesting(card == 0)
                        .animation(.snappy, value: card)
                }
                .overlay(alignment: .bottom) {
                    // Outside the page's translation because it carries its own: the bar is
                    // always full height, sitting `lift` below the screen when shut, and rises
                    // into the space the page vacates. Both movements are `.offset` under the one
                    // spring below, which is the only way they stay on the same frame.
                    BottomBar(folderName: pages.indices.contains(folderIndex)
                              ? pages[folderIndex].name : nil,
                              folder: pages.indices.contains(folderIndex) ? pages[folderIndex] : nil,
                              keyboard: keyboard,
                              visible: inNest,
                              mode: $barMode)
                        .ignoresSafeArea(edges: .bottom)
                }
                // ONE animation for the page's translation and the bar's growth. Two separate
                // ones drift apart by a frame or two mid-flight, and the gap between them is
                // exactly the band that was flashing.
                .animation(BottomBar.morph, value: lift)
                .animation(BottomBar.morph, value: inNest)
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillShowNotification)) { n in
                    keyboard = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                                as? CGRect)?.height ?? 0
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = 0 }
            }

        }
    }
}

// MARK: - One folder, one page

private struct FolderPage: View {
    let folder: Folder
    /// The chrome treatment under test, so the compact bar matches the dock.
    let mode: String

    /// Reading-scroll offset, fed by `onScrollGeometryChange` — the same hook and the same
    /// 0...1-progress shape the full-screen player uses to shrink and dim its blob
    /// (`FilFullScreenPlayer.readingContent`). One mechanic, two surfaces.
    @State private var scrollY: CGFloat = 0

    /// How far you scroll before the hero is entirely gone. Longer than the player's 240 because
    /// this hero is a whole screen rather than a band — it should feel like leaving a place, not
    /// like a header collapsing.
    private let collapse: CGFloat = 300
    private var progress: CGFloat { min(1, max(0, scrollY / collapse)) }

    private var palette: Palette { Palette(folder) }

    /// Newest first. There is no manual order on this surface: a feed is chronological or it is a
    /// list with extra steps.
    private var feed: [Note] { folder.notes.sorted { $0.timestamp > $1.timestamp } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // ONE ground for the whole page, at the cover's own saturation, fixed to the
                // screen rather than stretched to the content — so a folder of forty looks like a
                // folder of two and the colour never runs out. The cover draws the same gradient,
                // so when it fades there is nothing to hand off to: it is already this.
                LinearGradient(colors: [palette.groundFrom, palette.groundTo],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                // The hero is a LAYER, not the first row of the scroll. That is what lets it leave
                // on its own terms — drifting slower than the feed, dimming and blurring out —
                // instead of merely sliding off the top. The scroll reserves its screen below.
                hero
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: -min(scrollY * 0.35, geo.size.height * 0.4))
                    .scaleEffect(1 - progress * 0.10)
                    .opacity(1 - progress)
                    .blur(radius: progress * 8)
                    .allowsHitTesting(progress < 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // The hero's screen, reserved. Scrolling past it is what makes the folder
                        // a place you leave rather than a header you scroll off.
                        Color.clear.frame(height: geo.size.height)

                        if feed.isEmpty {
                            Text("Nothing filed here yet")
                                .font(StudyType.sans(13)).foregroundStyle(palette.faint)
                                .frame(maxWidth: .infinity)
                        } else {
                            Feed(notes: feed, palette: palette)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 150)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    scrollY = y
                }

                // Fades in exactly as the hero leaves, so the folder is never unnamed. Without it
                // the feed is a rail of thoughts belonging to nothing.
                compactBar
                    .opacity(progress)
                    .allowsHitTesting(progress > 0.5)
            }
        }
    }

    /// The arrival: the folder's rhythm, running, with its name over it.
    ///
    /// **The cover is generated from WHEN thoughts landed** — not from what the folder holds and
    /// not from what it says. Every thought is a pulse travelling through a field of lines at its
    /// own moment in the cycle, and the wave's frequency is the folder's median gap between
    /// thoughts. A folder filled in one burst pulses together; one filled slowly breathes.
    ///
    /// Kinetic identity, in Paone's sense: the system is the identity and a still is a frame
    /// captured from it with the rules intact. That is why this is a `Canvas` rather than a drawn
    /// image — the widget and the screensaver would sample the same generator at other moments
    /// rather than each drawing their own version of the folder.
    ///
    /// Chosen over a fixed drawn structure (Fry's method applied to time) on 2026-09-28; both are
    /// in `https://claude.ai/artifact/Kr6KyxeTvWBn7AS5NtbaB2`.
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            FolderRhythmCover(notes: folder.notes,
                              from: Color(hex: folder.gradientStartHex),
                              to: Color(hex: folder.gradientEndHex),
                              // Stops the per-frame redraw once the hero is most of the way gone,
                              // the way FilPlayerBlob pauses when it is collapsed out of sight.
                              paused: progress > 0.85)
            Text(folder.name)
                .font(StudyType.serif(46))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.top, 78)
        }
    }

    private static let dateline: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    /// The working state: the same folder, small, once you are reading rather than arriving.
    private var compactBar: some View {
        HStack(spacing: 10) {
            FolderShape()
                .fill(Theme.gradient(startHex: folder.gradientStartHex,
                                     endHex: folder.gradientEndHex,
                                     seed: Double(abs(folder.id.hashValue % 1000)) / 1000))
                .frame(width: 22, height: 17)
            Text(folder.name)
                .font(StudyType.serif(19))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer()
            Text("\(folder.notes.count)")
                .font(Theme.dmMono(11))
                .foregroundStyle(palette.soft)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background {
            if mode != "glass" { palette.plate.opacity(0.94) }
        }
        .glassEffect(mode == "glass" ? .regular : .identity, in: .rect(cornerRadius: 0))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.rail).frame(height: 0.5)
        }
    }
}

// MARK: - The bar

/// Static, always at the bottom of the screen, outside the pager.
///
/// It reports and drives the horizontal position within whichever folder is showing. Putting it
/// inside the folder page made it slide away with the page on a vertical swipe, which read as the
/// controls leaving rather than the content moving. Half of why the reference feels settled is
/// that the page ends in something instead of fading out at the bottom of the screen.
private struct TransportBar: View {
    @Binding var card: Int
    let count: Int

    var body: some View {
        HStack(spacing: 36) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 20))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(card == 0).opacity(card == 0 ? 0.28 : 1)

            Text(card == 0 ? "COVER" : "\(card) / \(count)")
                .font(Theme.dmMono(10)).tracking(1.6)
                .frame(width: 66)

            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 20))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(card >= count).opacity(card >= count ? 0.28 : 1)
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.92))
    }

    private func step(_ d: Int) {
        withAnimation(.snappy) { card = max(0, min(count, card + d)) }
    }
}

// MARK: - The folder rail// MARK: - The folder rail

/// Which folder you are on, down the right edge, and how to get to another one.
///
/// The mirror of the dot row that used to run along the bottom: the axis moved, so the indicator
/// moved with it. Press and drag along it to scrub — the same gesture the horizontal row had, which
/// is the one the iOS home screen's own indicator uses. `minimumDistance: 0` so it engages on touch,
/// and the hit area is 34 points wide against 5-point dots.
private struct FolderRail: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i == index ? 0.98 : 0.40))
                        .frame(width: i == index ? 3 : 5, height: i == index ? 16 : 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let run = geo.size.height * 0.62
                        let start = (geo.size.height - run) / 2
                        let slot = Int(((value.location.y - start) / run) * CGFloat(count))
                        let clamped = max(0, min(count - 1, slot))
                        guard clamped != index else { return }
                        Haptics.selection()
                        index = clamped
                    }
            )
        }
        .frame(width: 34)
        .shadow(color: .black.opacity(0.35), radius: 4)
        .animation(.snappy, value: index)
    }
}

// MARK: - One thought, one screen

/// A thought at the size of the screen, on the folder's ground.
///
/// Brought back 2026-09-28. It lost once as a replacement for the feed — one thought per screen
/// spends what a folder view is for — but the crossed model already made that trade when it took
/// the vertical axis for folders. Given every thought gets a screen either way, it should be the
/// screen the full-screen player gives it.
private struct FullScreenThought: View {
    let note: Note
    let palette: Palette
    /// Room for the folder rail on the trailing edge; the leading side keeps the usual 22.
    var trailingInset: CGFloat = 22
    /// No plates, settled 2026-09-28. White straight on the ground, which the luminance floor in
    /// `Palette` is what makes legible — every gradient end is darkened until white clears 7:1.
    private let onPlate = false
    private var ink: Color { .white }
    private var muted: Color { .white.opacity(0.78) }

    @State private var preview: PhotoPreview?

    private var kind: Kind {
        if !note.todoRowItems.isEmpty { .todo }
        else if note.isImageFil { .photo }
        else if note.isLinkFil { .link }
        else if !note.audioFilePath.isEmpty { .voice }
        else { .note }
    }
    private enum Kind { case todo, photo, link, voice, note }

    /// Short thoughts get to be big. Stepped by character count, because that is what overflows a
    /// screen — a word count says nothing about a wall of prose.
    private var titleSize: CGFloat {
        switch note.titleLine.count {
        case ..<28:  40
        case ..<60:  32
        case ..<120: 26
        default:     22
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            content
                .padding(onPlate ? 18 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if onPlate {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.plate)
                            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
                    }
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, 22)
        .padding(.trailing, trailingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $preview) { target in
            NativePhotoViewer(urls: target.urls, start: 0) { preview = nil }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .note:
            VStack(alignment: .leading, spacing: 12) {
                Text(note.titleLine)
                    .font(StudyType.serif(titleSize))
                    .foregroundStyle(ink)
                    .lineSpacing(titleSize * 0.13)
                if !note.bodyAfterTitle.isEmpty {
                    Text(note.bodyAfterTitle)
                        .font(StudyType.sans(15))
                        .foregroundStyle(muted)
                        .lineSpacing(5)
                }
            }

        case .photo:
            VStack(alignment: .leading, spacing: 14) {
                if let data = note.sortedImageFilImages.first?.data ?? note.imageData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { preview = PhotoPreview(note: note) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.titleLine)
                        .font(StudyType.sans(14.5)).italic()
                        .foregroundStyle(muted)
                    if !note.bodyAfterTitle.isEmpty {
                        Text(note.bodyAfterTitle)
                            .font(StudyType.sans(13.5)).italic()
                            .foregroundStyle(muted)
                    }
                }
            }

        case .voice:
            VStack(alignment: .leading, spacing: 18) {
                CompactWaveformView(duration: note.duration,
                                    color: onPlate ? palette.accent : .white.opacity(0.85))
                    .scaleEffect(x: 2.4, y: 2.2, anchor: .leading)
                    .frame(height: 42)
                Text(note.titleLine)
                    .font(StudyType.serif(titleSize))
                    .foregroundStyle(ink)
            }

        case .link:
            VStack(alignment: .leading, spacing: 16) {
                Text(note.sourceTitle ?? note.sourceURLString ?? "")
                    .font(StudyType.serif(30))
                    .foregroundStyle(ink)
                    .lineSpacing(3)
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(onPlate ? palette.accent : .white.opacity(0.9))
                        .frame(width: 26, height: 26)
                    if let host = note.sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") {
                        Text(host).font(Theme.dmMono(12)).foregroundStyle(muted)
                    }
                }
            }

        case .todo:
            VStack(alignment: .leading, spacing: 16) {
                Text(note.titleLine)
                    .font(StudyType.serif(28))
                    .foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(note.todoRowItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            TodoStatusCircle(isCompleted: item.done, onColor: !onPlate)
                                .frame(width: 19, height: 19)
                            Text(item.text)
                                .font(StudyType.sans(16))
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? muted : ink)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - The palette

/// Every colour one folder's page uses, derived from its two hexes.
///
/// **Plate**, chosen 2026-09-28 from three light treatments. The gradient FRAMES the content rather
/// than carrying it: the ground is the folder tinted 55% toward white and every entry sits on a
/// near-white plate. Paper (82% tint, ink straight onto it) and Field (86% with the cover's line
/// work continuing behind) are in `https://claude.ai/artifact/9ckXSVkaFw13bVFJNWoc1Z`.
///
/// The tint is what makes this legible. On the saturated hexes neither black nor white clears
/// 4.5:1 across a whole gradient — Reading is 2.64:1 for white at one end and 2.89:1 for black at
/// the other. Tinted, black clears 15.8 to 17.8:1 on every end of every folder.
struct Palette {
    let groundFrom: Color
    let groundTo: Color
    let plate: Color
    let ink: Color
    let soft: Color
    let faint: Color
    let rail: Color
    /// The folder's own hue, darkened enough to sit on its own tint: markers, the waveform, the
    /// ticked boxes, the link tile. The only colour on the page that is not ink.
    let accent: Color

    /// Darkens a colour until white text on it clears 7:1 — AAA, not the 4.5:1 minimum, because
    /// this ground carries body copy across a whole screen rather than a label.
    private static func floored(_ c: Color) -> Color {
        var t = 0.0
        while t < 0.95 {
            let candidate = c.mix(with: .black, by: t)
            if contrastWithWhite(candidate) >= 7 { return candidate }
            t += 0.02
        }
        return c.mix(with: .black, by: 0.95)
    }

    private static func contrastWithWhite(_ c: Color) -> Double {
        let r = UIColor(c).cgColor.components ?? [0, 0, 0]
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        guard r.count >= 3 else { return 21 }
        let l = 0.2126 * lin(r[0]) + 0.7152 * lin(r[1]) + 0.0722 * lin(r[2])
        return 1.05 / (l + 0.05)
    }

    init(_ folder: Folder) {
        // A luminance FLOOR, not a ceiling. Each end is darkened until white clears 7:1 on it,
        // because in the reference nothing sits on a plate and the text is white straight on the
        // ground. That inverts the rule from two rounds ago, when white CHROME needed the ground
        // bright enough at 3.5:1 — the same measurement pointing the other way once the ink moved.
        groundFrom = Self.floored(Color(hex: folder.gradientStartHex))
        groundTo   = Self.floored(Color(hex: folder.gradientEndHex))
        plate = Color(red: 1, green: 0.992, blue: 0.980)
        // ONE muted value, not two. At 60% and 45% the pair was barely distinguishable and the
        // lower one was #979595 on the plate — 2.93:1, under the 4.5:1 body text needs. 72% is
        // #59575A at 7.05:1, which clears AAA rather than scraping AA, and against the primary's
        // 17.74:1 it still reads as clearly secondary.
        let base = Color(red: 0.090, green: 0.086, blue: 0.102)   // #17161A
        ink   = base
        soft  = base.opacity(0.72)
        faint = base.opacity(0.72)
        rail  = base.opacity(0.18)
        accent = Color(hex: folder.gradientEndHex).mix(with: .black, by: 0.35)
    }
}

// MARK: - The cover

/// A folder drawn as its own filing rhythm.
///
/// One `Canvas` inside a `TimelineView(.animation)`: lines across the screen, each a sine whose
/// frequency comes from the folder's median gap, with one travelling swell per thought. Colour
/// interpolates down the field between the folder's two hexes, so the cover is monochrome on the
/// folder exactly as the feed below it is.
///
/// **The rhythm is computed ONCE, in init.** It was a computed property reading `notes`, which
/// meant walking a SwiftData relationship, mapping it against `Date.now` and sorting it sixty
/// times a second behind a page you can swipe. That was the stutter, not the drawing.
///
/// **The pulses wrap rather than restart.** Each swell is evaluated at its position and at that
/// position plus and minus a screen width, so one leaving the right edge is already entering from
/// the left. Without the two extra copies the bump vanishes at the edge and reappears at the other,
/// which reads as the animation starting over.
///
/// **Black on the folder's colour, not colour on black.** The gradient fills the canvas and the
/// rhythm is cut into it. Inverted 2026-09-28: the cover now carries the folder's colour at full
/// strength across the whole screen rather than at the weight of a one-point line.
///
/// **Curves, not segments.** The lines are sampled every 8 points and then drawn as quadratics
/// through the midpoints. Stroking the samples directly put visible angles on the crest of every
/// wave — at that step a peak is three straight segments and the eye reads the corners.
///
/// **Cost control, because this runs behind a pager.** Six pulses, lines sampled every 8 points,
/// and the clock capped at 30fps — at this speed nothing moves far enough between frames to need
/// more, and it halves the work. `paused` stops it entirely once the hero has scrolled away.
private struct FolderRhythmCover: View {
    let from: Color
    let to: Color
    var paused: Bool

    /// Days before now, oldest last. The whole input, frozen at init.
    private let days: [Double]
    /// The folder's cadence: the median silence between one thought and the next. Fewer than two
    /// thoughts is no gap at all, so a young folder breathes on a slow default until it has a
    /// rhythm of its own.
    private let cadence: Double

    private let lines = 40
    private let step: Double = 8

    init(notes: [Note], from: Color, to: Color, paused: Bool) {
        self.from = from
        self.to = to
        self.paused = paused
        let now = Date.now
        let all = notes.map { now.timeIntervalSince($0.timestamp) / 86_400 }.sorted()
        days = Array(all.prefix(6))
        if all.count > 1 {
            let gaps = zip(all.dropFirst(), all).map(-).sorted()
            cadence = max(0.35, gaps[gaps.count / 2])
        } else {
            cadence = 1.6
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let span = max(days.max() ?? 1, 1)
                let freq = 1 / cadence
                let width = size.width

                // Slow. The drift was five times this and read as something happening TO the page
                // rather than as the page having a pulse.
                let drift = time * 0.07
                let roll = time * 0.13

                // Each pulse's centre, plus its wrapped copies either side, so nothing pops.
                let centres: [Double] = days.flatMap { day -> [Double] in
                    let phase = (drift + (span - day) / span).truncatingRemainder(dividingBy: 1)
                    let cx = phase * width
                    return [cx - width, cx, cx + width]
                }

                // The folder's own gradient IS the field. The rhythm is drawn INTO it in black
                // rather than over black in colour — inverted 2026-09-28, which also means the
                // cover carries the folder's colour at full strength instead of at line weight.
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(Gradient(colors: [from, to]),
                                                   startPoint: .zero,
                                                   endPoint: CGPoint(x: size.width, y: size.height)))

                for i in 0..<lines {
                    let t = Double(i) / Double(lines)
                    let y0 = (Double(i) + 0.5) / Double(lines) * size.height
                    let swell = sin(.pi * t)

                    // Sample first, then draw through the samples as curves. Stroking the samples
                    // directly is what put visible angles on the crest of every wave: at a step of
                    // 8 points a peak is three straight segments, and the eye reads the corners.
                    var pts: [CGPoint] = []
                    var x: Double = 0
                    while x <= size.width + step {
                        var y = y0 + sin(x * 0.012 * freq + roll + t * 2.2) * (5 + 9 * swell)
                        for cx in centres {
                            let d = (x - cx) / 62
                            if abs(d) < 3 { y -= exp(-d * d) * 26 * swell }
                        }
                        pts.append(CGPoint(x: x, y: y))
                        x += step
                    }

                    // Quadratic through the midpoints: each sample becomes a control point and the
                    // curve passes through the point halfway between neighbours, so the line is
                    // smooth everywhere without taking more samples.
                    var path = Path()
                    path.move(to: pts[0])
                    for j in 1..<(pts.count - 1) {
                        let mid = CGPoint(x: (pts[j].x + pts[j + 1].x) / 2,
                                          y: (pts[j].y + pts[j + 1].y) / 2)
                        path.addQuadCurve(to: mid, control: pts[j])
                    }
                    path.addLine(to: pts[pts.count - 1])

                    context.opacity = 0.20 + 0.42 * swell
                    context.stroke(path, with: .color(.black),
                                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .ignoresSafeArea()
        .drawingGroup()
    }
}

// MARK: - The feed

/// One rail, a marker per entry, and the content is the whole row.
private struct Feed: View {
    let notes: [Note]
    let palette: Palette

    private static let railX: CGFloat = 4
    /// 38, not 26. "12/26" at 9.5pt mono needs about 30 points, and the date has to clear the
    /// rail without touching the content column.
    private static let gutter: CGFloat = 38

    /// Low frequency on purpose. A date on every entry is what made the earlier column read as a
    /// log rather than as a page; a date nowhere leaves a long folder with nothing to orient by.
    private func week(_ date: Date) -> String {
        let days = Date.now.timeIntervalSince(date) / 86_400
        return switch days {
        case ..<7:  "THIS WEEK"
        case ..<14: "LAST WEEK"
        case ..<21: "TWO WEEKS AGO"
        case ..<35: "LAST MONTH"
        default:    "EARLIER"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.uuid) { i, note in
                let label = week(note.timestamp)
                if i == 0 || label != week(notes[i - 1].timestamp) {
                    marker(label)
                }
                // The date replaces the dot on the first entry of each day, and only there. Every
                // entry is dated by the one above it, no entry gets a row of its own, and the
                // content column is exactly where it was.
                Entry(note: note,
                      palette: palette,
                      gutter: Self.gutter,
                      date: i == 0 || !Calendar.current.isDate(note.timestamp,
                                                               inSameDayAs: notes[i - 1].timestamp)
                            ? Self.day.string(from: note.timestamp) : nil)
            }
        }
        .padding(.top, 30)
        .background(alignment: .leading) {
            // The rail itself, behind every entry so it never breaks between them.
            Rectangle()
                .fill(palette.rail)
                .frame(width: 1)
                .padding(.leading, Self.railX)
                .padding(.vertical, 4)
        }
    }

    /// "8/26". Slashed and unpadded, the way a date reads when it is a label rather than a field.
    /// "20 SEPTEMBER 2026" — the form a thought carries when it has a screen to itself.
    static let long: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private func marker(_ label: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .stroke(palette.rail, lineWidth: 1)
                .background(Circle().fill(palette.groundTo))
                .frame(width: 9, height: 9)
                .frame(width: Self.gutter, alignment: .leading)
            // Instrument Serif at full strength. As 9.5pt mono at 29% these read as a system
            // label; at full opacity in the display face they read as the page's own headings,
            // which is what they are — the only structure the feed has.
            Text(label)
                .font(StudyType.serif(21))
                .foregroundStyle(palette.ink)
        }
        .padding(.bottom, 22)
    }
}

/// A thought rendered as the thing it is. The marker is the only chrome.
private struct Entry: View {
    let note: Note
    let palette: Palette
    var gutter: CGFloat = 38
    /// Set on the first entry of a day; nil on every entry after it that day.
    var date: String?

    @State private var preview: PhotoPreview?

    private var kind: Kind {
        if !note.todoRowItems.isEmpty { .todo }
        else if note.isImageFil { .photo }
        else if note.isLinkFil { .link }
        else if !note.audioFilePath.isEmpty { .voice }
        else { .note }
    }
    private enum Kind { case todo, photo, link, voice, note }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if let date {
                    Text(date)
                        .font(Theme.dmMono(9.5))
                        .foregroundStyle(palette.accent)
                        .fixedSize()
                } else {
                    Circle().fill(palette.accent).frame(width: 9, height: 9)
                }
            }
            .frame(width: gutter, alignment: .leading)
            .padding(.top, kind == .todo ? 4 : 6)
            // The plate. This is what "the gradient frames the content" means: the ground is the
            // folder and the reading happens on near-white sitting in it.
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(palette.plate, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .padding(.bottom, 26)
        .fullScreenCover(item: $preview) { target in
            NativePhotoViewer(urls: target.urls, start: 0) { preview = nil }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .todo:
            // Each item is its own line with its own box. A fil's items stay together; another
            // fil's to-do is a separate entry further down the rail.
            VStack(alignment: .leading, spacing: 9) {
                ForEach(note.todoRowItems) { item in
                    HStack(alignment: .top, spacing: 9) {
                        TodoStatusCircle(isCompleted: item.done)
                            .frame(width: 16, height: 16)
                        Text(item.text)
                            .font(StudyType.sans(14.5))
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? palette.faint : palette.ink)
                    }
                }
            }

        case .photo:
            VStack(alignment: .leading, spacing: 9) {
                if let data = note.sortedImageFilImages.first?.data ?? note.imageData,
                   let image = UIImage(data: data) {
                    // Full width at the photograph's own aspect — no crop, no fixed box. A frame
                    // that letterboxes shows its own backing through the sides, and a fixed height
                    // with free width is not available here because the column IS the width.
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { preview = PhotoPreview(note: note) }
                }
                caption
            }

        case .voice:
            VStack(alignment: .leading, spacing: 9) {
                // The app's own compact waveform, which already takes a colour — so the folder's
                // tint reaches it without a second bar-drawing implementation.
                CompactWaveformView(duration: note.duration,
                                    color: palette.accent)
                // Plain, not a caption and not a card: a voice fil's words ARE the recording,
                // transcribed, rather than something written about it.
                text
            }

        case .link:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 11) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.accent)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(note.sourceTitle ?? note.sourceURLString ?? "")
                            .font(StudyType.sans(13, weight: .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(2)
                        if let host = note.sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") {
                            Text(host)
                                .font(Theme.dmMono(10.5))
                                .foregroundStyle(palette.soft)
                        }
                    }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.rail, lineWidth: 1))
            }

        case .note:
            // No card of its own any more: under Plate EVERY entry rides a plate, so a second
            // container around a note would be a box inside a box.
            text
        }
    }

    /// A photograph's own words, set apart from it: dimmer than a note and italic, so it reads as
    /// a caption rather than as a second thought under the picture.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.titleLine)
                .font(StudyType.sans(13.5))
                .italic()
                .foregroundStyle(palette.soft)
            if !note.bodyAfterTitle.isEmpty {
                Text(note.bodyAfterTitle)
                    .font(StudyType.sans(13))
                    .italic()
                    .foregroundStyle(palette.faint)
            }
        }
    }

    /// The model's own split, so this surface and the reader never disagree about what a fil's
    /// first line is.
    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.titleLine)
                .font(StudyType.sans(15, weight: .medium))
                .foregroundStyle(palette.ink)
            if !note.bodyAfterTitle.isEmpty {
                Text(note.bodyAfterTitle)
                    .font(StudyType.sans(13.5))
                    .foregroundStyle(palette.soft)
            }
        }
    }
}

// MARK: - The native photo viewer

/// A fil's photographs, written where QuickLook can reach them.
///
/// QuickLook reads files, not `Data`, so the bytes go to a temp directory first — the same thing
/// `ArticleView.openImageFilPreview` does, and for the same reason.
struct PhotoPreview: Identifiable {
    let id: UUID
    let urls: [URL]

    init(note: Note) {
        id = note.uuid
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fil-image-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let images = note.sortedImageFilImages.map(\.data).isEmpty
            ? [note.imageData].compactMap { $0 }
            : note.sortedImageFilImages.map(\.data)
        urls = images.enumerated().compactMap { i, data in
            let url = dir.appendingPathComponent("study-\(note.uuid.uuidString)-\(i).jpg")
            guard (try? data.write(to: url)) != nil else { return nil }
            return url
        }
    }
}

/// Apple's own previewer, with editing off.
///
/// **What this answers:** how much of the native viewer we control. `.quickLookPreview($url, in:)`
/// is one line and already ships in `ArticleView.swift:230`, but it is a SwiftUI shim with no
/// delegate hook — so it always carries Markup. Driving `QLPreviewController` directly costs this
/// wrapper and buys the delegate, where `editingModeFor` returning `.disabled` takes the Markup
/// affordance away. Everything else Apple gives stays: pinch and double-tap zoom, pan, the share
/// sheet, and swiping between a fil's photographs.
///
/// Unverified until seen on device: that `.disabled` removes the control rather than only refusing
/// the edit. It is the documented meaning, but it is a claim about a system UI and should be looked
/// at before it is relied on.
struct NativePhotoViewer: UIViewControllerRepresentable {
    let urls: [URL]
    let start: Int
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.currentPreviewItemIndex = start
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.close))
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var parent: NativePhotoViewer
        init(parent: NativePhotoViewer) { self.parent = parent }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { parent.urls.count }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            parent.urls[index] as NSURL
        }

        /// The whole reason this is not the one-line modifier.
        func previewController(_ controller: QLPreviewController,
                               editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
            .disabled
        }

        @objc func close() { parent.onClose() }
    }
}

// MARK: - The chrome that survives a swipe

/// The Bin, present on every page. The word for this is the dock, not a toast: a toast is
/// transient by definition and this never leaves.
private struct Dock: View {
    let bin: Int
    let palette: Palette
    /// "plates", "glass", "white" or "scrim".
    let style: String

    /// Glass takes ink like a plate does — it is a light surface, not a dark one — so the two
    /// share every colour decision and differ only in what draws the surface.
    private var onLight: Bool { false }   // white chrome, settled 2026-09-28

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(onLight ? palette.rail : .white.opacity(0.32))
                .frame(width: 30, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Bin").font(StudyType.sans(13, weight: .semibold))
                Text("\(bin)")
                    .font(Theme.dmMono(10))
                    .foregroundStyle(onLight ? palette.soft : .white.opacity(0.7))
            }
        }
        .foregroundStyle(onLight ? palette.ink : .white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            if style == "plates" {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(palette.plate)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(palette.rail, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
            }
        }
        // The app's own glass, the same call `DockChipLabel` and the composer dock already make.
        // `.identity` rather than a conditional modifier, so the view tree is the same shape in
        // every variant and switching cannot re-identify it.
        .glassEffect(style == "glass" ? .regular : .identity,
                     in: .rect(cornerRadius: 26))
        // White marks carry their own shadow instead of a plate, which is the whole of that
        // variant: one treatment nothing else on the page uses, in exchange for no container.
        .shadow(color: style == "white" ? .black.opacity(0.45) : .clear, radius: 7, y: 2)
    }
}

/// Where you are in the run, and how to get somewhere else quickly.
///
/// The pin marks page one, which is the pinned folder — with the dock holding only the Bin, nothing
/// else on screen says so. The row scrubs under a drag, which is the gesture the iOS home screen's
/// indicator actually has; `minimumDistance: 0` so it engages on touch, and the hit area is padded
/// well past the dots, which are 6 points wide and unlandable otherwise.
private struct PageDots: View {
    let count: Int
    @Binding var index: Int
    var pinnedIndex: Int?
    let palette: Palette
    let style: String

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { i in
                    Group {
                        if i == pinnedIndex {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                // Upright: the symbol leans, and a leaning pin among circles reads
                                // as a mistake rather than as a mark.
                                .rotationEffect(.degrees(45))
                        } else {
                            Circle().frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(style == "plates" || style == "glass"
                                     ? (i == index ? palette.ink : palette.ink.opacity(0.3))
                                     : .white.opacity(i == index ? 0.98 : 0.42))
                    .frame(width: 12)
                }
            }
            .padding(.horizontal, style == "plates" || style == "glass" ? 12 : 0)
            .padding(.vertical, style == "plates" || style == "glass" ? 6 : 0)
            .background {
                if style == "plates" {
                    Capsule().fill(palette.plate)
                        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
                }
            }
            .glassEffect(style == "glass" ? .regular : .identity, in: .capsule)
            .shadow(color: style == "white" ? .black.opacity(0.45) : .clear, radius: 5, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let row = CGFloat(count) * 13
                        let start = (geo.size.width - row) / 2
                        let slot = Int(((value.location.x - start) / row) * CGFloat(count))
                        let clamped = max(0, min(count - 1, slot))
                        guard clamped != index else { return }
                        Haptics.selection()
                        index = clamped
                    }
            )
        }
        .frame(height: 30)
        .animation(.snappy, value: index)
    }
}
#endif
