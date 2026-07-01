import ActivityKit
import WidgetKit
import SwiftUI

struct PinnedFilLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var previewText: String
        var keyword: String
        var gradientStartHex: String
        var gradientEndHex: String
        var updatedAt: Date
    }

    var noteID: UUID
}

struct FilPinnedWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PinnedFilLiveActivityAttributes.self) { context in
            PinnedFilLockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.06))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    PinnedFilExpandedContent(state: context.state)
                }
            } compactLeading: {
                FilLogoMark(size: 15)
            } compactTrailing: {
                Text(compactTitle(context.state))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            } minimal: {
                FilLogoMark(size: 13)
            }
            .widgetURL(URL(string: "fil://pinned?id=\(context.attributes.noteID.uuidString)"))
            .keylineTint(Color(red: 0.2, green: 0.75, blue: 0.6))
        }
    }

    private func displayTitle(_ state: PinnedFilLiveActivityAttributes.ContentState) -> String {
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "pinned fil" : title
    }

    private func compactTitle(_ state: PinnedFilLiveActivityAttributes.ContentState) -> String {
        String(displayTitle(state).prefix(6))
    }
}

private struct PinnedFilLockScreenView: View {
    let state: PinnedFilLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FilLogoMark(size: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(displayPreview)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 124, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilLiveActivityGradient(startHex: state.gradientStartHex, endHex: state.gradientEndHex))
    }

    private var displayTitle: String {
        state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "pinned fil" : state.title
    }

    private var displayPreview: String {
        state.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "open Fil to continue" : state.previewText
    }
}

private struct PinnedFilExpandedContent: View {
    let state: PinnedFilLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FilLogoMark(size: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(displayPreview)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 7)
        .background(FilLiveActivityGradient(startHex: state.gradientStartHex, endHex: state.gradientEndHex).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var displayTitle: String {
        state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "pinned fil" : state.title
    }

    private var displayPreview: String {
        state.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "open Fil to continue" : state.previewText
    }
}

private struct FilLogoMark: View {
    let size: CGFloat

    var body: some View {
        Image("FilLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct FilLiveActivityGradient: View {
    let startHex: String
    let endHex: String

    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: startHex),
                Color(hex: endHex)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(Color.white.opacity(0.18))
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: cleanedHex)
        var rgb: UInt64 = 0

        guard scanner.scanHexInt64(&rgb), cleanedHex.count == 6 else {
            self.init(red: 0.25, green: 0.55, blue: 0.85)
            return
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension PinnedFilLiveActivityAttributes {
    fileprivate static var preview: PinnedFilLiveActivityAttributes {
        PinnedFilLiveActivityAttributes(noteID: UUID())
    }
}

extension PinnedFilLiveActivityAttributes.ContentState {
    fileprivate static var sample: PinnedFilLiveActivityAttributes.ContentState {
        PinnedFilLiveActivityAttributes.ContentState(
            title: "Follow up with Jordan",
            previewText: "Draft the intake summary and check whether the PDF attachment made it into the case note.",
            keyword: "todo",
            gradientStartHex: "#33BF99",
            gradientEndHex: "#408CD9",
            updatedAt: .now
        )
    }
}

#Preview("Pinned Fil", as: .content, using: PinnedFilLiveActivityAttributes.preview) {
    FilPinnedWidgetLiveActivity()
} contentStates: {
    PinnedFilLiveActivityAttributes.ContentState.sample
}
