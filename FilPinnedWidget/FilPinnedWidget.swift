//
//  FilPinnedWidget.swift
//  FilPinnedWidget
//
//  Created by Mason Garcera on 6/30/26.
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.masongarcera.Fil"
private let pinnedFolderFileName = "pinnedFolderSnapshot.json"

/// Mirrors the app's `PinnedFolderSnapshot`, decoded from the shared App Group container.
struct PinnedFolderWidgetSnapshot: Codable {
    var id: UUID
    var name: String
    var count: Int
    var blobs: [FilActivityBlob]
    var gradientStartHex: String
    var gradientEndHex: String
    var updatedAt: Date

    static let sample = PinnedFolderWidgetSnapshot(
        id: UUID(),
        name: "House move",
        count: 5,
        blobs: FilActivityBlob.samples,
        gradientStartHex: "#33BF99",
        gradientEndHex: "#408CD9",
        updatedAt: Date()
    )
}

struct PinnedFolderEntry: TimelineEntry {
    let date: Date
    let snapshot: PinnedFolderWidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedFolderEntry {
        PinnedFolderEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedFolderEntry) -> Void) {
        completion(PinnedFolderEntry(date: Date(), snapshot: loadSnapshot() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedFolderEntry>) -> Void) {
        let entry = PinnedFolderEntry(date: Date(), snapshot: loadSnapshot())
        // Self-heal: re-read the shared file periodically so the widget converges
        // on the current pin even if an explicit WidgetCenter reload is dropped
        // (or a stale timeline was restored when the widget was re-added).
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> PinnedFolderWidgetSnapshot? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(pinnedFolderFileName),
            let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PinnedFolderWidgetSnapshot.self, from: data)
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
            return URL(string: "fil://folder?id=\(snapshot.id.uuidString)")
        }
        return URL(string: "fil://draft")
    }

    private func pinnedContent(_ snapshot: PinnedFolderWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FolderMark(
                size: family == .systemSmall ? 30 : 34,
                startHex: snapshot.gradientStartHex,
                endHex: snapshot.gradientEndHex
            )

            Spacer(minLength: 0)

            Text(snapshot.name)
                .font(.system(size: family == .systemSmall ? 15 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(snapshot.count) \(snapshot.count == 1 ? "fil" : "fils")")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilBlobMark(size: 30, startHex: "#33BF99", endHex: "#408CD9")
                .opacity(0.5)

            Spacer(minLength: 0)

            Text("no pinned folder")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("pin a folder to see it here")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
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
        .configurationDisplayName("Pinned Folder")
        .description("Your pinned folder at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    FilPinnedWidget()
} timeline: {
    PinnedFolderEntry(date: .now, snapshot: .sample)
    PinnedFolderEntry(date: .now, snapshot: nil)
}
