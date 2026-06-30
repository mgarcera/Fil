import SwiftUI

struct NoteGridView: View {
    let notes: [Note]
    @Binding var selectedNote: Note?
    var selectedNoteIDs: Set<UUID> = []
    var landfillingNoteIDs: Set<UUID> = []
    var isSelectionMode = false
    var collapseCommandID = 0
    var collapseCommandStage = 0
    var onSelectNote: ((Note) -> Void)? = nil
    var onToggleSelection: (Note) -> Void = { _ in }
    var onBeginSelection: (Note) -> Void = { _ in }
    var onToggleSectionSelection: ([Note]) -> Void = { _ in }
    var onLandfil: ((Note) -> Void)?
    private let columnCount = 3
    @AppStorage("collapsedDaySectionKeys")
    private var collapsedDaySectionKeysRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedNotes, id: \.key) { date, notesInGroup in
                DaySectionView(
                    date: date,
                    notesInGroup: notesInGroup,
                    columnCount: columnCount,
                    initialCollapseStage: collapseStage(for: date),
                    selectedNoteIDs: selectedNoteIDs,
                    landfillingNoteIDs: landfillingNoteIDs,
                    isSelectionMode: isSelectionMode,
                    collapseCommandID: collapseCommandID,
                    collapseCommandStage: collapseCommandStage,
                    onSelectNote: { note in
                        if let onSelectNote {
                            onSelectNote(note)
                        } else {
                            selectedNote = note
                        }
                    },
                    onCollapseStageChange: { stage in
                        updateCollapseStage(stage, for: date)
                    },
                    onToggleSelection: onToggleSelection,
                    onBeginSelection: onBeginSelection,
                    onToggleSectionSelection: onToggleSectionSelection,
                    onLandfil: { note in
                        onLandfil?(note)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
    }

    private var groupedNotes: [(key: Date, value: [Note])] {
        let dayPartition = FilDayPartition()
        let grouped = Dictionary(grouping: notes) { note in
            dayPartition.dayStart(for: note.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var storedCollapseStages: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: collapsedDaySectionKeysRaw
                .split(separator: "\n")
                .compactMap { line in
                    let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                    guard let key = parts.first, !key.isEmpty else { return nil }
                    if parts.count == 1 {
                        return (key, 1)
                    }
                    return (key, Int(parts[1]) ?? 1)
                }
        )
    }

    private func dayKey(for date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }

    private func collapseStage(for date: Date) -> Int {
        storedCollapseStages[dayKey(for: date)] ?? 0
    }

    private func updateCollapseStage(_ stage: Int, for date: Date) {
        let key = dayKey(for: date)
        var stages = storedCollapseStages
        if stage > 0 {
            stages[key] = stage
        } else {
            stages.removeValue(forKey: key)
        }
        collapsedDaySectionKeysRaw = stages
            .sorted { $0.key < $1.key }
            .map { "\($0.key)|\($0.value)" }
            .joined(separator: "\n")
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
    let columnCount: Int
    let initialCollapseStage: Int
    let onSelectNote: (Note) -> Void
    let onCollapseStageChange: (Int) -> Void
    let selectedNoteIDs: Set<UUID>
    let landfillingNoteIDs: Set<UUID>
    let isSelectionMode: Bool
    let collapseCommandID: Int
    let collapseCommandStage: Int
    let onToggleSelection: (Note) -> Void
    let onBeginSelection: (Note) -> Void
    let onToggleSectionSelection: ([Note]) -> Void
    let onLandfil: (Note) -> Void

    @State private var settledProgress: CGFloat = 0
    @State private var expandedContentHeight: CGFloat = 0
    @State private var dotContentHeight: CGFloat = 0

    init(
        date: Date,
        notesInGroup: [Note],
        columnCount: Int,
        initialCollapseStage: Int,
        selectedNoteIDs: Set<UUID>,
        landfillingNoteIDs: Set<UUID>,
        isSelectionMode: Bool,
        collapseCommandID: Int,
        collapseCommandStage: Int,
        onSelectNote: @escaping (Note) -> Void,
        onCollapseStageChange: @escaping (Int) -> Void,
        onToggleSelection: @escaping (Note) -> Void,
        onBeginSelection: @escaping (Note) -> Void,
        onToggleSectionSelection: @escaping ([Note]) -> Void,
        onLandfil: @escaping (Note) -> Void
    ) {
        self.date = date
        self.notesInGroup = notesInGroup
        self.columnCount = columnCount
        self.initialCollapseStage = initialCollapseStage
        self.selectedNoteIDs = selectedNoteIDs
        self.landfillingNoteIDs = landfillingNoteIDs
        self.isSelectionMode = isSelectionMode
        self.collapseCommandID = collapseCommandID
        self.collapseCommandStage = collapseCommandStage
        self.onSelectNote = onSelectNote
        self.onCollapseStageChange = onCollapseStageChange
        self.onToggleSelection = onToggleSelection
        self.onBeginSelection = onBeginSelection
        self.onToggleSectionSelection = onToggleSectionSelection
        self.onLandfil = onLandfil
        let normalizedInitialStage = initialCollapseStage > 0 ? 2 : 0
        _settledProgress = State(initialValue: CGFloat(normalizedInitialStage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleSection) {
                HStack {
                    Text(formattedHeaderDate)
                        .font(Theme.dmSans(14, weight: .medium))
                        .foregroundStyle(headerColor)
                        .opacity(headerOpacity)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, sectionSpacing)
            .padding(.bottom, sectionSpacing)

            liveSectionContent
                .padding(.bottom, sectionSpacing)
        }
        .onChange(of: collapseCommandID) { _, _ in
            applyCollapseCommand()
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

    private var collapseProgress: CGFloat {
        min(settledProgress, 1)
    }

    private var deepCollapseProgress: CGFloat {
        max(0, min(1, settledProgress - 1))
    }

    private var liveSectionContent: some View {
        ZStack(alignment: .leading) {
            LazyVGrid(columns: activeColumns, spacing: gridSpacing) {
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
                        },
                        onLandfil: {
                            onLandfil(note)
                        }
                    )
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
                    ForEach(collapsedNotes) { note in
                        let isSelected = selectedNoteIDs.contains(note.uuid)
                        let isLandfilling = landfillingNoteIDs.contains(note.uuid)
                        CollapsedBlobDotShape(seed: note.blobDotSeed)
                            .fill(Theme.gradient(startHex: note.gradientStartHex, endHex: note.gradientEndHex))
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
                    if collapsedNotes.isEmpty {
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
        max(0, min(1, settledProgress / 2))
    }

    private var pulseEnvelope: CGFloat {
        sin(previewReveal * .pi)
    }

    private var sectionSpacing: CGFloat {
        12 - (8 * previewReveal) - (2 * deepCollapseProgress)
    }

    private var gridSpacing: CGFloat {
        12 * (1 - collapseProgress)
    }

    private var activeColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 16 * (1 - collapseProgress)),
            count: columnCount
        )
    }

    private var interpolatedContentHeight: CGFloat {
        let expanded = expandedContentHeight
        guard expanded > 0 else { return 0 }

        let dots = max(dotContentHeight, 1)
        return expanded + ((dots - expanded) * dotCollapseProgress)
    }

    private func applyCollapseCommand() {
        let targetStage = collapseCommandStage > 0 ? 2 : 0
        guard settledProgress != CGFloat(targetStage) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            settledProgress = CGFloat(targetStage)
        }
        onCollapseStageChange(targetStage)
    }

    private func expandSection() {
        SoundscapeManager.shared.playCollapsingSound()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            settledProgress = 0
        }
        onCollapseStageChange(0)
    }

    private func toggleSection() {
        guard canCollapse else { return }
        let nextStage = settledProgress > 0 ? 0 : 2
        if nextStage == 0 {
            SoundscapeManager.shared.playCollapsingSound()
        } else {
            SoundscapeManager.shared.playCollapsePartTwoSound()
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            settledProgress = CGFloat(nextStage)
        }
        onCollapseStageChange(nextStage)
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
    let onLandfil: () -> Void
    @State private var isDeleting = false
    @State private var showLandfilConfirmation = false

    var body: some View {
        Button(action: onTap) {
            NoteCardView(
                note: note,
                selectionStrokeColor: selectionStrokeColor,
                selectionStrokeLineWidth: isSelected ? 3 : 1.5,
                selectionStrokeShadowOpacity: isSelected ? 0.28 : 0
            )
            .overlay(alignment: .topTrailing) {
                selectionCheckmark
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(showsLandfilAnimation ? 0.01 : (isSelected ? 0.94 : 1))
        .blur(radius: showsLandfilAnimation ? 8 : 0)
        .opacity(showsLandfilAnimation ? 0 : (isSelectionMode && !isSelected ? 0.52 : 1))
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onLongPress() }
        )
        .contextMenu {
            if !isSelectionMode {
                Button {
                    onLongPress()
                } label: {
                    Label("select", systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    showLandfilConfirmation = true
                } label: {
                    Label("landfil", systemImage: "trash")
                }
            }
        }
        .alert("move to landfil?", isPresented: $showLandfilConfirmation) {
            Button("landfil", role: .destructive) {
                confirmLandfil()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("this cannot be undone.")
        }
        .animation(.easeOut(duration: 0.45), value: showsLandfilAnimation)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.18), value: isSelectionMode)
    }

    private var showsLandfilAnimation: Bool {
        isDeleting || isLandfilling
    }

    private var selectionStrokeColor: Color? {
        guard isSelectionMode else { return nil }
        return isSelected ? .white : Theme.primaryText.opacity(0.35)
    }

    @ViewBuilder
    private var selectionCheckmark: some View {
        if isSelectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(isSelected ? .white : Theme.primaryText.opacity(0.7))
                .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 5, x: 0, y: 2)
                .padding(6)
        }
    }

    private func confirmLandfil() {
        SoundscapeManager.shared.playLandfilSound()
        isDeleting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.45)) {
                onLandfil()
            }
        }
    }
}
