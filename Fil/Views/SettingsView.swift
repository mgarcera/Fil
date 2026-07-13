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
    @AppStorage("prefersLowercase") private var prefersLowercase = false
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("controlsOnLeft") private var controlsOnLeft = false

    @State private var section: SettingsSection = .appearance
    @State private var showFromMason = false
    @State private var contentVisible = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            ambientBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    sectionTabs
                    sectionCard
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
        }
        .sheet(isPresented: $showFromMason) {
            FromMasonFilCard()
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("fil")
                .font(Theme.dmSans(18, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Text("settings")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .blurOpacityEffect(contentVisible)
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
                            .font(Theme.dmSans(15, weight: .semibold))
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
        .blurOpacityEffect(contentVisible)
    }

    // MARK: - Section card

    private var sectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch section {
            case .writing:
                settingToggle(
                    "Use Lowercase",
                    description: "render titles and transcripts in lowercase for a more casual voice.",
                    isOn: $prefersLowercase
                )

            case .sound:
                settingToggle("Sound Effects", isOn: $soundEnabled)

            case .appearance:
                appearanceSection

            case .about:
                aboutContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .blurOpacityEffect(contentVisible)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingToggle("Dark Mode", isOn: $isDarkMode)

            sectionDivider

            settingToggle(
                "Left-handed",
                description: "put the search, fil, and send buttons on the left.",
                isOn: $controlsOnLeft
            )

            if !screensaverOptions.isEmpty {
                sectionDivider

                VStack(alignment: .leading, spacing: 14) {
                    Text("Screensavers")
                        .font(Theme.dmSans(16, weight: .medium))
                        .foregroundStyle(.white)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(screensaverOptions) { option in
                                Button(action: option.action) {
                                    HStack(spacing: 6) {
                                        if !option.isUnlocked {
                                            Image(systemName: "lock.fill").font(.system(size: 11))
                                        }
                                        Text(option.isUnlocked ? option.title : "\(option.title) · \(option.requirement)")
                                            .font(Theme.dmSans(14, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                                    .overlay { Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1) }
                                    .opacity(option.isUnlocked ? 1 : 0.5)
                                }
                                .buttonStyle(.plain)
                                .disabled(!option.isUnlocked)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            sectionDivider

            settingToggle(
                "Auto Screensaver",
                description: autoScreensaverUnlocked
                    ? "after a minute of idling, play the last opened screensaver. this keeps your screen awake, so watch your battery."
                    : "unlocks once you have a few more fils.",
                isOn: $autoScreensaverEnabled
            )
            .disabled(!autoScreensaverUnlocked)
            .opacity(autoScreensaverUnlocked ? 1 : 0.5)
        }
    }

    /// The hairline between settings options (matches the About section's dividers).
    private var sectionDivider: some View {
        Divider().overlay(Color.white.opacity(0.14))
    }

    private func settingToggle(_ title: String, description: String? = nil, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(Theme.dmSans(16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .tint(section.backgroundColors[0])

            if let description {
                Text(description)
                    .font(Theme.dmSans(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            aboutRow("from mason") { showFromMason = true }

            Divider().overlay(Color.white.opacity(0.14))

            aboutRow("support") { openURL(FilLinks.support) }
            aboutRow("privacy policy") { openURL(FilLinks.privacyPolicy) }
            aboutRow("terms of service") { openURL(FilLinks.termsOfService) }
            aboutRow("contact & feedback") { openURL(FilLinks.contactEmail) }
            aboutRow("rate fil") { openURL(FilLinks.writeReview) }

            Divider().overlay(Color.white.opacity(0.14))

            Text("version \(appVersion)")
                .font(Theme.dmMono(12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// A tappable About row — a lowercase label with a trailing "open" chevron. Shared by the
    /// "from mason" sheet and the external Privacy / Terms / Contact / Rate links.
    private func aboutRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(Theme.dmSans(16, weight: .medium))
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

/// A screensaver launcher shown in Settings → Appearance. Built by ContentView (which owns the
/// launch + unlock logic); the action dismisses settings then launches the screensaver.
struct ScreensaverOption: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let isUnlocked: Bool
    let requirement: String     // e.g. "10 fils" (shown when locked)
    let action: () -> Void
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case writing
    case sound
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .writing: "Writing"
        case .sound: "Sound"
        case .about: "About"
        }
    }

    /// Reuses the four ambient gradient palettes so each section has its own mood.
    var backgroundColors: [Color] {
        switch self {
        case .appearance:
            [Color(hex: "#0EA5E9"), Color(hex: "#14B8A6"), Color(hex: "#22C55E")]
        case .writing:
            [Color(hex: "#6366F1"), Color(hex: "#EC4899"), Color(hex: "#0EA5E9")]
        case .sound:
            [Color(hex: "#4F46E5"), Color(hex: "#7C3AED"), Color(hex: "#2563EB")]
        case .about:
            [Color(hex: "#F59E0B"), Color(hex: "#F97316"), Color(hex: "#EAB308")]
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
