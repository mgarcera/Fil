import SwiftUI

struct NoteGridView: View {
    let notes: [Note]
    @Binding var selectedNote: Note?
    var selectedNoteIDs: Set<UUID> = []
    var landfillingNoteIDs: Set<UUID> = []
    var isSelectionMode = false
    /// When true (e.g. during an active search), sections render expanded regardless of
    /// their saved collapse state, which is left untouched so it restores afterward.
    var forceExpanded = false
    var creatingFilIDs: [UUID] = []
    var creationNamespace: Namespace.ID? = nil
    /// Day-section keys (yyyy-MM-dd) that are currently collapsed. Owned as animatable
    /// @State by ContentView so the FAB and header taps animate through one coordinated
    /// Core Animation transaction — the same path as search's `forceExpanded`.
    var collapsedDayKeys: Set<String> = []
    var onToggleCollapse: (Date) -> Void = { _ in }
    var onSelectNote: ((Note) -> Void)? = nil
    var onToggleSelection: (Note) -> Void = { _ in }
    var onBeginSelection: (Note) -> Void = { _ in }
    var onToggleSectionSelection: ([Note]) -> Void = { _ in }
    private let columnCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.key) { section in
                DaySectionView(
                    date: section.key,
                    notesInGroup: section.notes,
                    placeholderIDs: section.placeholderIDs,
                    columnCount: columnCount,
                    isCollapsed: collapsedDayKeys.contains(dayKey(for: section.key)),
                    selectedNoteIDs: selectedNoteIDs,
                    landfillingNoteIDs: landfillingNoteIDs,
                    isSelectionMode: isSelectionMode,
                    forceExpanded: forceExpanded,
                    creationNamespace: creationNamespace,
                    onSelectNote: { note in
                        if let onSelectNote {
                            onSelectNote(note)
                        } else {
                            selectedNote = note
                        }
                    },
                    onToggle: {
                        onToggleCollapse(section.key)
                    },
                    onToggleSelection: onToggleSelection,
                    onBeginSelection: onBeginSelection,
                    onToggleSectionSelection: onToggleSectionSelection
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
    }

    /// Day sections for the grid. In-flight creations are dropped from their day's notes
    /// and surfaced as placeholder blobs at the front of today's section — the exact slot
    /// the finished card lands in — so the blob morphs into place without moving.
    private var sections: [(key: Date, notes: [Note], placeholderIDs: [UUID])] {
        let inFlight = Set(creatingFilIDs)
        let visibleNotes = notes.filter { !inFlight.contains($0.uuid) }
        let dayPartition = FilDayPartition()
        let grouped = Dictionary(grouping: visibleNotes) { note in
            dayPartition.dayStart(for: note.timestamp)
        }

        var result = grouped
            .sorted { $0.key > $1.key }
            .map { (key: $0.key, notes: $0.value, placeholderIDs: [UUID]()) }

        guard !creatingFilIDs.isEmpty else { return result }

        let todayStart = dayPartition.dayStart(for: Date())
        if let index = result.firstIndex(where: { $0.key == todayStart }) {
            result[index].placeholderIDs = creatingFilIDs
        } else {
            result.insert((key: todayStart, notes: [], placeholderIDs: creatingFilIDs), at: 0)
        }
        return result
    }

    private func dayKey(for date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DaySectionView: View {
    let date: Date
    let notesInGroup: [Note]
    let placeholderIDs: [UUID]
    let columnCount: Int
    /// Collapsed state is passed in (read in body), derived from an animatable Set<String>
    /// of collapsed day keys owned by ContentView — never local @State. Both the FAB and
    /// header taps mutate that Set inside a single `withAnimation`, so every section's leaf
    /// modifiers (scale/opacity/frame/offset) tween via Core Animation in one coordinated
    /// pass — the same path as search's `forceExpanded`.
    let isCollapsed: Bool
    let selectedNoteIDs: Set<UUID>
    let landfillingNoteIDs: Set<UUID>
    let isSelectionMode: Bool
    let forceExpanded: Bool
    let creationNamespace: Namespace.ID?
    let onSelectNote: (Note) -> Void
    let onToggle: () -> Void
    let onToggleSelection: (Note) -> Void
    let onBeginSelection: (Note) -> Void
    let onToggleSectionSelection: ([Note]) -> Void

    @State private var expandedContentHeight: CGFloat = 0
    @State private var dotContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleSection) {
                HStack {
                    Text(formattedHeaderDate)
                        .font(Theme.dmSans(18, weight: .bold))
                        .foregroundStyle(headerColor)
                        .opacity(headerOpacity)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, sectionSpacing)
            .padding(.bottom, sectionSpacing + headerToContentGap)

            liveSectionContent
                .padding(.bottom, sectionSpacing)
        }
    }

    private var canCollapse: Bool {
        true
    }

    private var formattedHeaderDate: String {
        Self.headerDateFormatter.string(from: date)
    }

    private var headerColor: Color {
        if FilDayPartition().isToday(date) || collapseProgress == 0 {
            return Theme.primaryText
        }

        return Theme.inactiveTabText
    }

    private var headerOpacity: Double {
        1 - Double(deepCollapseProgress)
    }

    /// Collapse amount used for layout. Forced to 0 (fully expanded) during search,
    /// without disturbing the persisted collapse state, so it restores afterward.
    ///
    /// This is a *discrete* driver (0 or 2), never a continuously animated CGFloat. When the
    /// passed-in `isCollapsed` changes inside a `withAnimation`, SwiftUI evaluates this view's
    /// body once and lets Core Animation tween the leaf modifiers (scale, opacity, frame
    /// height, offset) between the two endpoints. Animating a CGFloat directly would instead
    /// re-run body every frame for every section — the FAB/tap jank we chased down.
    private var effectiveProgress: CGFloat {
        (forceExpanded || !isCollapsed) ? 0 : 2
    }

    private var collapseProgress: CGFloat {
        min(effectiveProgress, 1)
    }

    private var deepCollapseProgress: CGFloat {
        max(0, min(1, effectiveProgress - 1))
    }

    private var liveSectionContent: some View {
        ZStack(alignment: .leading) {
            LazyVGrid(columns: activeColumns, spacing: gridSpacing) {
                ForEach(placeholderIDs, id: \.self) { id in
                    CreatingFilBlobView()
                        .frame(height: 98)
                        .filCreationMorph(id: id, in: creationNamespace)
                        .transition(.opacity)
                }

                ForEach(notesInGroup, id: \.uuid) { note in
                    DeletableNoteCard(
                        note: note,
                        isSelected: selectedNoteIDs.contains(note.uuid),
                        isLandfilling: landfillingNoteIDs.contains(note.uuid),
                        isSelectionMode: isSelectionMode,
                        onTap: {
                            if isSelectionMode {
                                onToggleSelection(note)
                            } else {
                                onSelectNote(note)
                            }
                        },
                        onLongPress: {
                            onBeginSelection(note)
                        }
                    )
                    .filCreationMorph(id: note.uuid, in: creationNamespace)
                    .transition(.blurReplace)
                }
            }
            .allowsHitTesting(collapseProgress < 0.9)
            .scaleEffect((1 - (0.3 * previewReveal)) + (0.05 * pulseEnvelope), anchor: .center)
            .opacity(1 - (previewReveal * 1.15))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .measureHeight { expandedContentHeight = $0 }
            .zIndex(0)

            collapsedDotRow
                .zIndex(1)
        }
        .frame(height: interpolatedContentHeight, alignment: .topLeading)
    }

    private var collapsedDotRow: some View {
        Button {
            if isSelectionMode {
                onToggleSectionSelection(notesInGroup)
            } else {
                expandSection()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    let collapsedNotes = collapsedTokenNotes
                    // A miniature of the same fil-creation blob used in the expanded grid, so
                    // in-flight creations still show in the collapsed row. No matched-geometry
                    // here — that stays on the expanded grid placeholder (a single source).
                    ForEach(placeholderIDs, id: \.self) { _ in
                        CreatingFilBlobView()
                            .frame(width: 24, height: 24)
                            .transition(.opacity)
                    }
                    ForEach(collapsedNotes) { note in
                        let isSelected = selectedNoteIDs.contains(note.uuid)
                        let isLandfilling = landfillingNoteIDs.contains(note.uuid)
                        CollapsedBlobDotShape(seed: note.blobDotSeed)
                            .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex, seed: note.blobShapeSeed))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if isSelected {
                                    CollapsedBlobDotShape(seed: note.blobDotSeed)
                                        .stroke(.white, lineWidth: 2)
                                }
                            }
                            .scaleEffect(isLandfilling ? 0.01 : (isSelected ? 1.16 : 1))
                            .blur(radius: isLandfilling ? 8 : 0)
                            .opacity(isLandfilling ? 0 : 1)
                            .animation(.easeOut(duration: 0.45), value: isLandfilling)
                    }
                    if collapsedNotes.isEmpty && placeholderIDs.isEmpty {
                        CollapsedBlobDotShape(seed: 0.4)
                            .fill(Theme.inactiveTabText.opacity(0.6))
                            .frame(width: 24, height: 24)
                    }
                }
                .measureHeight { dotContentHeight = $0 }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onToggleSectionSelection(notesInGroup) }
        )
        .opacity(dotCollapseProgress)
        .scaleEffect(0.7 + (0.3 * dotCollapseProgress), anchor: .center)
        .offset(y: -4 * (1 - dotCollapseProgress))
        .allowsHitTesting(dotCollapseProgress > 0.98)
    }

    private var collapsedTokenNotes: [Note] {
        notesInGroup
    }

    private var previewReveal: CGFloat {
        max(0, min(1, (collapseProgress - 0.18) / 0.82))
    }

    private var dotCollapseProgress: CGFloat {
        max(0, min(1, effectiveProgress / 2))
    }

    private var pulseEnvelope: CGFloat {
        sin(previewReveal * .pi)
    }

    private var sectionSpacing: CGFloat {
        12 - (8 * previewReveal) - (2 * deepCollapseProgress)
    }

    /// Extra gap between the date header and the top row of fils, present only when the
    /// section is expanded — fades to 0 as it collapses so the collapsed (dots) spacing
    /// stays tight, as before.
    private var headerToContentGap: CGFloat {
        14 * (1 - collapseProgress)
    }

    // Kept constant through the collapse so the LazyVGrid isn't forced to re-lay-out
    // every card each animation frame. The visual shrink is carried by the scaleEffect,
    // opacity, and height interpolation below — interpolating spacing too only added
    // per-frame layout churn (and re-computed every blob path) with no visible benefit.
    private var gridSpacing: CGFloat {
        18
    }

    private var activeColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 16),
            count: columnCount
        )
    }

    private var interpolatedContentHeight: CGFloat {
        let expanded = expandedContentHeight
        guard expanded > 0 else { return 0 }

        let dots = max(dotContentHeight, 1)
        return expanded + ((dots - expanded) * dotCollapseProgress)
    }

    // Both toggle paths animate by mutating ContentView's collapsed-keys Set *inside*
    // withAnimation (via onToggle). The new isCollapsed value flows back down and Core
    // Animation tweens the leaf modifiers — one coordinated transaction, exactly like the
    // search/forceExpanded path.
    private func expandSection() {
        SoundscapeManager.shared.playCollapsingSound()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            onToggle()
        }
    }

    private func toggleSection() {
        guard canCollapse else { return }
        if isCollapsed {
            SoundscapeManager.shared.playCollapsingSound()
        } else {
            SoundscapeManager.shared.playCollapsePartTwoSound()
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            onToggle()
        }
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let fitsCurrentRow = currentX == 0 || currentX + size.width <= maxWidth

            if !fitsCurrentRow {
                totalHeight += currentRowHeight + lineSpacing
                maxRowWidth = max(maxRowWidth, currentX - spacing)
                currentX = 0
                currentRowHeight = 0
            }

            currentRowHeight = max(currentRowHeight, size.height)
            currentX += size.width + spacing
        }

        if !subviews.isEmpty {
            totalHeight += currentRowHeight
            maxRowWidth = max(maxRowWidth, max(0, currentX - spacing))
        }

        return CGSize(width: min(maxWidth, maxRowWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let fitsCurrentRow = currentX == bounds.minX || currentX + size.width <= bounds.maxX

            if !fitsCurrentRow {
                currentX = bounds.minX
                currentY += currentRowHeight + lineSpacing
                currentRowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

private struct CollapsedBlobDotShape: Shape {
    let seed: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = 5 + Int(seed * 4.999)
        let amplitude = CGFloat(0.055 + (seed * 0.055))
        let secondaryFrequency = CGFloat(2 + Int(Self.unitNoise(seed, salt: 17) * 4))
        let tertiaryFrequency = CGFloat(3 + Int(Self.unitNoise(seed, salt: 23) * 4))
        let phaseA = CGFloat(seed * .pi * 2)
        let phaseB = CGFloat((1 - seed) * .pi * 2)
        let rotation = CGFloat((Self.unitNoise(seed, salt: 29) - 0.5) * 0.7)
        let asymmetryPhase = CGFloat(Self.unitNoise(seed, salt: 37) * .pi * 2)
        let asymmetryStrength = CGFloat((Self.unitNoise(seed, salt: 41) - 0.5) * 0.18)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.46
        let radiusY = rect.height * 0.42
        let blobPoints = (0..<points).map { index in
            let angle = (CGFloat(index) / CGFloat(points) * .pi * 2) + rotation
            let pointOffset = CGFloat((Self.unitNoise(seed, salt: Double(index) + 101) - 0.5) * 0.22)
            let waveOffset = (
                sin(angle * secondaryFrequency + phaseA) * 0.65
                + sin(angle * tertiaryFrequency + phaseB) * 0.45
            ) * amplitude
            let asymmetryOffset = cos(angle + asymmetryPhase) * asymmetryStrength
            let radiusMultiplier = max(0.72, 1 + pointOffset + waveOffset + asymmetryOffset)
            return CGPoint(
                x: center.x + cos(angle) * radiusX * radiusMultiplier,
                y: center.y + sin(angle) * radiusY * radiusMultiplier
            )
        }

        guard let firstPoint = blobPoints.first else { return path }
        path.move(to: firstPoint)

        for index in 0..<points {
            let current = blobPoints[index]
            let next = blobPoints[(index + 1) % points]
            let previous = blobPoints[(index - 1 + points) % points]
            let following = blobPoints[(index + 2) % points]
            path.addCurve(
                to: next,
                control1: CGPoint(
                    x: current.x + (next.x - previous.x) * 0.2,
                    y: current.y + (next.y - previous.y) * 0.2
                ),
                control2: CGPoint(
                    x: next.x - (following.x - current.x) * 0.2,
                    y: next.y - (following.y - current.y) * 0.2
                )
            )
        }

        path.closeSubpath()
        return path
    }

    private static func unitNoise(_ seed: Double, salt: Double) -> Double {
        let value = sin((seed + 0.137) * (salt + 12.9898) * 78.233) * 43758.5453
        return value - floor(value)
    }
}

private extension Note {
    var blobDotSeed: Double {
        let scalars = uuid.uuidString.unicodeScalars
        let hash = scalars.reduce(UInt32(2166136261)) { partial, scalar in
            (partial ^ scalar.value) &* 16777619
        }
        return Double(hash % 10_000) / 10_000
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

private struct DeletableNoteCard: View {
    let note: Note
    let isSelected: Bool
    let isLandfilling: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            NoteCardView(
                note: note,
                selectionStrokeColor: selectionStrokeColor,
                selectionStrokeLineWidth: isSelected ? 3 : 1.5,
                selectionStrokeShadowOpacity: isSelected ? 0.28 : 0
            )
            .overlay {
                selectionCheckmark
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(showsLandfilAnimation ? 0.01 : (isSelected ? 0.94 : 1))
        .blur(radius: showsLandfilAnimation ? 8 : 0)
        .opacity(showsLandfilAnimation ? 0 : (isSelectionMode && !isSelected ? 0.52 : 1))
        // Long-press goes straight to selection mode. We intentionally have no context menu:
        // its dismiss animation briefly clipped the badge (which floats above the card via
        // .offset), and landfil is handled from selection mode instead.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onLongPress() }
        )
        .animation(.easeOut(duration: 0.45), value: showsLandfilAnimation)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.18), value: isSelectionMode)
        // Collapse the decorative blob into one spoken element with a meaningful label, and
        // expose the long-press selection (which VoiceOver can't perform) as a named action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityHint(isSelectionMode ? "double tap to toggle selection" : "double tap to open")
        .accessibilityAction(named: Text("select")) { onLongPress() }
    }

    /// Title + fil kind, so VoiceOver announces what the card is rather than the bare badge.
    private var cardAccessibilityLabel: Text {
        let name = note.displayBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "fil" : name
        let kind: String
        if note.isImageFil {
            kind = "photo fil"
        } else if note.isLinkFil {
            kind = "link fil"
        } else if !note.audioFilePath.isEmpty {
            kind = "voice fil"
        } else {
            kind = "text fil"
        }
        return Text("\(title), \(kind)")
    }

    private var showsLandfilAnimation: Bool {
        isLandfilling
    }

    private var selectionStrokeColor: Color? {
        guard isSelectionMode else { return nil }
        return isSelected ? .white : Theme.primaryText.opacity(0.35)
    }

    @ViewBuilder
    private var selectionCheckmark: some View {
        if isSelectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(isSelected ? .white : Theme.primaryText.opacity(0.8))
                .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)
        }
    }

}
