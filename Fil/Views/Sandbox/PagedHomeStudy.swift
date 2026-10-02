//  PagedHomeStudy.swift
//  Fil — Debug design sandbox
//
//  The paged home as it stands after the 2026-09-28/30 arc: folders page DOWN, one cover per
//  folder on its own ground; a tap opens the folder's nest as a pushed screen. What renders is
//  `CoverPage`, `NestScreen`/`Nest`, `FolderRail`, `Palette` and `FolderGround`.
//
//  The earlier directions this file carried — a timeline feed, a kinetic-lines cover, a full-
//  screen thought, a dock and dot row — were deleted on 2026-09-30 with zero call sites. Their
//  record is archive/2026-09-28-paged-home/why.md; their code is in git before a7fb048.
//
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
    /// Axis A: the cover summary's voice — "casual" or "warm".
    let variant: String
    /// Axis B: the nest's chrome — "paper", "glass" or "line".
    let line: String
    /// "transport", "bin" or "folder" — what the bottom bar carries.
    var stressed: Bool

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)])
    private var folders: [Folder]
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var notes: [Note]

    @State private var folderIndex = 0
    @State private var folderID: Int? = 0
    /// The folder whose nest is open, pushed as its own screen. Nothing else on this page
    /// changes while it is; the pager is simply underneath.
    @State private var opened: Folder?

    private var pinned: Folder? { folders.first { PinnedFolderStore.shared.isPinned($0.id) } }

    /// Real folders, and at the stressed setting the same folders repeated to twelve — which keeps
    /// the longest title, the empty summary and the folder with no fils in the sample.
    private var pool: [Folder] {
        guard stressed, !folders.isEmpty else { return folders }
        return (0..<12).map { folders[$0 % folders.count] }
    }

    private var pages: [Folder] {
        let rest = pool.filter { $0.id != pinned?.id }
        guard let pinned else { return rest }
        return [pinned] + rest
    }

    var body: some View {
        // A NavigationStack so a folder can be OPENED rather than paged into. The nest is pushed
        // with the system's own slide and returns from a drawn back control — the same horizontal
        // step, owned by the framework instead of a page controller.
        NavigationStack {
        ZStack {
            // Behind everything and never moved: the current folder's palette, full bleed, under
            // the pager. The pushed nest brings its own `FolderGround`.
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
                // Folders page DOWN. A tap on a cover opens its nest as a pushed screen over this
                // pager, so the vertical axis only ever means folders here — nothing on this page
                // competes with the scroll.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { i, folder in
                            CoverPage(folder: folder) { opened = folder }
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(i)
                                .onAppear { folderIndex = i }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $folderID)
                // `.container`, not the bare form — see SandboxRoute. The bare form also ignores
                // the keyboard region, and the NavigationStack this sits in needs that region
                // alive so the pushed nest can shrink above the keyboard. All container edges:
                // pages must be full height or the next folder's ground shows in a strip under
                // the current cover. The cover's control and the composer add the home
                // indicator's inset back through `homeInset`.
                .ignoresSafeArea(.container)
                .onChange(of: folderID) { _, new in folderIndex = new ?? 0 }
                .overlay(alignment: .trailing) {
                    FolderRail(count: pages.count,
                               index: Binding(get: { folderID ?? 0 }, set: { folderID = $0 }))
                }
            }

        }
        .navigationDestination(item: $opened) { NestScreen(folder: $0) }
        .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.summaryVoice, variant)
        // On the NavigationStack, not the ZStack inside it. A pushed destination inherits its
        // environment from the stack, so a value set on the pager never reached the nest — both
        // bubble chips rendered the default and looked identical.
    }
}
// MARK: - The folder rail

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
#endif
