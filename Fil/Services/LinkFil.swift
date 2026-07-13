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

        // Separately fetch the page's description (LinkPresentation doesn't expose it).
        Task { @MainActor in
            if let description = await fetchDescription(for: url) {
                note.sourceDescription = description
                context.saveOrLog()
            }
        }
        return note
    }

    /// Fetch the page HTML and pull its description from the OpenGraph / standard meta tags. Returns
    /// nil for JS-only pages, bot-blocked sites, or pages without a description — all handled by just
    /// not showing one. Dependency-free: a small `URLSession` fetch + regex over the `<meta>` tags.
    static func fetchDescription(for url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        // A browsery UA coaxes OG tags out of servers that gate obvious bots.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        // The meta tags live in <head>; cap the scan so huge pages stay cheap.
        let html = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)) ?? ""
        let head = String(html.prefix(60_000))

        for key in ["og:description", "twitter:description", "description"] {
            if let content = metaContent(head, key: key) {
                let cleaned = decodeEntities(content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned.count > 800 ? String(cleaned.prefix(800)) + "…" : cleaned
                }
            }
        }
        return nil
    }

    /// The `content` of a `<meta>` tag whose `property`/`name` equals `key`, in either attribute order.
    private static func metaContent(_ html: String, key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "<meta[^>]*(?:property|name)=[\"']\(k)[\"'][^>]*content=[\"']([^\"']*)[\"']",
            "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*(?:property|name)=[\"']\(k)[\"']",
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = re.firstMatch(in: html, range: range), let r = Range(match.range(at: 1), in: html) {
                return String(html[r])
            }
        }
        return nil
    }

    /// Decode the handful of HTML entities common in meta descriptions (no full parser needed).
    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                   "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…"]
        for (entity, char) in map { out = out.replacingOccurrences(of: entity, with: char) }
        return out
    }
}
