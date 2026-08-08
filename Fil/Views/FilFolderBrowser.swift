import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// The folders surface, embedded inline on the home below the compose bar (no longer a modal).
/// Free: manual filing — create folders, rename/move fils, landfil. Pro: "smart organize" via Claude.
/// Tapping a folder pushes its typed-container interior; ＋ / ✨ ride in a compact header row.
struct FoldersHomeSection: View {
    /// Called on release of a past-threshold downward pull (swipe-to-refresh style) to start a new fil.
    var onNew: () -> Void = {}
    /// Reports whether a folder interior is pushed, so the home can hide its floating header there.
    var onInteriorOpenChange: (Bool) -> Void = { _ in }

    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt, order: .reverse)]) private var folders: [Folder]
    @Query private var allNotes: [Note]
    @Environment(\.modelContext) private var context

    /// Live overscroll pull distance (>=0) and whether it has passed the commit threshold.
    @State private var pull: CGFloat = 0
    @State private var armed = false
    private let revealThreshold: CGFloat = 96

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
                // Pull-to-add affordance (grows in the top overscroll gap; unfiled fils now live in the
                // bottom Bin basket rather than a hero deck).
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: armed ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(armed ? .green : Theme.secondaryText)
                        Text(armed ? "release to add" : "pull to add")
                            .font(Theme.dmSans(13, weight: .medium)).foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(height: max(0, min(pull, revealThreshold + 30)))
                    .frame(maxWidth: .infinity)
                    .opacity(Double(min(pull / 40, 1)))
                    .clipped()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { startRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.blue)
                            Button(role: .destructive) { pendingLandfilFolder = folder } label: {
                                Label("Landfil", systemImage: "trash")
                            }
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
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                pull = max(0, -y)
                let nowArmed = pull >= revealThreshold
                if nowArmed != armed {
                    withAnimation(.easeOut(duration: 0.12)) { armed = nowArmed }
                    if nowArmed { pullHaptic() }
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                let wasDragging = oldPhase == .interacting || oldPhase == .tracking
                if wasDragging && newPhase != .interacting && newPhase != .tracking && armed {
                    armed = false
                    onNew()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: path) { _, newPath in onInteriorOpenChange(!newPath.isEmpty) }
            .onAppear { normalizeFolderOrder() }
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

    private func interior(title: String, summary: String, seed: Double, start: String, end: String, glyph: String?, notes: [Note], folder: Folder?) -> some View {
        FolderInteriorView(
            title: title, summary: summary, seed: seed, start: start, end: end, glyph: glyph, notes: notes, folders: folders, folder: folder,
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
        move(note, to: folder)   // file the dragged Bin card into this folder
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
                        .font(.system(size: 12))
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
        if let note = pendingMoveNote { note.folder = folder }
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
        try? context.save()
    }

    private func delete(_ folder: Folder) {
        context.delete(folder)   // .nullify → its fils fall back to the unfiled deck
        try? context.save()
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
            for id in group.filIDs { byID[id]?.folder = folder }
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
    /// Opens a fil; the second argument is the ordered container it belongs to, for left/right paging.
    var onOpen: (Note, [Note]) -> Void
    var onMove: (Note, Folder?) -> Void
    var onNewFolder: (Note) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("prefersLowercase") private var prefersLowercase = false

    @State private var pendingRenameNote: Note?
    @State private var renameText = ""
    @State private var moveTargetNote: Note?
    @State private var pendingLandfilNote: Note?

    @State private var showNewFil = false
    @State private var newFilTitle = ""
    @State private var newFilBody = ""

    // Typed containers. To-dos are claimed first (any fil with a to-do lives there and nowhere else);
    // the rest split by kind. Each bucket is sorted most-recent.
    private func hasTodos(_ note: Note) -> Bool { !note.todoRowItems.isEmpty }
    private func byRecent(_ a: Note, _ b: Note) -> Bool { a.timestamp > b.timestamp }

    private var todoNotes: [Note] { notes.filter(hasTodos).sorted(by: byRecent) }
    private var rest: [Note] { notes.filter { !hasTodos($0) } }
    private var photoNotes: [Note] { rest.filter { $0.isImageFil }.sorted(by: byRecent) }
    private var linkNotes: [Note] { rest.filter { $0.isLinkFil }.sorted(by: byRecent) }
    private var voiceNotes: [Note] { rest.filter { !$0.isImageFil && !$0.isLinkFil && !$0.audioFilePath.isEmpty }.sorted(by: byRecent) }
    private var plainNotes: [Note] { rest.filter { !$0.isImageFil && !$0.isLinkFil && $0.audioFilePath.isEmpty }.sorted(by: byRecent) }

    private func cased(_ text: String) -> String { prefersLowercase ? text.lowercased() : text }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                FolderMark(seed: seed, start: start, end: end, glyph: glyph, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cased(title)).font(Theme.instrumentSerif(26)).foregroundStyle(Theme.primaryText)
                    if !summary.isEmpty {
                        Text(cased(summary))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(notes.count == 1 ? "1 item" : "\(notes.count) items")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    // To-dos ride at the top; every other type is a horizontal shelf below.
                    if !todoNotes.isEmpty { todoContainer }
                    if !photoNotes.isEmpty { shelf("Photos", "photo", photoNotes, isPhoto: true) }
                    if !plainNotes.isEmpty { shelf("Notes", "note.text", plainNotes, isPhoto: false) }
                    if !linkNotes.isEmpty { shelf("Links", "link", linkNotes, isPhoto: false) }
                    if !voiceNotes.isEmpty { shelf("Voice", "waveform", voiceNotes, isPhoto: false) }
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewFil = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New fil", isPresented: $showNewFil) {
            TextField("title", text: $newFilTitle)
            TextField("note (optional)", text: $newFilBody)
            Button("Create") { createFil() }
            Button("Cancel", role: .cancel) { newFilTitle = ""; newFilBody = "" }
        }
        .alert("Rename fil", isPresented: .init(
            get: { pendingRenameNote != nil },
            set: { if !$0 { pendingRenameNote = nil } }
        )) {
            TextField("title", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { pendingRenameNote = nil }
        }
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

    private func startRename(_ note: Note) {
        renameText = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingRenameNote = note
    }

    private func commitRename() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note = pendingRenameNote, !title.isEmpty {
            note.title = title
            try? context.save()
        }
        pendingRenameNote = nil
    }

    /// Create a plain text fil filed straight into this folder (nil folder = the Bin).
    private func createFil() {
        let title = newFilTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = newFilBody.trimmingCharacters(in: .whitespacesAndNewlines)
        newFilTitle = ""; newFilBody = ""
        guard !title.isEmpty || !body.isEmpty else { return }

        let finalTitle = title.isEmpty ? String(body.prefix(40)) : title
        let pair = Theme.randomGradientPair()
        let note = Note(
            title: finalTitle,
            transcript: body,
            keyword: finalTitle,
            gradientStartHex: pair.start,
            gradientEndHex: pair.end
        )
        note.folder = folder
        context.insert(note)
        try? context.save()
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
        .padding(.horizontal, 16)
    }

    /// One type's fils in a two-column grid (photos as thumbnails; notes/links/voice as cards).
    private func shelf(_ label: String, _ icon: String, _ items: [Note], isPhoto: Bool) -> some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            containerHeader(label, icon, items.count)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items, id: \.uuid) { note in
                    Group {
                        if isPhoto { photoShelfCard(note) } else { filShelfCard(note) }
                    }
                    .contentShape(Rectangle())
                    // Tap opens; a swipe-to-select won't fire this (a drag cancels the tap).
                    .onTapGesture { onOpen(note, items) }
                    .contextMenu { filActions(note) }
                    .swipeToSelect(note.uuid)   // swipe left to add to the selection basket
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Photos wear the same widget-style card as notes, but the top slot is a rounded photo
    /// thumbnail instead of a blob marker; title pinned to the bottom.
    private func photoShelfCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            photoThumb(note)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(cased(displayTitle(note)))
                .font(Theme.dmSans(13, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primaryText.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder private func photoThumb(_ note: Note) -> some View {
        if let data = note.sortedImageFilImages.first?.data, let image = Image(data: data) {
            image.resizable().scaledToFill()
        } else {
            Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed)
        }
    }

    /// Styled like the home-screen pinned-fil widget: a dark rounded card with a gradient glow pooled
    /// at the bottom, the fil's blob mark floating top-left, and the text pushed to the bottom edge.
    private func filShelfCard(_ note: Note) -> some View {
        // Plain notes show their contents (no title); links/voice show identity + a caption.
        let isPlainNote = !(note.isImageFil || note.isLinkFil || !note.audioFilePath.isEmpty)
        return VStack(alignment: .leading, spacing: 6) {
            filMarker(note, size: 30)
            Spacer(minLength: 6)
            Text(cased(cardContent(note)))
                .font(Theme.dmSans(13, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if !isPlainNote {
                let caption = cased(captionText(note))
                if !caption.isEmpty {
                    Text(caption).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primaryText.opacity(0.06), lineWidth: 1))
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

    // The To-dos container: an aggregated checklist across every fil in the folder that has to-dos.
    // Tapping a row toggles the to-do; long-press opens the source fil's actions.
    private var todoContainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            containerHeader("To-dos", "checklist", todoNotes.reduce(0) { $0 + $1.todoRowItems.count })
            VStack(spacing: 0) {
                ForEach(todoNotes, id: \.uuid) { note in
                    ForEach(note.todoRowItems) { item in
                        TodoRowContent(
                            text: cased(item.text),
                            isCompleted: item.done,
                            onToggle: { toggleTodo(note, at: item.index) }
                        )
                        .padding(.vertical, 5)
                        .contextMenu { filActions(note) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private func filActions(_ note: Note) -> some View {
        Button { startRename(note) } label: { Label("Rename", systemImage: "pencil") }
        Button { moveTargetNote = note } label: { Label("Move", systemImage: "folder") }
        Button(role: .destructive) { pendingLandfilNote = note } label: { Label("Landfil", systemImage: "trash") }
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
}

/// A horizontally-paged fil reader: swipe left/right to move between the fils in the container you
/// opened from. Because a container is one type, the sheet detents stay consistent across pages.
/// Each page owns its own navigation stack so threaded pushes don't leak between fils.
private struct BrowserFilPager: View {
    let notes: [Note]
    @State private var selection: UUID
    @State private var detent: PresentationDetent

    init(notes: [Note], startID: UUID) {
        self.notes = notes
        _selection = State(initialValue: startID)
        let start = notes.first { $0.uuid == startID }
        _detent = State(initialValue: (start?.isLinkFil ?? false) ? .fraction(0.2) : .fraction(0.6))
    }

    // A container is a single type, so the first fil's kind sets the detents for the whole session.
    private var detents: Set<PresentationDetent> {
        (notes.first?.isLinkFil ?? false) ? [.fraction(0.2)] : [.fraction(0.6), .large]
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
