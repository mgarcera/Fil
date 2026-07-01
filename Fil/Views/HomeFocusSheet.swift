import SwiftUI

struct HomeFocusSheet: View {
    let notes: [Note]
    let userProfile: UserProfile?
    let onOpenNote: (Note) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var openTodoSummary: OpenTodoSummary?
    @State private var isLoadingOpenTodoSummary = false
    @State private var selectedCardIndex = 0

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                summarySection
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: openTodoSummaryCacheKey) {
            await refreshOpenTodoSummary()
        }
        .onChange(of: openTodoSummary?.cards.count) { _, newCount in
            guard let newCount, newCount > 0 else {
                selectedCardIndex = 0
                return
            }
            selectedCardIndex = min(selectedCardIndex, newCount - 1)
        }
    }

    private var openTodoEntries: [OpenTodoEntry] {
        notes.flatMap { note in
            note.todos.enumerated().compactMap { index, todo in
                let isCompleted = note.completedTodos.indices.contains(index) ? note.completedTodos[index] : false
                guard !isCompleted else { return nil }

                return OpenTodoEntry(
                    id: "\(note.uuid.uuidString)-\(index)",
                    todoText: todo.trimmingCharacters(in: .whitespacesAndNewlines),
                    noteUUID: note.uuid,
                    noteTitle: note.title,
                    noteKeyword: note.keyword,
                    noteTimestamp: note.timestamp,
                    noteGradientStartHex: note.gradientStartHex,
                    noteGradientEndHex: note.gradientEndHex,
                    contextSnippet: contextSnippet(for: note)
                )
            }
        }
        .filter { !$0.todoText.isEmpty }
        .sorted { $0.noteTimestamp < $1.noteTimestamp }
    }

    private var openTodoSummaryCacheKey: String {
        let dayPartition = FilDayPartition()
        let entryKey = openTodoEntries.map {
            "\($0.id)|\($0.todoText)|\($0.noteTitle)|\($0.noteTimestamp.timeIntervalSince1970)"
        }
        .joined(separator: "||")
        let profileKey = userProfile.map { "lowercase:\($0.prefersLowercase)" } ?? "no-profile"
        let dayKey = String(dayPartition.referenceDayStart.timeIntervalSince1970)
        return "todo-summary-v15::" + dayKey + "::" + entryKey + "::" + profileKey
    }

    private var currentCard: OpenTodoCardSummary? {
        guard let cards = openTodoSummary?.cards, cards.indices.contains(selectedCardIndex) else {
            return openTodoSummary?.cards.first
        }
        return cards[selectedCardIndex]
    }

    private var currentStartColor: Color {
        if let currentCard {
            return Color(hex: currentCard.gradientStartHex)
        }
        if let firstEntry = openTodoEntries.first {
            return Color(hex: firstEntry.noteGradientStartHex)
        }
        return Color(hex: "#408CD9")
    }

    private var currentEndColor: Color {
        if let currentCard {
            return Color(hex: currentCard.gradientEndHex)
        }
        if let firstEntry = openTodoEntries.first {
            return Color(hex: firstEntry.noteGradientEndHex)
        }
        return Color(hex: "#6659CC")
    }

    private var summarySection: some View {
        ZStack {
            loadingStateView

            summaryContent
                .opacity(shouldShowLoadingState ? 0 : 1)
                .blur(radius: shouldShowLoadingState ? 14 : 0)
                .scaleEffect(shouldShowLoadingState ? 0.985 : 1)
        }
        .animation(.easeInOut(duration: 0.45), value: shouldShowLoadingState)
        .animation(.easeInOut(duration: 0.45), value: hasResolvedOpenTodoSummary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowLoadingState: Bool {
        isLoadingOpenTodoSummary && openTodoSummary == nil && !openTodoEntries.isEmpty
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let openTodoSummary {
            if !openTodoSummary.cards.isEmpty {
                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        cardPagination(openTodoSummary.cards)

                        TabView(selection: $selectedCardIndex) {
                            ForEach(Array(openTodoSummary.cards.enumerated()), id: \.element.id) { index, card in
                                todoSummaryCard(card)
                                    .tag(index)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 160)
                    }

                    Spacer(minLength: 0)
                }
            } else if !openTodoSummary.text.isEmpty {
                Text(openTodoSummary.text)
                    .font(Theme.dmSans(18, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                emptyStateView
            }
        } else {
            emptyStateView
        }
    }

    private var loadingStateView: some View {
        GooeySummaryLoadingView(
            startColor: currentStartColor,
            endColor: currentEndColor,
            gradientColors: Theme.accentGradientColors,
            showsContainer: false,
            primaryOpacity: hasResolvedOpenTodoSummary ? 0.5 : 1,
            secondaryOpacity: hasResolvedOpenTodoSummary ? 0.24 : 0.4
        )
        .blur(radius: shouldShowLoadingState ? 0 : (hasResolvedOpenTodoSummary ? 22 : 16))
        .opacity(shouldShowLoadingState || hasResolvedOpenTodoSummary ? 1 : 0)
        .scaleEffect(shouldShowLoadingState ? 1 : (hasResolvedOpenTodoSummary ? 0.46 : 0.96))
        .offset(y: 0)
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: loadingBlobAlignment)
    }

    private var hasResolvedOpenTodoSummary: Bool {
        openTodoSummary != nil
    }

    private var loadingBlobAlignment: Alignment {
        hasResolvedOpenTodoSummary ? .bottom : .center
    }

    private var loadingEllipses: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(.clear)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Theme.primaryText.opacity(0.28), lineWidth: 1.15)
                    }
                    .borderBeam(
                        border: Theme.primaryText.opacity(0.28),
                        hideFadeBorder: false,
                        beam: Theme.accentGradientColors,
                        beamBlur: 10,
                        cornerRadius: 999
                    )
            }
        }
    }

    private var emptyStateView: some View {
        Text("no open to-dos right now")
            .font(Theme.dmMono(12))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private func cardPagination(_ cards: [OpenTodoCardSummary]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                Button {
                    withAnimation(.snappy) {
                        selectedCardIndex = index
                    }
                } label: {
                    Capsule()
                        .fill(
                            index == selectedCardIndex
                            ? AnyShapeStyle(Theme.gradient(startHex: card.gradientStartHex, endHex: card.gradientEndHex))
                            : AnyShapeStyle(Theme.primaryText)
                        )
                        .frame(width: index == selectedCardIndex ? 18 : 8, height: 8)
                        .opacity(index == selectedCardIndex ? 1.0 : 0.45)
                        .animation(.easeInOut(duration: 0.2), value: selectedCardIndex)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("summary \(index + 1) for \(card.todoText)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func todoSummaryCard(_ card: OpenTodoCardSummary) -> some View {
        Button {
            guard let note = notes.first(where: { $0.uuid == card.noteUUID }) else { return }
            openNote(note)
        } label: {
            VStack {
                Spacer(minLength: 0)
                Text(card.summary)
                    .font(Theme.dmSans(15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshOpenTodoSummary() async {
        guard !openTodoEntries.isEmpty else {
            openTodoSummary = nil
            return
        }
        guard !isLoadingOpenTodoSummary else { return }

        isLoadingOpenTodoSummary = true
        defer { isLoadingOpenTodoSummary = false }

        do {
            let dayPartition = FilDayPartition()
            let oldestDate = openTodoEntries.first?.noteTimestamp ?? .now
            let newestDate = openTodoEntries.last?.noteTimestamp ?? .now
            let context = FilTimeContext(
                now: dayPartition.referenceDate,
                firstNoteAt: oldestDate,
                lastNoteAt: newestDate,
                calendar: dayPartition.calendar
            )
            openTodoSummary = try await OpenTodoSummaryService.shared.generateSummary(
                from: openTodoEntries,
                context: context,
                userProfile: userProfile,
                cacheKey: openTodoSummaryCacheKey
            )
        } catch {
            openTodoSummary = nil
        }
    }

    private func contextSnippet(for note: Note) -> String {
        let compact = note.transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(compact.prefix(140))
    }

    private func openNote(_ note: Note) {
        onOpenNote(note)
        dismiss()
    }

}

struct GooeySummaryLoadingView: View {
    let startColor: Color
    let endColor: Color
    var gradientColors: [Color]? = nil
    var showsContainer: Bool = true
    var primaryOpacity: Double = 1
    var secondaryOpacity: Double = 0.55

    private let containerWidth: CGFloat = 164
    private let containerHeight: CGFloat = 74
    private let blobSize: CGFloat = 115

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 0.9
            let rotation = time * 0.62
            let blueOrangeSpread = 0.18 + ((sin(time * 1.15) + 1) * 0.22)
            let blueOrangeStart = UnitPoint(
                x: 0.5 + cos(rotation) * blueOrangeSpread,
                y: 0.5 + sin(rotation) * blueOrangeSpread
            )
            let blueOrangeEnd = UnitPoint(
                x: 0.5 - cos(rotation) * blueOrangeSpread,
                y: 0.5 - sin(rotation) * blueOrangeSpread
            )

            ZStack {
                if showsContainer {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.cardBackground.opacity(0.72))
                }

                ZStack {
                    BlobShape(points: 5, amplitude: 2, time: time)
                        .fill(
                            LinearGradient(
                                colors: baseGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    BlobShape(points: 5, amplitude: 1.7, time: time * 0.82 + 1.3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.75),
                                    .orange.opacity(0.75)
                                ],
                                startPoint: blueOrangeStart,
                                endPoint: blueOrangeEnd
                            )
                        )
                        .blendMode(.plusLighter)
                }
                .frame(width: blobSize, height: blobSize)
                .blur(radius: 12)
                .opacity(primaryOpacity)

                BlobShape(points: 6, amplitude: 1.2, time: time * 0.82 + 3.4)
                    .fill(
                        LinearGradient(
                            colors: secondaryGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: blobSize * 0.84, height: blobSize * 0.84)
                    .blur(radius: 28)
                    .opacity(secondaryOpacity)
                    .blendMode(.plusLighter)

                if showsContainer {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Theme.primaryText.opacity(0.08), lineWidth: 1)
                }
            }
            .frame(width: showsContainer ? containerWidth : blobSize, height: showsContainer ? containerHeight : blobSize)
        }
    }

    private var primaryGradientColors: [Color] {
        if let gradientColors, !gradientColors.isEmpty {
            return gradientColors
        }

        return [startColor, endColor]
    }

    private var baseGradientColors: [Color] {
        if gradientColors?.isEmpty == false {
            return [Color(hex: "#33BF99"), .green, .pink, .indigo]
        }

        return primaryGradientColors
    }

    private var secondaryGradientColors: [Color] {
        primaryGradientColors.map { $0.opacity(0.42) }
    }
}

struct BlobShape: Shape {
    let points: Int
    let deformation: CGFloat
    let time: CGFloat

    init(points: Int = 6, amplitude: CGFloat = 4, time: CGFloat = 0) {
        self.points = max(3, min(points, 32))
        self.deformation = amplitude
        self.time = time
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        var blobPoints: [CGPoint] = []
        for index in 0..<points {
            let angle = CGFloat(index) / CGFloat(points) * .pi * 2
            let s1 = sin(angle * 5.0 - time + 512.0) * 2.0
            let s2 = sin(angle * 2.0 + time * 1.8 + 21.0) * 2.0
            let noise = (s1 + s2) * deformation
            let dynamicRadius = radius + noise
            let x = center.x + cos(angle) * dynamicRadius
            let y = center.y + sin(angle) * dynamicRadius
            blobPoints.append(CGPoint(x: x, y: y))
        }

        guard let firstPoint = blobPoints.first else {
            return path
        }

        path.move(to: firstPoint)

        for index in 0..<points {
            let currentPoint = blobPoints[index]
            let nextPoint = blobPoints[(index + 1) % points]
            let previousPoint = blobPoints[(index - 1 + points) % points]

            let control1 = CGPoint(
                x: currentPoint.x + (nextPoint.x - previousPoint.x) * 0.2,
                y: currentPoint.y + (nextPoint.y - previousPoint.y) * 0.2
            )

            let control2 = CGPoint(
                x: nextPoint.x - (blobPoints[(index + 2) % points].x - currentPoint.x) * 0.2,
                y: nextPoint.y - (blobPoints[(index + 2) % points].y - currentPoint.y) * 0.2
            )

            path.addCurve(to: nextPoint, control1: control1, control2: control2)
        }

        path.closeSubpath()
        return path
    }
}
