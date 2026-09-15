import SwiftUI
import SwiftData

/// Which collection the dock's blob row is browsing.
enum DockTab { case bin, selected }

/// The tab actually shown, falling back when the requested one isn't available.
func resolveDockTab(_ tab: DockTab, hasBin: Bool, hasSelection: Bool) -> DockTab {
    if tab == .selected && hasSelection { return .selected }
    if tab == .bin && hasBin { return .bin }
    return hasBin ? .bin : .selected
}

/// The floating liquid-glass row above the composer: a Bin | Selected switcher chip (leftmost, shown
/// whenever the dock has fils), then move / copy / delete action chips when fils are selected. Drives
/// the dock's blob row via `tab` and acts on the shared `FilSelectionStore`.
struct DockChipsRow: View {
    @Binding var tab: DockTab
    /// The Bin's blob row is folded away. Owned by CanvasHome and shared with HomeBasket, which stops
    /// drawing the row; the Bin segment and its count stay, so the fold never hides that fils exist.
    @Binding var binCollapsed: Bool
    /// The Bin segment shows only on the folders home (hidden inside a folder interior).
    var showBin: Bool = true
    /// Tapped "File for me" (or "Organize", when there's nowhere to file yet). The caller decides
    /// which of the two it runs — it re-checks the same folder count this row labels itself from.
    var onFile: () -> Void = {}

    private let selection = FilSelectionStore.shared
    @Query(filter: #Predicate<Note> { $0.folder == nil }, sort: \Note.timestamp, order: .reverse)
    private var unfiled: [Note]
    @Query private var allFolders: [Folder]
    @State private var showLandfil = false
    @State private var copied = false

    private var hasSelection: Bool { !selection.isEmpty }
    private var hasBin: Bool { showBin && !unfiled.isEmpty }
    private var effectiveTab: DockTab { resolveDockTab(tab, hasBin: hasBin, hasSelection: hasSelection) }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            // Scrolls horizontally so the switcher + move/copy/delete never crowd/truncate on a
            // narrow screen (mirrors the old search chip bar).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switcher
                    // The visible twin of the shake gesture. Shake is undiscoverable and
                    // unavailable to anyone who can't shake a phone, so the feature needs a tap
                    // target; this row already exists to hold exactly this kind of action.
                    if canFile { fileChip }
                    if hasSelection {
                        moveChip
                        // Copy acts on the selection only, so hide it while browsing the Bin tab.
                        if effectiveTab == .selected { copyChip }
                        deleteChip
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
        .alert("Send to landfil?", isPresented: $showLandfil) {
            Button("Landfil", role: .destructive) {
                SoundscapeManager.shared.playLandfilSound()
                withAnimation(.snappy) { selection.landfilSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These thoughts will be deleted. This cannot be undone.")
        }
    }

    // MARK: - Switcher chip (one glass capsule; the active segment gets an inner solid capsule)

    private var switcher: some View {
        HStack(spacing: 4) {
            if hasBin {
                collapseToggle
                segment("Bin", unfiled.count, .bin)
            }
            if hasSelection { segment("Selected", selection.count, .selected) }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Folds the Bin's blob row away for a cleaner dock. Sits left of the Bin segment, inside the same
    /// capsule, because it acts on the Bin and nothing else: a selection's row is never folded.
    private var collapseToggle: some View {
        Button {
            Haptics.toggle()
            withAnimation(.snappy(duration: 0.25)) { binCollapsed.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText.opacity(0.6))
                .rotationEffect(.degrees(binCollapsed ? -180 : 0))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(binCollapsed ? "Show Bin" : "Hide Bin")
    }

    private func segment(_ label: String, _ count: Int, _ value: DockTab) -> some View {
        let active = effectiveTab == value
        return Button {
            if !active { SoundscapeManager.shared.playTabSound() }
            withAnimation(.snappy) { tab = value }
        } label: {
            HStack(spacing: 6) {
                Text(label).font(Theme.dmSans(14, weight: .semibold))
                Text("\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(active ? Theme.primaryText : Theme.secondaryText.opacity(0.6))
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background { if active { Capsule().fill(Theme.primaryText.opacity(0.14)) } }
        }
        .buttonStyle(.plain)
    }

    // MARK: - File chip

    /// Shown whenever there is something to act on: a selection anywhere, or the Bin on the
    /// folders home. Inside a folder interior a selection is the only valid input — the Bin
    /// isn't on screen there, and acting on something you can't see reads as a bug.
    private var canFile: Bool { hasSelection || (showBin && hasBin) }

    /// With no folders yet there is nothing to file INTO, and that is smart organize's job — it's
    /// the mode that invents folders. Same slot, honest label, no dead end.
    private var fileChip: some View {
        Button(action: onFile) {
            chipLabel(
                // "File for me" rather than "File these": it rhymes with the folder menu's
                // "Caption for me", so the two Claude actions read as a pair and both say the
                // work is being done on your behalf.
                allFolders.isEmpty ? "Organize" : "File for me",
                allFolders.isEmpty ? "wand.and.stars" : "folder.badge.plus",
                destructive: false,
                // Amber marks a Pro feature, the same signal "Caption for me" carries in the
                // folder menu. Shown to everyone: it's what the lock looks like before you tap.
                tint: Theme.filProAmber
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action chips

    private var moveChip: some View {
        Menu {
            ForEach(selection.folders()) { folder in
                Button(folder.name) { withAnimation(.snappy) { selection.moveSelected(to: folder) } }
            }
        } label: { chipLabel("Move", "folder", destructive: false) }
        .disabled(selection.folders().isEmpty)
    }

    private var copyChip: some View {
        Menu {
            Button { selection.copySelectedAsText(); flashCopied() } label: { Label("Copy as text", systemImage: "doc.plaintext") }
            Button { selection.copySelectedAsMarkdown(); flashCopied() } label: { Label("Copy as Markdown", systemImage: "doc.richtext") }
        } label: { chipLabel(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc", destructive: false) }
    }

    private var deleteChip: some View {
        Button { showLandfil = true } label: { chipLabel("Landfil", "trash", destructive: true) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ text: String, _ icon: String, destructive: Bool, tint: Color? = nil) -> some View {
        DockChipLabel(text, icon, destructive: destructive, tint: tint)
    }

    private func flashCopied() {
        withAnimation(.snappy) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// A liquid-glass chip label; delete carries a red-tinted glass with a white label.
/// `tint` colours the icon only — used to mark a Pro action without shouting.
/// Shared so a chip that appears elsewhere (the Move chip on a Bin fil's reader) is the same chip.
struct DockChipLabel: View {
    let text: String
    let icon: String
    var destructive: Bool = false
    var tint: Color? = nil
    /// Off inside a navigation bar, which already draws its own glass; two layers read as a smudge.
    var glass: Bool = true

    init(_ text: String, _ icon: String, destructive: Bool = false, tint: Color? = nil, glass: Bool = true) {
        self.text = text
        self.icon = icon
        self.destructive = destructive
        self.tint = tint
        self.glass = glass
    }

    var body: some View {
        let fg: Color = destructive ? .white : Theme.primaryText
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint ?? fg)
            Text(text).font(Theme.dmSans(14, weight: .semibold))
        }
        .foregroundStyle(fg)
        .fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(
            glass ? (destructive ? .regular.tint(.red).interactive() : .regular.interactive()) : .identity,
            in: .capsule
        )
    }
}
