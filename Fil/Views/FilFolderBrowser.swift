import SwiftUI
import SwiftData

/// Real-data folders browser (DEBUG integration surface).
/// Free: manual filing — create folders, rename/move fils, landfil. Pro: "smart organize" via Claude.
/// Rows are the authentic 36pt fil chips and open the real fil on tap; swipe a row for actions.
struct RealFoldersBrowser: View {
    @Query(sort: \Folder.createdAt, order: .reverse) private var folders: [Folder]
    @Query private var allNotes: [Note]
    @Environment(\.modelContext) private var context

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

    private var inbox: [Note] { allNotes.filter { $0.folder == nil } }

    private func cased(_ text: String) -> String { prefersLowercase ? text.lowercased() : text }

    enum Route: Hashable {
        case folder(Folder)
        case inbox
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button { path.append(.inbox) } label: {
                    listRow(seed: 0.5, start: "#8A8A99", end: "#5A5A6B", glyph: "tray.full.fill",
                            title: "Bin", trailing: "\(inbox.count) waiting")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))

                Section {
                    if folders.isEmpty {
                        Text("No folders yet. Tap ＋ to make one.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.tertiaryText)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    }
                    ForEach(folders) { folder in
                        Button { path.append(.folder(folder)) } label: {
                            listRow(seed: seed(for: folder), start: folder.gradientStartHex, end: folder.gradientEndHex,
                                    glyph: nil, title: folder.name, trailing: "\(folder.notes.count)", caption: folder.summary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { startRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.blue)
                            Button(role: .destructive) { pendingLandfilFolder = folder } label: {
                                Label("Landfil", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Folders")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { organize() } label: { Image(systemName: "sparkles") }
                        .disabled(organizing || allNotes.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pendingMoveNote = nil; showNewFolder = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .inbox:
                    interior(title: "Bin", summary: "", seed: 0.5, start: "#8A8A99", end: "#5A5A6B", glyph: "tray.full.fill", notes: inbox, folder: nil)
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
            "This folder is removed. Its fils return to the Bin."
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
        context.delete(folder)   // .nullify → its fils fall back to the Bin
        try? context.save()
    }

    /// New folders draw a gradient from the full range the fils use.
    private func makeFolder(named name: String) -> Folder {
        let pair = Theme.randomGradientPair()
        let folder = Folder(name: name, gradientStartHex: pair.start, gradientEndHex: pair.end)
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

    /// A horizontal shelf for one type (photos read big; notes/links/voice as compact cards).
    private func shelf(_ label: String, _ icon: String, _ items: [Note], isPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            containerHeader(label, icon, items.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: isPhoto ? 16 : 12) {
                    ForEach(items, id: \.uuid) { note in
                        Button { onOpen(note, items) } label: {
                            if isPhoto { photoShelfCard(note) } else { filShelfCard(note) }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { filActions(note) }
                    }
                }
                .padding(.horizontal, 16)
            }
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
                .font(Theme.dmSans(15, weight: .medium))
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
        VStack(alignment: .leading, spacing: 6) {
            filMarker(note, size: 30)
            Spacer(minLength: 6)
            Text(cased(displayTitle(note)))
                .font(Theme.dmSans(15, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            let caption = cased(captionText(note))
            if !caption.isEmpty {
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .background {
            ZStack {
                Theme.cardBackground
                CardBottomGlow(startHex: note.gradientStartHex, endHex: note.gradientEndHex)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primaryText.opacity(0.06), lineWidth: 1))
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

/// A soft gradient glow pooled at the bottom of a card — mirrors the home-screen pinned-fil widget
/// (FilLiveActivityBottomGlow), replicated here since that lives in the widget target. The glow
/// circles sit just below the bottom edge so only their soft upper falloff shows.
private struct CardBottomGlow: View {
    let startHex: String
    let endHex: String

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.5),
                        .init(color: Color(hex: startHex).opacity(0.16), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Color(hex: startHex).opacity(0.32))
                    .frame(width: 120, height: 120)
                    .blur(radius: 40)
                    .position(x: w * 0.28, y: h + 24)
                Circle()
                    .fill(Color(hex: endHex).opacity(0.32))
                    .frame(width: 130, height: 130)
                    .blur(radius: 42)
                    .position(x: w * 0.78, y: h + 26)
            }
        }
        .allowsHitTesting(false)
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

/// The folders entry point: a single grabber pinned to the bottom of the compose home. Drag it up
/// past a short threshold and the folders browser rises as a sheet. Static (no follow/arm motion).
/// Owns its own sheet so it can't interfere with CanvasHome's other sheets.
struct HomeFoldersPeek: View {
    @State private var showBrowser = false

    private let threshold: CGFloat = -44

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
            .contentShape(Rectangle())
            .onTapGesture { showBrowser = true }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onEnded { value in
                        if value.translation.height <= threshold { showBrowser = true }
                    }
            )
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showBrowser) {
            RealFoldersBrowser()
                .presentationBackground(Theme.background)
        }
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
