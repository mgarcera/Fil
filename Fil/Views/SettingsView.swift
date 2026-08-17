import SwiftUI
import SwiftData

/// The app's settings, reached from the home header. Reuses the onboarding aesthetic —
/// a capsule tab bar over an animated ambient gradient, with a glass card below — but
/// each tab is a real settings section and every control applies live (no save step).
struct SettingsView: View {
    /// Screensaver launchers, supplied by ContentView (each dismisses settings, then launches).
    var screensaverOptions: [ScreensaverOption] = []
    /// Whether the library has enough fils for auto-screensaver to actually run (else the toggle
    /// is disabled so it can't be switched on to no effect).
    var autoScreensaverUnlocked: Bool = true

    @AppStorage("autoScreensaverEnabled") private var autoScreensaverEnabled = false
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.auto.rawValue
    @AppStorage(LockScreenActivity.storageKey, store: .filAppGroup) private var lockScreenActivityRaw = LockScreenActivity.off.rawValue

    @State private var section: SettingsSection = .appearance
    @State private var showFeedback = false
    @State private var showCaptureAnywhere = false
    @State private var contentVisible = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            ambientBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                sectionTabs
                    .padding(.top, 32)

                if section == .subscription {
                    // The paywall (SubscriptionStoreView) scrolls + reflects Free/Pro on its own, so
                    // it's rendered full-height here rather than nested in the card's ScrollView.
                    PaywallView(showsDismiss: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blurOpacityEffect(contentVisible)
                } else {
                    ScrollView {
                        sectionCard
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .task {
            withAnimation(.smooth(duration: 0.7, extraBounce: 0)) {
                contentVisible = true
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet()
        }
        .sheet(isPresented: $showCaptureAnywhere) {
            CaptureAnywhereView()
        }
    }

    // MARK: - Tabs

    private var sectionTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(SettingsSection.allCases) { tab in
                    Button {
                        guard section != tab else { return }
                        SoundscapeManager.shared.playTabSound()
                        withAnimation(.snappy) { section = tab }
                    } label: {
                        let isSelected = section == tab
                        Text(tab.title)
                            .font(Theme.fredoka(19, weight: .medium))
                            .foregroundStyle(isSelected ? Color.black : .white)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
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
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .blurOpacityEffect(contentVisible)
    }

    // MARK: - Section card

    private var sectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch section {
            case .appearance:
                appearanceSection

            case .subscription:
                // Rendered full-height in the body (not inside the card's ScrollView).
                EmptyView()

            case .about:
                aboutContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .blurOpacityEffect(contentVisible)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            appearanceSectionRow

            sectionDivider

            settingToggle("Sound effects", icon: "music.note", isOn: $soundEnabled)

            sectionDivider

            lockScreenSection

            sectionDivider

            Button { showCaptureAnywhere = true } label: {
                HStack {
                    settingLabel("Capture from anywhere", icon: "bolt.badge.clock")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if !screensaverOptions.isEmpty {
                sectionDivider

                VStack(alignment: .leading, spacing: 16) {
                    settingLabel("Screensavers", icon: "zzz")
                    // Indent rows so their icons line up under the word "Screensavers"
                    // (header icon frame width 22 + HStack spacing 12).
                    ForEach(screensaverOptions) { screensaverRow($0) }
                        .padding(.leading, 34)
                }
            }

            sectionDivider

            settingToggle(
                "Auto screensaver",
                icon: "power",
                description: autoScreensaverUnlocked
                    ? "After a minute of idling, play the last opened screensaver. This keeps your screen awake, so watch your battery."
                    : "Unlocks once you have a few more thoughts.",
                isOn: $autoScreensaverEnabled
            )
            .disabled(!autoScreensaverUnlocked)
            .opacity(autoScreensaverUnlocked ? 1 : 0.5)
        }
    }

    /// Chooses which Live Activity Fil keeps on the Lock Screen / Dynamic Island. "Folder" pins from a
    /// folder's swipe action; choosing it here with nothing pinned simply shows nothing until you pin one.
    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingLabel("Live Widget", icon: "lock.iphone")
            Text("Keep a live widget on the Lock Screen and Dynamic Island. Bin shows your unsorted thoughts, while Folder shows your chosen folder.")
                .font(Theme.fredoka(13, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(LockScreenActivity.allCases) { lockScreenPill($0) }
            }
            .padding(.leading, 34)
        }
    }

    private func lockScreenPill(_ option: LockScreenActivity) -> some View {
        let isSelected = lockScreenActivityRaw == option.rawValue
        return Button {
            SoundscapeManager.shared.playTabSound()
            withAnimation(.snappy) { lockScreenActivityRaw = option.rawValue }
        } label: {
            Text(option.title)
                .font(Theme.fredoka(18, weight: .medium))
                .foregroundStyle(isSelected ? Color.black : .white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    /// Appearance: Auto (follow system) / Light / Dark, as capsules matching the Live Widget pills.
    private var appearanceSectionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingLabel("Appearance", icon: "circle.lefthalf.filled")
            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases) { appearancePill($0) }
            }
            .padding(.leading, 34)
        }
    }

    private func appearancePill(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceRaw == mode.rawValue
        return Button {
            SoundscapeManager.shared.playLightModeSound()
            withAnimation(.snappy) { appearanceRaw = mode.rawValue }
        } label: {
            Text(mode.title)
                .font(Theme.fredoka(18, weight: .medium))
                .foregroundStyle(isSelected ? Color.black : .white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    /// The hairline between settings options (matches the About section's dividers).
    private var sectionDivider: some View {
        Divider().overlay(Color.white.opacity(0.14))
    }

    private func settingToggle(_ title: String, icon: String, description: String? = nil, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: isOn) {
                settingLabel(title, icon: icon)
            }
            .toggleStyle(BorderedToggleStyle(tint: section.backgroundColors[0]))

            if let description {
                Text(description)
                    .font(Theme.fredoka(13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A leading SF Symbol + a title, sized to line up icons across rows. Shared by the toggles and
    /// the screensavers header.
    private func settingLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22)
            Text(title)
                .font(Theme.fredoka(17, weight: .regular))
                .foregroundStyle(.white)
        }
    }

    /// A screensaver as a vertical row: icon + name + a one-line description (or the unlock
    /// requirement when locked). Tapping launches it; locked rows are dimmed and non-tappable.
    private func screensaverRow(_ option: ScreensaverOption) -> some View {
        Button(action: option.action) {
            HStack(spacing: 12) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(Theme.fredoka(17, weight: .regular))
                            .foregroundStyle(.white)
                        if !option.isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Text(option.isUnlocked ? option.description : "Unlocks at \(option.requirement)")
                        .font(Theme.fredoka(13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .opacity(option.isUnlocked ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!option.isUnlocked)
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            aboutRow("Open feedback form") { showFeedback = true }
            aboutRow("Rate Fil on the App Store") { openURL(FilLinks.writeReview) }

            Divider().overlay(Color.white.opacity(0.14))

            aboutRow("Website") { openURL(FilLinks.website) }
            aboutRow("Support") { openURL(FilLinks.support) }
            aboutRow("Privacy policy") { openURL(FilLinks.privacyPolicy) }
            aboutRow("Terms of service") { openURL(FilLinks.termsOfService) }

            Divider().overlay(Color.white.opacity(0.14))

            Text("Version \(appVersion)")
                .font(Theme.dmSans(12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// A tappable About row — a lowercase label with a trailing "open" chevron. Used by the external
    /// Website / Support / Privacy / Terms / feedback / Rate links.
    private func aboutRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(Theme.fredoka(17, weight: .regular))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    // MARK: - Background

    private var ambientBackground: some View {
        let colors = section.backgroundColors

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
        .animation(.easeInOut(duration: 0.8), value: section)
    }
}

/// A pill switch that keeps a clear outline when OFF (so it reads against the dark background),
/// and fills with the section tint when ON.
private struct BorderedToggleStyle: ToggleStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? tint : Color.white.opacity(0.06))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(configuration.isOn ? 0 : 0.4), lineWidth: 1.5)
                    }
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: configuration.isOn ? 11 : -11)   // glides between the two ends
            }
            .frame(width: 51, height: 31)
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

/// A screensaver launcher shown in Settings → Appearance. Built by ContentView (which owns the
/// launch + unlock logic); the action dismisses settings then launches the screensaver.
struct ScreensaverOption: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let description: String     // one-line sub-description shown in the vertical list
    let isUnlocked: Bool
    let requirement: String     // e.g. "10 thoughts" (shown when locked)
    let action: () -> Void
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case subscription
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .subscription: "Fil Pro"
        case .about: "About"
        }
    }

    /// Reuses the four ambient gradient palettes so each section has its own mood.
    var backgroundColors: [Color] {
        switch self {
        case .appearance:
            [Color(hex: "#0EA5E9"), Color(hex: "#14B8A6"), Color(hex: "#22C55E")]
        case .subscription:
            [Color(hex: "#F59E0B"), Color(hex: "#F97316"), Color(hex: "#EAB308")]
        case .about:
            [Color(hex: "#6659CC"), Color(hex: "#408CD9"), Color(hex: "#E8196A")]
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
