//
//  FilPinnedWidget.swift
//  FilPinnedWidget
//
//  Created by Mason Garcera on 6/30/26.
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.masongarcera.Fil"
private let pinnedFilKey = "pinnedFilSnapshot"

/// Mirrors the app's `PinnedFilSnapshot`, decoded from the shared App Group container.
struct PinnedFilWidgetSnapshot: Codable {
    var id: UUID
    var title: String
    var previewText: String
    var keyword: String
    var gradientStartHex: String
    var gradientEndHex: String
    var updatedAt: Date

    static let sample = PinnedFilWidgetSnapshot(
        id: UUID(),
        title: "Follow up with Jordan",
        previewText: "Draft the intake summary and check whether the PDF attachment made it into the case note.",
        keyword: "todo",
        gradientStartHex: "#33BF99",
        gradientEndHex: "#408CD9",
        updatedAt: Date()
    )
}

struct PinnedFilEntry: TimelineEntry {
    let date: Date
    let snapshot: PinnedFilWidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedFilEntry {
        PinnedFilEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedFilEntry) -> Void) {
        completion(PinnedFilEntry(date: Date(), snapshot: loadSnapshot() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedFilEntry>) -> Void) {
        let entry = PinnedFilEntry(date: Date(), snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadSnapshot() -> PinnedFilWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: pinnedFilKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PinnedFilWidgetSnapshot.self, from: data)
    }
}

struct FilPinnedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                pinnedContent(snapshot)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(destinationURL)
    }

    private var destinationURL: URL? {
        if let snapshot = entry.snapshot {
            return URL(string: "fil://pinned?id=\(snapshot.id.uuidString)")
        }
        return URL(string: "fil://draft")
    }

    private func pinnedContent(_ snapshot: PinnedFilWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FilBlobMark(
                size: family == .systemSmall ? 30 : 34,
                startHex: snapshot.gradientStartHex,
                endHex: snapshot.gradientEndHex
            )

            Spacer(minLength: 0)

            Text(displayTitle(snapshot))
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(family == .systemSmall ? 3 : 2)

            if family != .systemSmall {
                Text(displayPreview(snapshot))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilBlobMark(size: 30, startHex: "#33BF99", endHex: "#408CD9")
                .opacity(0.5)

            Spacer(minLength: 0)

            Text("no pinned fil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("pin a fil to see it here")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func displayTitle(_ snapshot: PinnedFilWidgetSnapshot) -> String {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "pinned fil" : title
    }

    private func displayPreview(_ snapshot: PinnedFilWidgetSnapshot) -> String {
        let preview = snapshot.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "open Fil to continue" : preview
    }
}

struct FilPinnedWidget: Widget {
    let kind: String = "FilPinnedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FilPinnedWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color(red: 0.06, green: 0.06, blue: 0.07)
                        if let snapshot = entry.snapshot {
                            FilLiveActivityBottomGlow(
                                startHex: snapshot.gradientStartHex,
                                endHex: snapshot.gradientEndHex
                            )
                        }
                    }
                }
        }
        .configurationDisplayName("Pinned Fil")
        .description("Your pinned fil at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    FilPinnedWidget()
} timeline: {
    PinnedFilEntry(date: .now, snapshot: .sample)
    PinnedFilEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemMedium) {
    FilPinnedWidget()
} timeline: {
    PinnedFilEntry(date: .now, snapshot: .sample)
}
