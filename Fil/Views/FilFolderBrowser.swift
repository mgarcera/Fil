import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The folder browser's page background: `Theme.background` nudged toward the primary color so it
/// reads as the same soft gray as the blurred header. The blur lifts much more over black than over
/// white, so dark mode needs a bigger nudge to match.
private struct FolderBrowserBackground: View {
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

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)]) private var folders: [Folder]
    @Query private var allNotes: [Note]
    @Environment(\.modelContext) private var context

    /// The folder a drag is currently over (drop highlight).
    @State private var targetedFolderID: UUID?

    @State private var path: [Route] = []
    @State private var pagerSelection: FilPagerSelection?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderCaption = ""
    @State private var pendingMoveNote: Note?

    @State private var pendingRenameFolder: Folder?
    @State private var renameFolderText = ""
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
                } header: {
                    HStack(spacing: 16) {
                        Text("Folders")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Button { organize() } label: { Image(systemName: "sparkles") }
                            .disabled(organizing || allNotes.isEmpty)
                        Button { pendingMoveNote = nil; showNewFolder = true } label: { Image(systemName: "plus") }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.primaryText)
                    .textCase(nil)
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
        pendingRenameFolder = folder
    }

    private func commitFolderRename() {
        let name = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = pendingRenameFolder, !name.isEmpty {
            folder.name = name
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

    // MARK: - Smart organize (Pro)

    private func organize() {
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
    @State private var headerHeight: CGFloat = 0   // measured, so list content clears the overlaid header


    // Typed containers. To-dos are claimed first (any fil with a to-do lives there and nowhere else);
    // the rest split by kind. Each bucket is in manual order (sortIndex), newest-first for ties.
    private func hasTodos(_ note: Note) -> Bool { !note.todoRowItems.isEmpty }
    /// Manual position, then newest-first tiebreak — so an un-reordered folder reads newest-first.
    private func inFolderOrder(_ a: Note, _ b: Note) -> Bool {
        a.sortIndex != b.sortIndex ? a.sortIndex < b.sortIndex : a.timestamp > b.timestamp
    }

    private var todoNotes: [Note] { notes.filter(hasTodos).sorted(by: inFolderOrder) }
    private var rest: [Note] { notes.filter { !hasTodos($0) } }
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
        .contentMargins(.top, headerHeight, for: .scrollContent)     // clear the overlaid folder header
        .contentMargins(.bottom, bottomInset, for: .scrollContent)   // clear the floating composer dock
        .background(FolderBrowserBackground())
        // The folder identity header floats over the list as a translucent material bar; cards scroll
        // under it (the native section-header treatment). Its height is measured so content clears it.
        .overlay(alignment: .top) {
            folderHeader
                .background(.ultraThinMaterial)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Creating a fil here happens through the contextual composer bar ("add to {folder}"), not a
        // per-folder ＋.
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
    }

    /// The folder identity header (blob + title + count badge + caption), overlaid on the list.
    private var folderHeader: some View {
        HStack(spacing: 14) {
            FolderMark(seed: seed, start: start, end: end, glyph: glyph, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(cased(title)).font(Theme.instrumentSerif(26)).foregroundStyle(Theme.primaryText)
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                ForEach(items, id: \.uuid) { note in
                    cardRow(filRow(note), note: note, container: items)
                }
                .onMove { reorder(items, from: $0, to: $1) }
            } header: {
                sectionHeader(label, icon, items.count)
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
            .onTapGesture { onOpen(note, container) }
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
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    private func sectionHeader(_ label: String, _ icon: String, _ count: Int) -> some View {
        // Match the home's "Folders" header exactly: no listRowInsets / listRowBackground override, so
        // it keeps the native plain-List section-header material (semi-transparent, pins on scroll).
        // Setting custom insets strips that default chrome and drops it onto the opaque list background.
        containerHeader(label, icon, count)
            .textCase(nil)
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

    /// A full-width card row: the rich component (photo thumb / fil blob) on the left, light text right.
    private func filRow(_ note: Note) -> some View {
        let isPlainNote = !(note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty)
        return HStack(alignment: .top, spacing: 14) {
            rowRich(note)
            VStack(alignment: .leading, spacing: 3) {
                Text(cased(cardContent(note)))
                    .font(Theme.fredoka(15, weight: .regular))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(30)
                    .fixedSize(horizontal: false, vertical: true)
                // Plain notes caption their date; typed fils keep their identity caption (domain/duration).
                let caption = isPlainNote
                    ? cased(note.timestamp.formatted(date: .abbreviated, time: .omitted))
                    : cased(captionText(note))
                if !caption.isEmpty {
                    Text(caption).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A dark card tinted with the fil's gradient — enough color to feel like the fil, but kept
        // low so light text stays legible.
        .background {
            ZStack {
                Theme.cardBackground
                Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed)
                    .opacity(0.14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Theme.primaryText.opacity(0.08), lineWidth: 1))
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

    /// A card's main text: plain notes show their contents; typed fils show their identity.
    private func cardContent(_ note: Note) -> String {
        if note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty { return displayTitle(note) }
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
                ForEach(todoNotes, id: \.uuid) { note in
                    cardRow(todoCard(note), note: note, container: todoNotes)
                }
                .onMove { reorder(todoNotes, from: $0, to: $1) }
            } header: {
                sectionHeader("To-dos", "checklist", todoNotes.reduce(0) { $0 + $1.todoRowItems.count })
            }
        }
    }

    /// A fil's to-dos as a note-style card: blob left + gradient wash; each to-do is a checkbox +
    /// light text row on the right.
    private func todoCard(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 14) {
            filMarker(note, size: 48)
            VStack(alignment: .leading, spacing: 8) {
                // The fil's own thought, so the user sees what they typed above its to-dos.
                let body = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    Text(cased(body))
                        .font(Theme.fredoka(15, weight: .regular))
                        .foregroundStyle(Theme.primaryText)
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
                                .foregroundStyle(Theme.primaryText)
                                .strikethrough(item.done, color: Theme.tertiaryText)
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
        .background {
            ZStack {
                Theme.cardBackground
                Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed)
                    .opacity(0.14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Theme.primaryText.opacity(0.08), lineWidth: 1))
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
        _detent = State(initialValue: .fraction(0.6))
    }

    private var currentNote: Note? { notes.first { $0.uuid == selection } }

    // All types share the 0.6 base size (so a mixed container like the Bin doesn't jump), but only
    // non-link fils can expand to .large — links cap at 0.6.
    private var detents: Set<PresentationDetent> {
        (currentNote?.isLinkFil ?? false) ? [.fraction(0.6)] : [.fraction(0.6), .large]
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
        .presentationBackground(Theme.background)
        .onChange(of: selection) { _, _ in
            // Swiping from an expanded note onto a link snaps back down to the link's 0.6 cap.
            if (currentNote?.isLinkFil ?? false), detent == .large {
                detent = .fraction(0.6)
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

    var body: some View {
        NavigationStack(path: $path) {
            ArticleView(
                note: note,
                ignoresTopSafeArea: false,
                showsCloseButton: true,
                filSheetPath: $path,
                selectedPresentationDetent: $detent
            )
        }
    }
}
