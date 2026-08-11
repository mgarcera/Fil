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
    /// The Bin segment shows only on the folders home (hidden inside a folder interior).
    var showBin: Bool = true

    private let selection = FilSelectionStore.shared
    @Query(filter: #Predicate<Note> { $0.folder == nil }, sort: \Note.timestamp, order: .reverse)
    private var unfiled: [Note]
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
                    if hasSelection {
                        moveChip
                        copyChip
                        deleteChip
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
        .alert("Landfil these fils?", isPresented: $showLandfil) {
            Button("Landfil", role: .destructive) { withAnimation(.snappy) { selection.landfilSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These fils will be deleted. This cannot be undone.")
        }
    }

    // MARK: - Switcher chip (one glass capsule; the active segment gets an inner solid capsule)

    private var switcher: some View {
        HStack(spacing: 4) {
            if hasBin { segment("Bin", unfiled.count, .bin) }
            if hasSelection { segment("Selected", selection.count, .selected) }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func segment(_ label: String, _ count: Int, _ value: DockTab) -> some View {
        let active = effectiveTab == value
        return Button { withAnimation(.snappy) { tab = value } } label: {
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

    // MARK: - Action chips

    private var moveChip: some View {
        Menu {
            // Bottom-anchored menu renders bottom-to-top; reverse so it reads in home order.
            ForEach(Array(selection.folders().reversed())) { folder in
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
        Button { showLandfil = true } label: { chipLabel("Delete", "trash", destructive: true) }
            .buttonStyle(.plain)
    }

    /// A liquid-glass chip label; delete carries a red-tinted glass with a white label.
    private func chipLabel(_ text: String, _ icon: String, destructive: Bool) -> some View {
        let fg: Color = destructive ? .white : Theme.primaryText
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(text).font(Theme.dmSans(14, weight: .semibold))
        }
        .foregroundStyle(fg)
        .fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(destructive ? .regular.tint(.red).interactive() : .regular.interactive(), in: .capsule)
    }

    private func flashCopied() {
        withAnimation(.snappy) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { copied = false }
        }
    }
}
