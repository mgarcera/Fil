import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Shared link-fil helpers: detect a bare URL in typed text, and build a link `Note` that fetches
/// its real title + favicon in the background. Used by the canvas composer (typed links) and the
/// share-extension intake, so both create link fils identically.
enum LinkFil {
    /// A single bare URL becomes a link — no whitespace, http/https scheme, dotted host. Prose (which
    /// has spaces) and non-URLs return nil, so ordinary thoughts still become text fils.
    static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        let lower = trimmed.lowercased()
        let candidate = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host(),
              host.contains("."),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    /// The domain (sans "www.") used as the link's title until the real page title loads.
    static func titleFallback(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Build + insert a link fil, then fetch its real title + favicon in the background. Pass `uuid`
    /// to reuse a pre-allocated fil id (the share-extension blob morph); omit it for a fresh fil.
    @MainActor
    @discardableResult
    static func make(url: URL, gradient: (start: String, end: String), uuid: UUID? = nil, in context: ModelContext) -> Note {
        let fallback = titleFallback(for: url)
        let note = Note(
            title: fallback,
            transcript: url.absoluteString,
            keyword: "link",
            gradientStartHex: gradient.start,
            gradientEndHex: gradient.end,
            sourceURLString: url.absoluteString,
            sourceTitle: fallback
        )
        if let uuid { note.uuid = uuid }
        context.insert(note)

        FaviconLoader.loadMetadata(for: url) { title, icon in
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                note.title = title
                note.sourceTitle = title
            }
            if let data = icon?.pngData() {
                note.sourceFaviconData = data
            }
            context.saveOrLog()
        }
        return note
    }
}
