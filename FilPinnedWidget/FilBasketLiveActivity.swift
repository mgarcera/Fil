import ActivityKit
import WidgetKit
import SwiftUI

/// Widget-side mirror of the app's `FilBasketLiveActivityAttributes`. Must stay structurally
/// identical to the app copy so ActivityKit can decode the shared content state.
struct FilBasketLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var blobs: [FilActivityBlob]
        var updatedAt: Date
    }
}

struct FilBasketLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FilBasketLiveActivityAttributes.self) { context in
            FilBasketLockScreenView(state: context.state)
                .activityBackgroundTint(nil)   // system default (adaptive/translucent) rather than a solid fill
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "fil://basket"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Bin")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FilActivityBlobRow(blobs: context.state.blobs)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                }
            } compactLeading: {
                Text("Bin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } minimal: {
                Text("Bin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .widgetURL(URL(string: "fil://basket"))
            .keylineTint(Color(red: 0.2, green: 0.75, blue: 0.6))
            .contentMargins(.all, 0, for: .expanded)
        }
    }
}

private struct FilBasketLockScreenView: View {
    let state: FilBasketLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            FilActivityBlobRow(blobs: state.blobs)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            FilLiveActivityBottomGlow(startHex: binStartHex, endHex: binEndHex)
        }
    }

    private var headline: String {
        let n = state.count
        return "\(n) \(n == 1 ? "item" : "items") in your Bin"
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
            count: 5,
            blobs: FilActivityBlob.samples,
            updatedAt: .now
        )
    }
}

#Preview("Bin", as: .content, using: FilBasketLiveActivityAttributes.preview) {
    FilBasketLiveActivity()
} contentStates: {
    FilBasketLiveActivityAttributes.ContentState.sample
}
