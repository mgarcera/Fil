import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        // New users land straight in the app (composer + home). The action-first onboarding
        // (first-fil → congratulation → "from mason" seed fil) lives in ContentView; the old
        // summary-preview onboarding is gone. See docs/onboarding/onboarding-design.md.
        ContentView()
    }
}

struct OnboardingView: View {
    let existingProfile: UserProfile?
    let showsSkipControl: Bool
    let onFinish: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("didSkipSetup") private var didSkipSetup = false

    @State private var selectedScope = SummaryScope.thisWeek
    @AppStorage("prefersLowercase") private var prefersLowercase = false
    @State private var showSkipConfirmation = false
    @State private var showFromMason = false
    @State private var titleProgress: CGFloat = 0
    @State private var contentVisible = false

    init(
        existingProfile: UserProfile? = nil,
        showsSkipControl: Bool = true,
        onFinish: (() -> Void)? = nil
    ) {
        self.existingProfile = existingProfile
        self.showsSkipControl = showsSkipControl
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            ambientBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    hero
                    summaryScopeSelector
                    previewCard
                    preferencesCard

                    controls
                    fromMasonEntry
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            withAnimation(.smooth(duration: 0.7, extraBounce: 0)) {
                contentVisible = true
            }

            withAnimation(.smooth(duration: 1.8, extraBounce: 0).delay(0.15)) {
                titleProgress = 1
            }
        }
        .alert("Skip setup?", isPresented: $showSkipConfirmation) {
            Button("Skip for now", role: .destructive) {
                didSkipSetup = true
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Skip, but Fil will use its default settings until you change them.")
        }
        .sheet(isPresented: $showFromMason) {
            FromMasonFilCard()
            .presentationDetents([.large])
            .presentationBackground(Theme.background)
        }
    }

    private var header: some View {
        HStack {
            Text("fil")
                .font(Theme.dmSans(18, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Text(existingProfile == nil ? "setup" : "settings")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .blurOpacityEffect(contentVisible)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your view.")
                .font(Theme.dmSans(34, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Preview how Fil can zoom out across your thoughts.")
                .font(Theme.dmSans(16, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .blurOpacityEffect(contentVisible)
        }
    }

    private var summaryScopeSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(SummaryScope.allCases) { scope in
                        Button {
                            guard selectedScope != scope else { return }
                            SoundscapeManager.shared.playTabSound()
                            withAnimation(.snappy) {
                                selectedScope = scope
                            }
                        } label: {
                            let isSelected = selectedScope == scope

                            Text(scope.title)
                                .font(Theme.dmSans(15, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.black : .white)
                                .padding(.horizontal, 18)
                                .frame(height: 42)
                                .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(isSelected ? 0 : 0.14), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .blurOpacityEffect(contentVisible)

        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("scope")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.65))

            Text(selectedScope.previewSummary)
                .font(Theme.dmSans(14))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.white.opacity(0.14))

            Text("sample")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.65))

            Text(previewSource)
                .font(Theme.dmMono(13))
                .italic()
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.white.opacity(0.14))

            Text("summary")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.65))

            AnimatedGradientRevealText(
                text: previewExample,
                elementDuration: 0.18,
                perElementDelay: 0.011,
                minDuration: 0.55,
                extraSlices: 10
            )
                .font(Theme.dmSans(15, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.45))
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .blurOpacityEffect(contentVisible)
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $prefersLowercase) {
                Text("Use lowercase")
                    .font(Theme.dmSans(16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .tint(selectedScope.backgroundColors[0])
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .blurOpacityEffect(contentVisible)
    }

    private var fromMasonEntry: some View {
        Button {
            showFromMason = true
        } label: {
            HStack(spacing: 14) {
                Text("from mason")
                    .font(Theme.dmSans(16, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .blurOpacityEffect(contentVisible)
    }

    private var previewExample: String {
        let example = selectedScope.previewRewrite
        guard prefersLowercase else { return example }
        return example.lowercased()
    }

    private var previewSource: String {
        selectedScope.previewSource
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                saveProfile()
            } label: {
                Text(existingProfile == nil ? "Continue" : "Save changes")
                    .font(Theme.dmSans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selectedScope.backgroundColors[0], in: Capsule())
            }
            .blurOpacityEffect(contentVisible)

            if showsSkipControl {
                Button {
                    showSkipConfirmation = true
                } label: {
                    Text("Skip for now")
                        .font(Theme.dmSans(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .blurOpacityEffect(contentVisible)
            }
        }
    }

    private var ambientBackground: some View {
        let colors = selectedScope.backgroundColors

        return ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.96), Color.black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(colors[0])
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -110, y: -210)

            Circle()
                .fill(colors[1])
                .frame(width: 280, height: 280)
                .blur(radius: 85)
                .offset(x: 120, y: -80)

            Circle()
                .fill(colors[2])
                .frame(width: 260, height: 260)
                .blur(radius: 95)
                .offset(x: 20, y: 240)

            Rectangle()
                .fill(.black.opacity(0.45))
        }
        .animation(.easeInOut(duration: 0.8), value: selectedScope)
    }

    private func saveProfile() {
        if let existingProfile {
            existingProfile.updatedAt = .now
        } else {
            modelContext.insert(UserProfile())
        }
        modelContext.saveOrLog()
        didSkipSetup = false
        onFinish?()
        if existingProfile != nil {
            dismiss()
        }
    }
}

private struct IntroTitleRenderer: TextRenderer, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let slices = layout.flatMap { $0 }.flatMap { $0 }

        for (index, slice) in slices.enumerated() {
            let sliceProgressIndex = CGFloat(slices.count) * progress
            let sliceProgress = max(min(sliceProgressIndex / CGFloat(index + 1), 1), 0)

            ctx.addFilter(.blur(radius: 6 - (6 * sliceProgress)))
            ctx.opacity = sliceProgress
            ctx.translateBy(x: 0, y: 6 - (6 * sliceProgress))
            ctx.draw(slice, options: .disablesSubpixelQuantization)
        }
    }
}

private enum SummaryScope: String, CaseIterable, Identifiable {
    case thisWeek
    case thisMonth
    case thisYear
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .thisYear: "This Year"
        case .allTime: "All Time"
        }
    }

    var previewSource: String {
        switch self {
        case .thisWeek:
            "coffee beans, cleaning before ben gets home, bike delivery, reloshare training"
        case .thisMonth:
            "farmers market errands, work follow-ups, sleep notes, training prep, house resets"
        case .thisYear:
            "new routines, practical errands, work shifts, relationship notes, small systems"
        case .allTime:
            "recurring threads across every fil: what keeps coming up, changing, and still needs attention"
        }
    }

    var previewRewrite: String {
        switch self {
        case .thisWeek:
            "this week, i’ve been keeping track of practical things: getting coffee beans, cleaning up before ben gets home, waiting on my bike, and preparing for training."
        case .thisMonth:
            "this month has a lot of small follow-through in it: errands, work updates, training prep, and a few notes about sleep and keeping the house reset."
        case .thisYear:
            "this year, the same kinds of threads keep showing up: making routines easier, staying on top of practical tasks, and noticing what needs more space."
        case .allTime:
            "across everything, fil would look for the patterns that keep returning: the people, places, tasks, and decisions that have quietly shaped the notes over time."
        }
    }

    var previewSummary: String {
        switch self {
        case .thisWeek:
            "A short recap of the most recent threads from the current week."
        case .thisMonth:
            "A wider pass across recurring tasks, notes, and unfinished things from the month."
        case .thisYear:
            "A broader summary of themes and patterns that have built up over the year."
        case .allTime:
            "A full-history view of what keeps returning across every fil."
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .thisWeek:
            [Color(hex: "#0EA5E9"), Color(hex: "#14B8A6"), Color(hex: "#22C55E")]
        case .thisMonth:
            [Color(hex: "#6366F1"), Color(hex: "#EC4899"), Color(hex: "#0EA5E9")]
        case .thisYear:
            [Color(hex: "#F59E0B"), Color(hex: "#F97316"), Color(hex: "#EAB308")]
        case .allTime:
            [Color(hex: "#4F46E5"), Color(hex: "#7C3AED"), Color(hex: "#2563EB")]
        }
    }
}

private extension View {
    func blurOpacityEffect(_ show: Bool) -> some View {
        self
            .blur(radius: show ? 0 : 8)
            .opacity(show ? 1 : 0)
            .offset(y: show ? 0 : 12)
    }
}
