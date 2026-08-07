import ActivityKit
import WidgetKit
import SwiftUI

/// Widget-side mirror of the app's `FilBasketLiveActivityAttributes`. Must stay structurally
/// identical to the app copy so ActivityKit can decode the shared content state.
struct FilBasketLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var recentTitles: [String]
        var updatedAt: Date
    }
}

struct FilBasketLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FilBasketLiveActivityAttributes.self) { context in
            FilBasketLockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.06))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "fil://basket"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FilBlobMark(size: 24, startHex: basketStartHex, endHex: basketEndHex)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FilBasketExpandedContent(state: context.state)
                }
            } compactLeading: {
                FilBlobMark(size: 16, startHex: basketStartHex, endHex: basketEndHex)
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } minimal: {
                Text("\(context.state.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .widgetURL(URL(string: "fil://basket"))
            .keylineTint(Color(red: 0.2, green: 0.75, blue: 0.6))
            .contentMargins(.all, 0, for: .expanded)
        }
    }
}

private let basketStartHex = "#33BF99"
private let basketEndHex = "#408CD9"

private struct FilBasketLockScreenView: View {
    let state: FilBasketLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FilBlobMark(size: 26, startHex: basketStartHex, endHex: basketEndHex)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                ForEach(Array(state.recentTitles.prefix(3).enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            FilLiveActivityBottomGlow(startHex: basketStartHex, endHex: basketEndHex)
        }
    }

    private var headline: String {
        state.count == 1 ? "1 in your basket" : "\(state.count) in your basket"
    }
}

private struct FilBasketExpandedContent: View {
    let state: FilBasketLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(state.recentTitles.prefix(3).enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(alignment: .bottom) {
            FilLiveActivityBottomGlow(startHex: basketStartHex, endHex: basketEndHex)
        }
    }
}

extension FilBasketLiveActivityAttributes {
    fileprivate static var preview: FilBasketLiveActivityAttributes {
        FilBasketLiveActivityAttributes()
    }
}

extension FilBasketLiveActivityAttributes.ContentState {
    fileprivate static var sample: FilBasketLiveActivityAttributes.ContentState {
        FilBasketLiveActivityAttributes.ContentState(
            count: 3,
            recentTitles: ["Call the framer back", "gift idea: cyanotype kit", "https://getdroppy.app"],
            updatedAt: .now
        )
    }
}

#Preview("Basket", as: .content, using: FilBasketLiveActivityAttributes.preview) {
    FilBasketLiveActivity()
} contentStates: {
    FilBasketLiveActivityAttributes.ContentState.sample
}
