import SwiftUI
import AppIntents

/// Surfaces Fil's system-capture entry points, which already work but are otherwise invisible: the
/// Action Button, Control Center controls, Siri phrases, and the Shortcuts app.
struct CaptureAnywhereView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Capture a thought without opening Fil first. Set any of these up once.")
                        .font(Theme.dmSans(14))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    section(
                        "Action Button", "button.horizontal.top.press",
                        "Settings › Action Button › Shortcut, then choose “Add to Fil.” One press drops a thought straight in."
                    )
                    section(
                        "Control Center", "switch.2",
                        "Edit Control Center, tap ＋, and add a Fil control: “Record in fil” starts a voice note, “Write in fil” opens the composer."
                    )
                    section(
                        "Siri", "mic.badge.plus",
                        "Say “Add to Fil,” “Fil this in Fil,” or “New fil in Fil,” and Siri captures what you say next."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        label("Shortcuts", "square.stack.3d.up")
                        Text("Build your own automations around Fil in the Shortcuts app.")
                            .font(Theme.dmSans(13)).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automatic)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .navigationTitle("Capture from anywhere")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ icon: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title, icon)
            Text(body)
                .font(Theme.dmSans(13)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.primaryText.opacity(0.85)).frame(width: 24)
            Text(title).font(Theme.fredoka(17, weight: .medium)).foregroundStyle(Theme.primaryText)
        }
    }
}
