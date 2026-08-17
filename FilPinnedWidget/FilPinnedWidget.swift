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
            switch family {
            case .accessoryRectangular:
                AccessoryRectangular(snapshot: entry.snapshot)
            case .accessoryCircular:
                AccessoryCircular(snapshot: entry.snapshot)
            case .accessoryInline:
                AccessoryInline(snapshot: entry.snapshot)
            default:
                if let snapshot = entry.snapshot {
                    pinnedContent(snapshot)
                } else {
                    emptyState
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: isAccessory ? .center : .topLeading
        )
        .widgetURL(destinationURL)
        // Applied here rather than in the Widget body because the right background depends on the
        // family, and the family is only in scope inside the view.
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular:
                // The system's own translucent disc. Painting our own would fight the lock screen's
                // material instead of sitting in it.
                AccessoryWidgetBackground()
            case .accessoryRectangular, .accessoryInline:
                Color.clear
            default:
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
    }

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular || family == .accessoryInline
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

            Text("\(snapshot.count) \(snapshot.count == 1 ? "thought" : "thoughts")")
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

// MARK: - Lock-screen accessories

/// The permanent door.
///
/// The Live Activity is capped near eight hours *and* shares a single system slot, so a delivery or
/// a timer evicts it — it can carry the loud transient moment but not the standing one. These can.
///
/// What they cannot carry is colour. iOS renders accessory widgets into a vibrant monochrome
/// material, so the folder's gradient — the app's loudest identity signal everywhere else —
/// collapses to one luminance ramp. Shape survives: `FolderShape` is a silhouette, and a blob's
/// seed is precisely what makes it *that* fil and not another. So these lean on shape where the
/// systemSmall widget leans on colour, and fill flat rather than with a gradient that would only be
/// flattened into mud.

/// Name, count, and the fils themselves as silhouettes — the closest thing to the Live Activity's
/// peek that survives on a locked screen.
private struct AccessoryRectangular: View {
    let snapshot: PinnedFolderWidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let snapshot {
                HStack(spacing: 5) {
                    FolderShape()
                        .fill(.primary)
                        .frame(width: 12, height: 12)
                    Text(snapshot.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text("\(snapshot.count) \(snapshot.count == 1 ? "thought" : "thoughts")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Capped at five: the row is ~160pt wide and these are identity, not inventory.
                HStack(spacing: 3) {
                    ForEach(Array(snapshot.blobs.prefix(5).enumerated()), id: \.offset) { _, blob in
                        LiveActivityBlobShape(seed: blob.seed)
                            .fill(.primary.opacity(0.75))
                            .frame(width: 9, height: 9)
                    }
                }
                .accessibilityHidden(true)
            } else {
                Text("No pinned folder")
                    .font(.headline)
                Text("Pin one to see it here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Folder glyph over the count. Too small for a name, so it answers "how much is in there" only.
private struct AccessoryCircular: View {
    let snapshot: PinnedFolderWidgetSnapshot?

    var body: some View {
        VStack(spacing: 1) {
            FolderShape()
                .fill(.primary)
                .frame(width: 17, height: 17)
            if let snapshot {
                Text("\(snapshot.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
        }
        .opacity(snapshot == nil ? 0.5 : 1)
        .accessibilityLabel(
            snapshot.map { "\($0.name), \($0.count) thoughts" } ?? "No pinned folder"
        )
    }
}

/// A single line beside the clock. Inline accepts only text and an SF Symbol — no custom shape —
/// so this is the one accessory where the folder is named rather than drawn.
private struct AccessoryInline: View {
    let snapshot: PinnedFolderWidgetSnapshot?

    var body: some View {
        if let snapshot {
            Label(
                "\(snapshot.name) · \(snapshot.count)",
                systemImage: "folder.fill"
            )
        } else {
            Label("No pinned folder", systemImage: "folder")
        }
    }
}

struct FilPinnedWidget: Widget {
    let kind: String = "FilPinnedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FilPinnedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pinned Folder")
        .description("Your pinned folder at a glance.")
        .supportedFamilies([
            .systemSmall,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

#Preview(as: .systemSmall) {
    FilPinnedWidget()
} timeline: {
    PinnedFolderEntry(date: .now, snapshot: .sample)
    PinnedFolderEntry(date: .now, snapshot: nil)
}

#Preview(as: .accessoryRectangular) {
    FilPinnedWidget()
} timeline: {
    PinnedFolderEntry(date: .now, snapshot: .sample)
    PinnedFolderEntry(date: .now, snapshot: nil)
}

#Preview(as: .accessoryCircular) {
    FilPinnedWidget()
} timeline: {
    PinnedFolderEntry(date: .now, snapshot: .sample)
    PinnedFolderEntry(date: .now, snapshot: nil)
}

#Preview(as: .accessoryInline) {
    FilPinnedWidget()
} timeline: {
    PinnedFolderEntry(date: .now, snapshot: .sample)
    PinnedFolderEntry(date: .now, snapshot: nil)
}
