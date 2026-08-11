import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The folder browser's page background: `Theme.background` nudged toward the primary color so it
/// reads as the same soft gray as the blurred header. The blur lifts much more over black than over
/// white, so dark mode needs a bigger nudge to match.
struct FolderBrowserBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Theme.background
            .overlay(Theme.primaryText.opacity(scheme == .dark ? 0.15 : 0.05))
            .ignoresSafeArea()
    }
}

/// A Lock Screen / widget tap destination the home should route to on launch.
enum HomeDeepLink: Equatable {
    /// Show the Bin (pop to the folders root, where the Bin dock is visible).
    case bin
    /// Open a specific folder's interior.
    case folder(UUID)
}

/// The folders surface, embedded inline on the home below the compose bar (no longer a modal).
/// Free: manual filing — create folders, rename/move fils, landfil. Pro: "smart organize" via Claude.
/// Tapping a folder pushes its typed-container interior; ＋ / ✨ ride in a compact header row.
struct FoldersHomeSection: View {
    /// Bottom scroll inset so content clears the floating composer dock (measured by CanvasHome).
    var bottomInset: CGFloat = 120
    /// Reports the currently-open folder (nil at the root), so the home can hide its floating header
    /// and make the composer contextual ("add to {folder}").
    var onContextFolderChange: (Folder?) -> Void = { _ in }
    /// A pending deep-link target (from the Lock Screen widget). Consumed once routed, then cleared.
    @Binding var deepLink: HomeDeepLink?
    /// Set true by the composer's ＋ / ✨ to open the new-folder popup / run smart-organize; reset here.
    @Binding var newFolderRequest: Bool
    @Binding var organizeRequest: Bool

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)]) private var folders: [Folder]
    @Query private var allNotes: [Note]
    @Environment(\.modelContext) private var context

    /// The folder a drag is currently over (drop highlight).
    @State private var targetedFolderID: UUID?

    @State private var path: [Route] = []
    @State private var pagerSelection: FilPagerSelection?
    @State private var isSummarizing = false   // a pinned-folder summary is being generated (drives the skeleton)
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderCaption = ""
    @State private var pendingMoveNote: Note?

    @State private var pendingRenameFolder: Folder?
    @State private var renameFolderText = ""
    @State private var renameFolderCaption = ""
    @State private var pendingLandfilFolder: Folder?

    @State private var showPaywall = false
    @State private var organizing = false
    @State private var organizeError: String?

    @AppStorage("prefersLowercase") private var prefersLowercase = false

    private func cased(_ text: String) -> String { prefersLowercase ? text.lowercased() : text }

    private func pullHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    enum Route: Hashable {
        case folder(Folder)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    // Home hero: the pinned folder as a 3D object (scrolls with the list). A soft
                    // placeholder invites pinning when nothing is featured yet.
                    PinnedFolderHero(model: pinnedHeroModel,
                                     placeholderText: cased("Pin a folder to feature it here")) {
                        if let folder = pinnedFolder { path.append(.folder(folder)) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 24, trailing: 20))
                }

                Section {
                    if folders.isEmpty {
                        Text("No folders yet. Tap ＋ to make one.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.tertiaryText)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(folders) { folder in
                        Button { path.append(.folder(folder)) } label: {
                            listRow(seed: seed(for: folder), start: folder.gradientStartHex, end: folder.gradientEndHex,
                                    glyph: nil, title: folder.name, trailing: "\(folder.notes.count)", caption: folder.summary)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(targetedFolderID == folder.id ? Theme.primaryText.opacity(0.10) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        // Native swipe actions (back by request) + a drop target for a dragged card.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // Live Activity is the fast full-swipe action (like Select on fil cards).
                            let pinned = PinnedFolderStore.shared.isPinned(folder.id)
                            Button { togglePin(folder) } label: {
                                Label(pinned ? "Remove" : "Live Activity", systemImage: pinned ? "pin.slash" : "pin")
                            }
                            .tint(.indigo)
                            Button { startRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.blue)
                            // Plain (not destructive) so the row doesn't animate out before confirming.
                            Button { pendingLandfilFolder = folder } label: {
                                Label("Landfil", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, on: folder)
                        } isTargeted: { targeted in
                            if targeted { targetedFolderID = folder.id }
                            else if targetedFolderID == folder.id { targetedFolderID = nil }
                        }
                    }
                    .onMove(perform: moveFolders)   // long-press a folder to drag-reorder
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)   // clear the floating composer dock
            .background(FolderBrowserBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: path) { _, newPath in
                if case let .folder(folder) = newPath.last { onContextFolderChange(folder) }
                else { onContextFolderChange(nil) }
            }
            .onAppear { normalizeFolderOrder(); applyDeepLink() }
            .task(id: pinnedSummaryTaskID) { await refreshPinnedSummaryIfNeeded() }
            .onChange(of: newFolderRequest) { _, req in
                if req { pendingMoveNote = nil; showNewFolder = true; newFolderRequest = false }
            }
            .onChange(of: organizeRequest) { _, req in
                if req { organize(); organizeRequest = false }
            }
            .onChange(of: deepLink) { _, _ in applyDeepLink() }
            .onChange(of: folders.map(\.id)) { _, _ in applyDeepLink() }   // retry once folders load (cold launch)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let folder):
                    interior(title: folder.name, summary: folder.summary, seed: seed(for: folder), start: folder.gradientStartHex,
                             end: folder.gradientEndHex, glyph: nil, notes: folder.notes, folder: folder)
                }
            }
        }
        .tint(Theme.primaryText)
        .sheet(item: $pagerSelection) { sel in BrowserFilPager(notes: sel.notes, startID: sel.startID) }
        // Close the pager if any fil it's paging gets landfil'd (from within its own modal or a swipe).
        .onChange(of: allNotes.map(\.uuid)) { _, ids in
            let live = Set(ids)
            if let pager = pagerSelection, !pager.noteIDs.allSatisfy({ live.contains($0) }) { pagerSelection = nil }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("name", text: $newFolderName)
            TextField("caption (optional)", text: $newFolderCaption)
            Button("Create") { createFolderFromPrompt() }
            Button("Cancel", role: .cancel) { newFolderName = ""; newFolderCaption = ""; pendingMoveNote = nil }
        }
        .alert("Rename folder", isPresented: .init(
            get: { pendingRenameFolder != nil },
            set: { if !$0 { pendingRenameFolder = nil } }
        )) {
            TextField("name", text: $renameFolderText)
            TextField("caption (optional)", text: $renameFolderCaption)
            Button("Save") { commitFolderRename() }
            Button("Cancel", role: .cancel) { pendingRenameFolder = nil }
        }
        .landfilConfirmation(item: $pendingLandfilFolder, message: { _ in
            "This folder is removed. Its fils return to the deck."
        }, onConfirm: { folder in delete(folder) })
        .alert("Couldn't organize", isPresented: .init(
            get: { organizeError != nil },
            set: { if !$0 { organizeError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(organizeError ?? "")
        }
        .overlay {
            if organizing {
                ProgressView("organizing…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    /// Routes a pending Lock Screen deep link: the Bin pops to the folders root; a folder opens its
    /// interior. A folder id that isn't loaded yet is left pending — the `folders` onChange retries.
    private func applyDeepLink() {
        guard let link = deepLink else { return }
        switch link {
        case .bin:
            if !path.isEmpty { path = [] }
            deepLink = nil
        case .folder(let id):
            guard let folder = folders.first(where: { $0.id == id }) else { return }
            path = [.folder(folder)]
            deepLink = nil
        }
    }

    private func interior(title: String, summary: String, seed: Double, start: String, end: String, glyph: String?, notes: [Note], folder: Folder?) -> some View {
        FolderInteriorView(
            title: title, summary: summary, seed: seed, start: start, end: end, glyph: glyph, notes: notes, folders: folders, folder: folder,
            bottomInset: bottomInset,
            onOpen: { note, items in pagerSelection = FilPagerSelection(notes: items, startID: note.uuid) },
            onMove: { note, folder in move(note, to: folder) },
            onNewFolder: { note in pendingMoveNote = note; showNewFolder = true }
        )
    }

    // MARK: - Drag & drop (file a card / reorder folders)

    private func handleDrop(_ items: [String], on folder: Folder) -> Bool {
        defer { targetedFolderID = nil }
        guard let payload = items.first, payload.hasPrefix("card:"),
              let id = UUID(uuidString: String(payload.dropFirst(5))),
              let note = allNotes.first(where: { $0.uuid == id }) else { return false }
        move(note, to: folder)                  // file the dragged card into this folder
        FilSelectionStore.shared.remove(id)     // if it came from the selection, it's filed now
        pullHaptic()
        return true
    }

    /// List long-press drag-reorder: renumber sortIndex to the new order.
    private func moveFolders(from source: IndexSet, to destination: Int) {
        var ordered = folders
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() { folder.sortIndex = index }
        try? context.save()
    }

    /// First load after adding `sortIndex`: everything is 0 → seed the order by createdAt (newest first).
    private func normalizeFolderOrder() {
        guard folders.count > 1, folders.allSatisfy({ $0.sortIndex == 0 }) else { return }
        let ordered = folders.sorted { $0.createdAt > $1.createdAt }
        for (i, folder) in ordered.enumerated() { folder.sortIndex = i }
        try? context.save()
    }

    private func listRow(seed: Double, start: String, end: String, glyph: String?, title: String, trailing: String? = nil, caption: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            FolderMark(seed: seed, start: start, end: end, glyph: glyph)
            VStack(alignment: .leading, spacing: 3) {
                Text(cased(title)).font(Theme.instrumentSerif(22)).foregroundStyle(Theme.primaryText).lineLimit(1)
                if let caption, !caption.isEmpty {
                    Text(cased(caption))
                        .font(Theme.fredoka(12, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Manual writes (free)

    private func createFolderFromPrompt() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = newFolderCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""; newFolderCaption = ""
        guard !name.isEmpty else { pendingMoveNote = nil; return }

        let folder = makeFolder(named: name)
        folder.summary = caption
        if let note = pendingMoveNote { note.folder = folder; note.sortIndex = 0 }
        pendingMoveNote = nil
        try? context.save()
    }

    private func startRename(_ folder: Folder) {
        renameFolderText = folder.name
        renameFolderCaption = folder.summary
        pendingRenameFolder = folder
    }

    private func commitFolderRename() {
        let name = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = pendingRenameFolder, !name.isEmpty {
            folder.name = name
            folder.summary = renameFolderCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            try? context.save()
        }
        pendingRenameFolder = nil
    }

    private func move(_ note: Note, to folder: Folder?) {
        note.folder = folder
        note.sortIndex = 0   // order is per-folder; reset so it joins the destination at the top
        try? context.save()
    }

    private func delete(_ folder: Folder) {
        if PinnedFolderStore.shared.isPinned(folder.id) {
            PinnedFolderStore.shared.unpin()
            Task { await PinnedFolderLiveActivityController.unpin() }
        }
        context.delete(folder)   // .nullify → its fils fall back to the unfiled deck
        try? context.save()
    }

    /// Pin a folder to the Lock Screen widget (or unpin it). Pinning also flips the Lock Screen
    /// setting to Folder so the activity actually shows; unpinning turns it off. The coordinator
    /// builds/refreshes the snapshot from the folder's live contents.
    private func togglePin(_ folder: Folder) {
        SoundscapeManager.shared.playTabSound()
        if PinnedFolderStore.shared.isPinned(folder.id) {
            PinnedFolderStore.shared.unpin()
            UserDefaults.filAppGroup.set(LockScreenActivity.off.rawValue, forKey: LockScreenActivity.storageKey)
        } else {
            let newest = folder.notes.sorted { $0.timestamp > $1.timestamp }
            let blobs = newest.prefix(8).map { $0.activityBlob }
            PinnedFolderStore.shared.pin(
                id: folder.id,
                name: cased(folder.name),
                count: folder.notes.count,
                blobs: Array(blobs),
                gradientStartHex: folder.gradientStartHex,
                gradientEndHex: folder.gradientEndHex
            )
            UserDefaults.filAppGroup.set(LockScreenActivity.pinnedFolder.rawValue, forKey: LockScreenActivity.storageKey)
        }
        Task { await LockScreenActivityCoordinator.sync(modelContext: context) }
    }

    /// New folders draw a gradient from the full range the fils use.
    private func makeFolder(named name: String) -> Folder {
        let pair = Theme.randomGradientPair()
        let nextIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        let folder = Folder(name: name, gradientStartHex: pair.start, gradientEndHex: pair.end, sortIndex: nextIndex)
        context.insert(folder)
        return folder
    }

    private func seed(for folder: Folder) -> Double {
        let hash = folder.id.uuidString.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return Double(hash % 10_000) / 10_000
    }

    /// The currently-pinned folder resolved from the live query (reactive via @Observable store).
    private var pinnedFolder: Folder? {
        guard let id = PinnedFolderStore.shared.pinnedFolderID else { return nil }
        return folders.first { $0.id == id }
    }

    /// Display model for the hero (nil → the placeholder state).
    private var pinnedHeroModel: PinnedFolderHero.Model? {
        guard let folder = pinnedFolder else { return nil }
        let fils = folder.notes.prefix(6).map {
            HeroFil(start: $0.gradientStartHex, end: $0.gradientEndHex, seed: $0.blobShapeSeed)
        }
        return .init(title: cased(folder.name), start: folder.gradientStartHex,
                     end: folder.gradientEndHex, seed: seed(for: folder), count: folder.notes.count,
                     parts: heroParts(folder), loadingSummary: isSummarizing, fils: fils)
    }

    /// Stamp snippets for the hero: the Pro-generated parts, or — free tier / before generation —
    /// the organize caption split into a couple of short fragments (no API).
    private func heroParts(_ folder: Folder) -> [String] {
        if !folder.summaryParts.isEmpty { return folder.summaryParts.map(cased) }
        let caption = folder.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caption.isEmpty else { return [] }
        let sentences = caption
            .replacingOccurrences(of: ". ", with: ".\n")
            .split(separator: "\n")
            .map { cased($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        return Array(sentences.prefix(3))
    }

    /// The pinned folder's content state — fil count + newest timestamp. Changes when a fil is
    /// added/removed/refiled, which is when the summary is worth regenerating.
    private func contentSignature(_ folder: Folder) -> String {
        let newest = folder.notes.map(\.timestamp).max() ?? .distantPast
        return "\(folder.notes.count)|\(newest.timeIntervalSince1970)"
    }

    /// Re-runs the summary generation when the pinned folder (or its contents) changes.
    private var pinnedSummaryTaskID: String {
        guard let folder = pinnedFolder else { return "none" }
        return "\(folder.id.uuidString)|\(contentSignature(folder))"
    }

    /// Regenerate the featured folder's summary — Pro only, and only when the cached signature is
    /// stale, so it's one call per meaningful change. Free tier keeps whatever caption it already has.
    private func refreshPinnedSummaryIfNeeded() async {
        guard StoreManager.shared.isPro,
              let folder = pinnedFolder,
              !folder.notes.isEmpty else { return }
        let signature = contentSignature(folder)
        // Regenerate when the contents changed OR when we don't yet have snippet parts (e.g. a folder
        // summarized before parts existed). Once parts are written for the current signature, both fail.
        guard folder.summaryParts.isEmpty || signature != folder.summarySignature else { return }

        isSummarizing = true
        defer { isSummarizing = false }

        let inputs = folder.notes.map { note in
            FilClusterInput(
                id: note.uuid,
                text: String((note.transcript.isEmpty ? note.title : note.transcript).prefix(240)),
                keyword: note.displayBadgeText
            )
        }
        let txn = StoreManager.shared.proTransactionID ?? ""
        guard let parts = try? await ClaudeSurfacingService.shared.folderSnippets(fils: inputs, transactionID: txn),
              !parts.isEmpty else { return }

        folder.summaryParts = parts
        folder.summarySignature = signature
        try? context.save()
    }

    // MARK: - Smart organize (Pro)

    private func organize() {
        guard !organizing else { return }
        guard StoreManager.shared.isPro else { showPaywall = true; return }
        // Reorganize the whole library, not just the Bin — Claude regroups everything.
        let targets = Array(allNotes.prefix(200))
        guard !targets.isEmpty else { return }

        let inputs = targets.map { note in
            FilClusterInput(
                id: note.uuid,
                text: String((note.transcript.isEmpty ? note.title : note.transcript).prefix(240)),
                keyword: note.displayBadgeText
            )
        }
        let txn = StoreManager.shared.proTransactionID ?? ""

        organizing = true
        Task {
            do {
                let groups = try await ClaudeSurfacingService.shared.organize(fils: inputs, transactionID: txn)
                apply(groups, targets: targets)
            } catch {
                organizeError = (error as? ClaudeSurfacingService.SurfacingError)?.errorDescription ?? error.localizedDescription
            }
            organizing = false
        }
    }

    private func apply(_ groups: [ClaudeSurfacingService.OrganizedFolder], targets: [Note]) {
        let byID = Dictionary(targets.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        // Fetch fresh so name-matching sees folders created earlier in this same pass.
        var existing = (try? context.fetch(FetchDescriptor<Folder>())) ?? Array(folders)
        for group in groups {
            let folder: Folder
            if let match = existing.first(where: { $0.name.lowercased() == group.name.lowercased() }) {
                folder = match
                folder.name = group.name        // refresh to the model's Title Case
            } else {
                let made = makeFolder(named: group.name)
                existing.append(made)
                folder = made
            }
            folder.summary = group.summary
            for id in group.filIDs { byID[id]?.folder = folder; byID[id]?.sortIndex = 0 }
        }
        // A re-organize can empty out old folders — remove any leftovers so none linger empty.
        for folder in existing where folder.notes.isEmpty {
            context.delete(folder)
        }
        try? context.save()
    }
}

/// A real folder's interior: Finder-legible rows whose leading icon is the authentic 36pt fil chip,
/// tappable to open the fil, swipe for rename / move / landfil. Header blob matches the folder.
struct FolderInteriorView: View {
    let title: String
    let summary: String
    let seed: Double
    let start: String
    let end: String
    var glyph: String? = nil
    let notes: [Note]
    let folders: [Folder]
    /// The folder this interior represents (nil for the Bin) — new fils are filed straight into it.
    var folder: Folder?
    /// Bottom scroll inset so content clears the floating composer dock.
    var bottomInset: CGFloat = 120
    /// Opens a fil; the second argument is the ordered container it belongs to, for left/right paging.
    var onOpen: (Note, [Note]) -> Void
    var onMove: (Note, Folder?) -> Void
    var onNewFolder: (Note) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("prefersLowercase") private var prefersLowercase = false
    private let selection = FilSelectionStore.shared

    @State private var moveTargetNote: Note?
    @State private var pendingLandfilNote: Note?
    @State private var playerSelection: FilPagerSelection?


    // Typed containers. To-dos are claimed first (any fil with a to-do lives there and nowhere else);
    // the rest split by kind. Each bucket is in manual order (sortIndex), newest-first for ties.
    private func hasTodos(_ note: Note) -> Bool { !note.todoRowItems.isEmpty }
    /// Manual position, then newest-first tiebreak — so an un-reordered folder reads newest-first.
    private func inFolderOrder(_ a: Note, _ b: Note) -> Bool {
        a.sortIndex != b.sortIndex ? a.sortIndex < b.sortIndex : a.timestamp > b.timestamp
    }

    private var todoNotes: [Note] { notes.filter(hasTodos).sorted(by: inFolderOrder) }
    private var rest: [Note] { notes.filter { !hasTodos($0) } }
    /// The Full Screen player deck: every non-link fil, in the order the sections read top-to-bottom.
    private var playerDeck: [Note] { todoNotes + photoNotes + plainNotes + voiceNotes + linkNotes }
    private var photoNotes: [Note] { rest.filter { $0.isImageFil }.sorted(by: inFolderOrder) }
    private var linkNotes: [Note] { rest.filter { $0.isLinkFil }.sorted(by: inFolderOrder) }
    private var voiceNotes: [Note] { rest.filter { !$0.isImageFil && !$0.isLinkFil && !$0.audioFilePath.isEmpty }.sorted(by: inFolderOrder) }
    private var plainNotes: [Note] { rest.filter { !$0.isImageFil && !$0.isLinkFil && $0.audioFilePath.isEmpty }.sorted(by: inFolderOrder) }

    private func cased(_ text: String) -> String { prefersLowercase ? text.lowercased() : text }

    var body: some View {
        // Sections are reorderable Lists: long-press-drag a card to reorder within its type
        // (like folders). Swipe leading to select, trailing for rename / move / landfil.
        List {
            todoSection
            filSection("Photos", "photo", photoNotes)
            filSection("Notes", "note.text", plainNotes)
            filSection("Links", "link", linkNotes)
            filSection("Voice", "waveform", voiceNotes)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)   // clear the floating composer dock
        .background(FolderBrowserBackground())
        // Native large-title collapse: the expanded identity (blob + Instrument Serif title + count)
        // sits below the bar with the caption; on scroll it collapses to the compact inline identity.
        // `.toolbarTitleDisplayMode(.large)` is what drives the collapse (and stops the large + inline
        // titles rendering at once). The folders root hides its bar, so force it visible here.
        .navigationTitle(cased(title))
        .toolbarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .largeTitle) { folderIdentity }
        }
        // Creating a fil here happens through the contextual composer bar ("add to {folder}"), not a
        // per-folder ＋. The folder switcher lives in the composer's FAB slot (replaces new-folder).
        .confirmationDialog("Move to a folder", isPresented: .init(
            get: { moveTargetNote != nil },
            set: { if !$0 { moveTargetNote = nil } }
        ), titleVisibility: .visible, presenting: moveTargetNote) { note in
            ForEach(folders.filter { $0.id != note.folder?.id }) { folder in
                Button(cased(folder.name)) { onMove(note, folder) }
            }
            Button("New folder…") { onNewFolder(note) }
            if note.folder != nil {
                Button("Remove from folder", role: .destructive) { onMove(note, nil) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .landfilConfirmation(item: $pendingLandfilNote, message: { _ in
            "This thought will be deleted. This cannot be undone."
        }, onConfirm: { note in
            FilLandfil.cleanUpResources(for: note)
            context.delete(note)
            try? context.save()
        })
        .sheet(item: $playerSelection) { sel in
            FilFullScreenPlayer(notes: sel.notes, startID: sel.startID) { playerSelection = nil }
        }
    }

    /// The folder identity for the large-title slot — mirrors the original header layout: blob on the
    /// left; title + count on line one and the caption on line two, stacked to the right of the blob so
    /// the caption's left edge lines up with the title. Collapses to the native inline title on scroll.
    private var folderIdentity: some View {
        HStack(spacing: 14) {
            FolderMark(seed: seed, start: start, end: end, glyph: glyph, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(cased(title))
                        .font(Theme.instrumentSerif(28))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(notes.count)")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
                }
                if !summary.isEmpty {
                    Text(cased(summary))
                        .font(Theme.fredoka(13, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30)   // separate the identity from the nav bar
    }

    // MARK: - Containers

    /// A type container header: an icon + serif label + a count chip.
    private func containerHeader(_ label: String, _ icon: String, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Text(label).font(Theme.instrumentSerif(22)).foregroundStyle(Theme.primaryText)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
            Spacer()
        }
        // No internal horizontal padding — the List's default section-header inset positions it,
        // matching the home "Folders" header.
    }

    /// One type's fils as a reorderable List section of full-width cards. Long-press-drag reorders
    /// (persisted to `sortIndex`); swipe leading to select, trailing for rename / move / landfil.
    @ViewBuilder private func filSection(_ label: String, _ icon: String, _ items: [Note]) -> some View {
        if !items.isEmpty {
            Section {
                // Header as a scrolling row (not the pinning `header:` slot) so it doesn't stick to the
                // nav bar on scroll.
                containerHeader(label, icon, items.count)
                    .textCase(nil)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 4, trailing: 20))
                ForEach(items, id: \.uuid) { note in
                    cardRow(filRow(note), note: note, container: items)
                }
                .onMove { reorder(items, from: $0, to: $1) }
            }
        }
    }

    /// Shared per-row chrome: selected overlay, tap-to-open, and the leading/trailing swipe actions.
    private func cardRow<Card: View>(_ card: Card, note: Note, container: [Note]) -> some View {
        card
            .overlay(alignment: .topTrailing) {
                if isSelected(note) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(10)
                }
            }
            .opacity(isSelected(note) ? 0.6 : 1)
            .contentShape(Rectangle())
            // Tapping a fil opens the Full Screen player (the folder's default reader).
            .onTapGesture { playerSelection = FilPagerSelection(notes: playerDeck, startID: note.uuid) }
            // Swipe left: Select (full swipe selects), then Move / Landfil.
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { toggleSelect(note) } label: {
                    Label(isSelected(note) ? "Deselect" : "Select",
                          systemImage: isSelected(note) ? "checkmark.circle.fill" : "checkmark")
                }
                .tint(.green)
                Button { moveTargetNote = note } label: { Label("Move", systemImage: "folder") }.tint(.indigo)
                // Not role:.destructive — that plays the row-removal animation on swipe, before the
                // user confirms. Plain red button so the card only animates out on the real delete.
                Button { pendingLandfilNote = note } label: { Label("Landfil", systemImage: "trash") }
                    .tint(.red)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 16))
    }

    /// Persist a drag-reorder: rewrite the section's `sortIndex` to its new order (0…n).
    private func reorder(_ items: [Note], from source: IndexSet, to destination: Int) {
        var arr = items
        arr.move(fromOffsets: source, toOffset: destination)
        for (index, note) in arr.enumerated() { note.sortIndex = index }
        try? context.save()
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func isSelected(_ note: Note) -> Bool { selection.contains(note.uuid) }
    private func toggleSelect(_ note: Note) {
        withAnimation(.snappy) { selection.toggle(note.uuid) }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// The Full Screen player's exact wash: a plain diagonal 2-color gradient, zoomed and blurred into
    /// a soft low-contrast field, darkened. Clipped to the card by the row's `clipShape`.
    private func filWash(_ note: Note) -> some View {
        LinearGradient(colors: [Color(hex: note.gradientStartHex), Color(hex: note.gradientEndHex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .scaleEffect(3.5)
            .overlay(Color.black.opacity(0.44))
    }

    /// A full-width card row: the rich component (photo thumb / fil blob) on the left, light text right.
    private func filRow(_ note: Note) -> some View {
        let isPlainNote = !(note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty)
        // Plain notes and photos caption their date; typed fils keep their identity caption.
        let showsDate = isPlainNote || note.isImageFil
        let main = cased(cardContent(note))
        return HStack(alignment: .top, spacing: 14) {
            rowRich(note)
            VStack(alignment: .leading, spacing: 3) {
                // A captionless photo has no words — show only its date below the thumbnail.
                if !main.isEmpty {
                    Text(highlightedCardText(note, base: main))
                        .font(Theme.fredoka(15, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(30)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let caption = showsDate
                    ? cased(note.timestamp.formatted(date: .abbreviated, time: .omitted))
                    : cased(captionText(note))
                if !caption.isEmpty {
                    Text(caption).font(.system(size: 12, weight: .light)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A dark card tinted with the fil's gradient — enough color to feel like the fil, but kept
        // low so light text stays legible.
        .background { filWash(note) }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    /// The row's leading rich component. Photo thumbnails stretch to the card's height; the fil blob
    /// and link/voice markers stay fixed squares, top-aligned beside long notes.
    @ViewBuilder private func rowRich(_ note: Note) -> some View {
        if note.isImageFil {
            photoThumb(note)
                .frame(width: 52)
                .frame(minHeight: 52, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            filMarker(note, size: 48)
        }
    }

    @ViewBuilder private func photoThumb(_ note: Note) -> some View {
        if let data = note.sortedImageFilImages.first?.data, let image = Image(data: data) {
            image.resizable().scaledToFill()
        } else {
            Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed)
        }
    }

    /// A card's main text: plain notes and photos show their own words (no generated title); other
    /// typed fils (links, voice) show their identity.
    private func cardContent(_ note: Note) -> String {
        // Photos read like notes: their caption words on top, no title. Empty if the photo has none.
        if note.isImageFil { return note.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
        if note.isLinkFil || !note.audioFilePath.isEmpty { return displayTitle(note) }
        let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? displayTitle(note) : body
    }

    /// The fil marker: each fil's shape + color (a play glyph / favicon for voice / links).
    @ViewBuilder private func filMarker(_ note: Note, size: CGFloat) -> some View {
        Group {
            if note.isLinkFil || !note.audioFilePath.isEmpty {
                NoteCardView(note: note, cardHeight: size)
            } else {
                NoteBlobShape(seed: note.blobShapeSeed)
                    .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
            }
        }
        .frame(width: size, height: size)
    }

    // The To-dos section: one reorderable card per fil that has to-dos (styled like the note cards),
    // listing that fil's to-dos with an inline checkbox each.
    @ViewBuilder private var todoSection: some View {
        if !todoNotes.isEmpty {
            Section {
                // Header as a scrolling row so it doesn't pin to the nav bar on scroll.
                containerHeader("To-dos", "checklist", todoNotes.reduce(0) { $0 + $1.todoRowItems.count })
                    .textCase(nil)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 4, trailing: 20))
                ForEach(todoNotes, id: \.uuid) { note in
                    cardRow(todoCard(note), note: note, container: todoNotes)
                }
                .onMove { reorder(todoNotes, from: $0, to: $1) }
            }
        }
    }

    /// A fil's to-dos as a note-style card: blob left + gradient wash; each to-do is a checkbox +
    /// light text row on the right.
    private func todoCard(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Photos lead with their thumbnail (like the note cards); other fils show their blob.
            rowRich(note)
            VStack(alignment: .leading, spacing: 8) {
                // The fil's own thought, so the user sees what they typed above its to-dos.
                let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    Text(cased(body))
                        .font(Theme.fredoka(15, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(30)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(note.todoRowItems) { item in
                    Button { toggleTodo(note, at: item.index) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            TodoStatusCircle(isCompleted: item.done)
                            Text(cased(item.text))
                                .font(Theme.fredoka(15, weight: .light))
                                .foregroundStyle(.white)
                                .strikethrough(item.done, color: .white.opacity(0.5))
                                .opacity(item.done ? 0.6 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { filWash(note) }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    /// Toggle a to-do's completion, keeping `completedTodos` aligned with `todos` (mirrors ArticleView).
    private func toggleTodo(_ note: Note, at index: Int) {
        if note.completedTodos.count < note.todos.count {
            note.completedTodos.append(contentsOf: Array(repeating: false, count: note.todos.count - note.completedTodos.count))
        } else if note.completedTodos.count > note.todos.count {
            note.completedTodos = Array(note.completedTodos.prefix(note.todos.count))
        }
        guard note.completedTodos.indices.contains(index) else { return }
        SoundscapeManager.shared.playTodoArticleToggleSound()
        note.completedTodos[index].toggle()
        try? context.save()
    }

    // MARK: - Text helpers

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? note.displayBadgeText : trimmed
    }

    /// The card's main text with its filament keywords lit — same treatment as the reading view
    /// (Fredoka medium in the fil's lighter gradient color), so highlights read on the card too.
    private func highlightedCardText(_ note: Note, base: String) -> AttributedString {
        var attributed = AttributedString(base)
        let keywords = note.attachments.map(\.keyword)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !keywords.isEmpty else { return attributed }

        let color = Color(hex: lighterHex(note))
        for keyword in keywords {
            var start = attributed.startIndex
            while start < attributed.endIndex,
                  let range = attributed[start...].range(of: keyword, options: .caseInsensitive) {
                attributed[range].font = Theme.fredoka(15, weight: .medium)
                attributed[range].foregroundColor = color
                start = range.upperBound
            }
        }
        return attributed
    }

    /// The lighter of the fil's two gradient endpoints — the highlight tint (matches SelectableTextView).
    private func lighterHex(_ note: Note) -> String {
        Color(hex: note.gradientStartHex).luminance > Color(hex: note.gradientEndHex).luminance
            ? note.gradientStartHex : note.gradientEndHex
    }

    /// The caption line: a link's domain, a voice fil's duration, or — for a plain note — a preview
    /// of the note's own text so the row shows a glimpse of the content.
    private func captionText(_ note: Note) -> String {
        if note.isLinkFil { return note.sourceDomain ?? "link" }
        if !note.audioFilePath.isEmpty {
            let m = Int(note.duration) / 60, s = Int(note.duration) % 60
            return String(format: "%d:%02d", m, s)
        }
        let body = note.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? "note" : body
    }
}

/// Shared gradient blob for folders (and the Bin tray).
private struct FolderMark: View {
    let seed: Double
    let start: String
    let end: String
    var glyph: String? = nil
    var size: CGFloat = 40

    var body: some View {
        let points = Theme.gradientUnitPoints(seed: seed)
        let gradient = LinearGradient(colors: [Color(hex: start), Color(hex: end)], startPoint: points.start, endPoint: points.end)
        ZStack {
            if let glyph {
                // Bin / special marks keep the organic blob with a glyph.
                NoteBlobShape(seed: seed).fill(gradient)
                Image(systemName: glyph)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            } else {
                // Folders read as a folder silhouette (a container), distinct from fil blobs (content).
                FolderShape().fill(gradient)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The home hero: the pinned folder as a dimensional object, built on the same `FolderShape` +
/// gradient the folder blobs use (so it reads as the same folder, extruded and lit). Falls back to a
/// soft "pin a folder" placeholder when nothing is pinned.
/// One fil's look, for the little blobs that spill out of the folder when it opens.
struct HeroFil { let start: String; let end: String; let seed: Double }

/// A blob's animatable state as it spills out (no opacity — the cover hides it at rest).
private struct HeroBlobAnim { var x: CGFloat = 0; var y: CGFloat = 0; var scale: CGFloat = 0.3 }

/// Flight slots for the spilled fils (tuned for the 100pt hero folder). Each starts near the top-edge
/// extrusion (sx/sy — different spots along the lip, not one center) and bursts out to a wide,
/// uneven endpoint (dx/dy) so the spill reads scattered rather than symmetric.
private let heroBlobSlots: [(sx: CGFloat, sy: CGFloat, dx: CGFloat, dy: CGFloat, size: CGFloat, delay: Double)] = [
    (-28, -34, -92, -102, 50, 0.010),
    (  4, -46, -34, -156, 54, 0.034),
    (-10, -40,  40, -122, 46, 0.018),
    ( 24, -32,  94, -108, 40, 0.048),
]

struct PinnedFolderHero: View {
    struct Model {
        let title: String
        let start: String
        let end: String
        let seed: Double
        let count: Int
        /// Short summary fragments → the scattered stamp snippets. Empty shows nothing (or the loader).
        var parts: [String] = []
        /// True while the summary is being generated and no parts exist yet → show the skeleton loader.
        var loadingSummary: Bool = false
        /// The folder's own fils (colors + seeds) that spill out of the folder when it opens.
        var fils: [HeroFil] = []
    }

    let model: Model?
    var placeholderText: String = "Pin a folder to feature it here"
    var onOpen: () -> Void = {}

    @State private var bob = false
    @State private var lid: Double = 0        // the front cover's open angle (hinged at the base)
    @State private var blobTrigger = 0        // fires the fil-blob burst
    @State private var retract = false        // scales the spilled fils back out as the folder closes
    private let depth = 10
    private let size: CGFloat = 150

    var body: some View {
        Group {
            if let model { pinned(model) } else { placeholder }
        }
        .frame(maxWidth: .infinity)
        .onAppear { bob = true }
    }

    private func pinned(_ m: Model) -> some View {
        let points = Theme.gradientUnitPoints(seed: m.seed)
        let gradient = LinearGradient(colors: [Color(hex: m.start), Color(hex: m.end)],
                                      startPoint: points.start, endPoint: points.end)
        // No Button wrapper — the deck needs its own drag gesture. Tap the folder/title to open.
        return VStack(alignment: .center, spacing: 14) {
            // Title atop.
            HStack(alignment: .center, spacing: 8) {
                Text(m.title).font(Theme.instrumentSerif(26)).foregroundStyle(Theme.primaryText)
                Text("\(m.count)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.primaryText.opacity(0.08)))
            }
            .contentShape(Rectangle())
            .onTapGesture { openFolder() }

            // Folder + stamps aligned in one centered row.
            HStack(alignment: .center, spacing: 18) {
                folder(gradient, lidAngle: lid, fils: m.fils, blobTrigger: blobTrigger, retract: retract)
                    .frame(width: 100, height: 100)
                    .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 16)
                    .offset(y: bob ? -4 : 4)
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: bob)
                    .contentShape(Rectangle())
                    .onTapGesture { openFolder() }

                if !m.parts.isEmpty {
                    StampDeck(parts: m.parts, start: m.start, end: m.end, seed: m.seed)
                } else if m.loadingSummary {
                    summarySkeleton
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Two shimmering lines standing in for the summary while it generates.
    private var summarySkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonView(Capsule()).frame(height: 10)
            SkeletonView(Capsule()).frame(width: 120, height: 10)
        }
        .padding(.top, 2)
    }

    private func folder(_ gradient: LinearGradient, lidAngle: Double = 0,
                        fils: [HeroFil] = [], blobTrigger: Int = 0, retract: Bool = false) -> some View {
        ZStack {
            FolderShape().fill(Color(white: 0.97))   // inner paper, revealed as the lid lifts
            // Extruded thickness reads at the TOP edge (offsets up), so the front & back bottoms
            // coincide at the base and the lid hinges cleanly there.
            ForEach(0..<depth, id: \.self) { i in
                FolderShape().fill(gradient).brightness(-0.18).offset(y: -CGFloat(depth - i))
            }
            // The folder's fils sit inside, in front of the paper but BEHIND the cover, so they're
            // concealed at rest and spill up out of the folder when it opens.
            blobLayer(fils, trigger: blobTrigger, retract: retract)
            // Front cover — swings open from its BOTTOM edge (the top folds back).
            FolderShape()
                .fill(gradient)
                .overlay(
                    FolderShape().fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                                      startPoint: .top, endPoint: .center))
                )
                .rotation3DEffect(.degrees(lidAngle), axis: (x: 1, y: 0, z: 0),
                                  anchor: .bottom, perspective: 0.55)
        }
    }

    /// The spilled fils — real `NoteBlobShape` blobs in each fil's colors, bursting out on a snappy
    /// ease-in curve and scaling back away as the folder closes.
    private func blobLayer(_ fils: [HeroFil], trigger: Int, retract: Bool) -> some View {
        ForEach(Array(fils.prefix(heroBlobSlots.count).enumerated()), id: \.offset) { i, fil in
            let slot = heroBlobSlots[i]
            NoteBlobShape(seed: fil.seed)
                .fill(Theme.gradient(startHex: fil.start, endHex: fil.end, seed: fil.seed))
                .frame(width: slot.size, height: slot.size)
                // Starts at the top-edge extrusion (sx/sy), bursts out to a wide endpoint (dx/dy).
                .keyframeAnimator(initialValue: HeroBlobAnim(x: slot.sx, y: slot.sy), trigger: trigger) { content, v in
                    content.offset(x: v.x, y: v.y).scaleEffect(v.scale)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.3, duration: slot.delay)   // delays are all > 0 (no zero-duration keyframe)
                        SpringKeyframe(1.0, duration: 0.09)
                    }
                    KeyframeTrack(\.y) {
                        LinearKeyframe(slot.sy, duration: slot.delay)                          // hold at the lip
                        CubicKeyframe(slot.sy + (slot.dy - slot.sy) * 0.12, duration: 0.05)    // slow start
                        CubicKeyframe(slot.dy, duration: 0.13)                                 // shoot out
                    }
                    KeyframeTrack(\.x) {
                        LinearKeyframe(slot.sx, duration: slot.delay)
                        CubicKeyframe(slot.sx + (slot.dx - slot.sx) * 0.12, duration: 0.05)
                        CubicKeyframe(slot.dx, duration: 0.13)
                    }
                }
                .scaleEffect(retract ? 0 : 1)   // shrink away as the folder closes
        }
    }

    /// Lifts the cover open, spilling the folder's fils out, then navigates in. The close + retract
    /// happen off-screen so the hero is shut with its fils tucked away when we return.
    private func openFolder() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        retract = false
        blobTrigger += 1                                                          // spill the fils
        withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) { lid = 82 } // lid lifts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onOpen() }         // burst shown, then navigate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {                    // off-screen reset
            lid = 0
            retract = true
        }
    }

    private var placeholder: some View {
        // A ghosted version of the same 3D folder (band-free), so it previews what a pin will look like.
        let gray = LinearGradient(colors: [Theme.primaryText.opacity(0.16), Theme.primaryText.opacity(0.07)],
                                  startPoint: .top, endPoint: .bottom)
        return VStack(spacing: 16) {
            folder(gray)
                .frame(width: 110, height: 110)
                .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(0.85)
            Text(placeholderText)
                .font(Theme.fredoka(13, weight: .regular))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 8)
    }
}

/// A soft, on-brand folder silhouette (rounded body + tab), filled with the folder's gradient.
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let radius = w * 0.28
        let tabHeight = h * 0.22
        let tabWidth = w * 0.5
        let bodyTop = rect.minY + tabHeight

        // Tab (top-left). Overlap the body deep enough that the tab's rounded bottom corners sink
        // fully below the body's top edge — so only its straight sides emerge (no furrow at the seam).
        let tab = CGRect(x: rect.minX, y: rect.minY, width: tabWidth, height: tabHeight + radius * 2)
        path.addRoundedRect(in: tab, cornerSize: CGSize(width: radius, height: radius))

        // Body.
        let body = CGRect(x: rect.minX, y: bodyTop, width: w, height: rect.maxY - bodyTop)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))

        return path
    }
}

/// Identifies a paged reading session: the ordered container of fils plus which one to open first.
struct FilPagerSelection: Identifiable {
    let id = UUID()
    let notes: [Note]
    let startID: UUID
    /// The fils' ids captured up front — safe to compare against live fils even after a deletion
    /// (reading a deleted SwiftData model's properties is not).
    let noteIDs: [UUID]

    init(notes: [Note], startID: UUID) {
        self.notes = notes
        self.startID = startID
        self.noteIDs = notes.map(\.uuid)
    }
}

/// A horizontally-paged fil reader: swipe left/right to move between the fils in the container you
/// opened from. Because a container is one type, the sheet detents stay consistent across pages.
/// Each page owns its own navigation stack so threaded pushes don't leak between fils.
/// Shared: also used by the home's Bin/selection baskets, not just folder interiors.
struct BrowserFilPager: View {
    let notes: [Note]
    @State private var selection: UUID
    @State private var detent: PresentationDetent

    init(notes: [Note], startID: UUID) {
        self.notes = notes
        _selection = State(initialValue: startID)
        // Photos open taller (0.8); everything else rests at 0.6.
        let start = notes.first { $0.uuid == startID }
        _detent = State(initialValue: (start?.isImageFil ?? false) ? .fraction(0.8) : .fraction(0.6))
    }

    private var currentNote: Note? { notes.first { $0.uuid == selection } }

    // Links cap at 0.6; photos rest at 0.8 (roomier for the image); everything else at 0.6. All
    // non-link fils can expand to .large.
    private var detents: Set<PresentationDetent> {
        if currentNote?.isLinkFil ?? false { return [.fraction(0.6)] }
        if currentNote?.isImageFil ?? false { return [.fraction(0.8), .large] }
        return [.fraction(0.6), .large]
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(notes, id: \.uuid) { note in
                BrowserFilPage(note: note, detent: $detent)
                    .tag(note.uuid)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .presentationDetents(detents, selection: $detent)
        .presentationBackground { FolderBrowserBackground() }
        .onChange(of: selection) { _, _ in
            // Keep the resting detent valid for the fil just swiped to (types have different bases).
            guard let note = currentNote else { return }
            if note.isLinkFil, detent == .large {
                detent = .fraction(0.6)                     // links cap at 0.6
            } else if note.isImageFil, detent == .fraction(0.6) {
                detent = .fraction(0.8)                     // photos rest taller
            } else if !note.isImageFil, !note.isLinkFil, detent == .fraction(0.8) {
                detent = .fraction(0.6)                     // leaving a photo drops back to 0.6
            }
        }
    }
}

/// One page of the pager: a fil opened the same way the app does (ArticleView in a nav stack),
/// with its own navigation path and the shared detent binding.
private struct BrowserFilPage: View {
    let note: Note
    @Binding var detent: PresentationDetent
    @State private var path: [FilSheetRoute] = []
    @Query(sort: [SortDescriptor(\Note.timestamp, order: .reverse)]) private var allNotes: [Note]

    var body: some View {
        NavigationStack(path: $path) {
            ArticleView(
                note: note,
                ignoresTopSafeArea: false,
                showsCloseButton: true,
                filSheetPath: $path,
                selectedPresentationDetent: $detent
            )
            // Without this, tapping a filament pushed a route with no destination — the fil sheet
            // opened from a folder/Bin showed a caution glyph and nothing else. Mirror CanvasHome.
            .navigationDestination(for: FilSheetRoute.self) { route in
                filSheetDestination(route)
            }
        }
    }

    /// Destinations pushed inside the fil sheet: a filament (keyword) popup, or a linked fil.
    @ViewBuilder
    private func filSheetDestination(_ route: FilSheetRoute) -> some View {
        switch route {
        case .keyword(let noteID, let keyword):
            if let routeNote = allNotes.first(where: { $0.uuid == noteID }) {
                KeywordPopup(note: routeNote, keyword: keyword)
            } else {
                MissingLinkedFilView()
            }
        case .linkedNote(let linkedNoteID):
            if let linkedNote = allNotes.first(where: { $0.uuid == linkedNoteID }) {
                ArticleView(note: linkedNote, showsThreadedFilRows: false, ignoresTopSafeArea: false, filSheetPath: $path, selectedPresentationDetent: $detent)
            } else {
                MissingLinkedFilView()
            }
        }
    }
}
