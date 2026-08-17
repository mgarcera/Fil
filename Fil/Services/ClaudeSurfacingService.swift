import Foundation
import OSLog

/// Surfacing client: posts a query + the user's fils to the Fil surfacing proxy (a Cloudflare Worker
/// that holds the Anthropic key server-side and asks Claude to pick the relevant fils + write a short
/// synthesis). The app never sees the key.
///
/// Phase 1 MVP: the proxy is gated only by a shared secret and isn't subscription-aware yet. The
/// endpoint URL + secret are configured on-device (dev), never committed. StoreKit verification and
/// per-user cost attribution land in later phases (see docs/monetization/blank-canvas-pivot-plan.md).
actor ClaudeSurfacingService {
    static let shared = ClaudeSurfacingService()

    struct Surfacing: Sendable {
        let summary: String
        let relevantIDs: [UUID]   // best-match order, as chosen by the model
        let suggestion: String    // when nothing matched: a nearby query the corpus can actually answer ("" if none)
    }

    /// One folder the model proposed when organizing the library (Pro "smart organize").
    struct OrganizedFolder: Sendable {
        let name: String
        let summary: String
        let filIDs: [UUID]
    }

    /// A folder that already exists, offered to the model as a filing destination. The caption
    /// rides along because a folder's name alone is often too thin to file against — "Move" and
    /// "Reading" mean much more with the sentence the folder already carries.
    struct FolderChoice: Sendable {
        let id: UUID
        let name: String
        let summary: String

        init(id: UUID, name: String, summary: String = "") {
            self.id = id
            self.name = name
            self.summary = summary
        }
    }

    /// Where one loose fil is proposed to go. `folderID` nil means "leave it in the Bin", which
    /// is a real answer here rather than a failure — see `fileIntoFolders`.
    struct FiledFil: Sendable {
        let filID: UUID
        let folderID: UUID?
    }

    enum SurfacingError: LocalizedError {
        case notSubscribed, http(Int, String), empty, badJSON

        var errorDescription: String? {
            switch self {
            case .notSubscribed:         return "Check out Fil Pro for a smarter search."
            case let .http(code, body):  return "Surfacing request failed (\(code)). \(body)"
            case .empty:                 return "The proxy returned an empty response."
            case .badJSON:               return "Couldn't read the proxy's response."
            }
        }
    }

    /// The surfacing proxy. A URL isn't secret, so it's compiled in; the proxy verifies the caller's
    /// Fil Pro subscription (via the transaction id) and holds the Anthropic key server-side.
    private let endpoint = URL(string: "https://fil-surfacing-proxy.mason-2fe.workers.dev")!
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "surfacing")

    /// - Parameter transactionID: the active Fil Pro subscription's transaction id, which the proxy
    ///   verifies with Apple before serving.
    func surface(query: String, fils: [FilClusterInput], transactionID: String) async throws -> Surfacing {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }

        let payload = RequestBody(
            query: query,
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) }
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SurfacingError.empty }
        guard http.statusCode == 200 else {
            let body = errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            log.notice("surfacing http \(http.statusCode, privacy: .public)")
            throw SurfacingError.http(http.statusCode, String(body.prefix(200)))
        }

        guard let decoded = try? JSONDecoder().decode(ProxyResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }

        let ids = decoded.relevant.compactMap { number -> UUID? in
            let index = number - 1
            return fils.indices.contains(index) ? fils[index].id : nil
        }
        log.notice("surface(\"\(query, privacy: .public)\"): \(ids.count, privacy: .public) fils")
        return Surfacing(summary: decoded.summary.withoutEmDashes, relevantIDs: ids, suggestion: decoded.suggestion ?? "")
    }

    /// Summarize-only pass: the app already chose the fils (a keyword match the model couldn't place
    /// semantically, e.g. an invented project name). Asks the proxy for just a warm reflection of them.
    /// - Parameter window: when the search was a time window (e.g. "this year"), its human label, so the
    ///   proxy can frame the reflection as a look back over that stretch. nil for non-temporal summaries.
    func summarize(query: String, fils: [FilClusterInput], transactionID: String, window: String? = nil) async throws -> String {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }

        let payload = RequestBody(
            query: query,
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) },
            summarize: true,
            window: window
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw SurfacingError.empty }
        guard let decoded = try? JSONDecoder().decode(ProxyResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }
        return decoded.summary.withoutEmDashes
    }

    /// Folder snippets: reflect one folder's contents as 2–4 short fragments (for the home hero stamps).
    func folderSnippets(fils: [FilClusterInput], transactionID: String) async throws -> [String] {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }

        let payload = RequestBody(
            query: "",
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) },
            snippets: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw SurfacingError.empty }
        guard let decoded = try? JSONDecoder().decode(SnippetsResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }
        return decoded.parts.map { $0.withoutEmDashes }
    }

    /// Describe one folder: caption its contents in a sentence or two (the interior folder caption).
    /// Purpose-built prompt on the proxy — grounded like organize's per-group description.
    func describeFolder(name: String, fils: [FilClusterInput], transactionID: String) async throws -> String {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }

        let payload = RequestBody(
            query: name,
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) },
            describe: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw SurfacingError.empty }
        guard let decoded = try? JSONDecoder().decode(ProxyResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }
        return decoded.summary.withoutEmDashes
    }

    /// Pro "smart organize": send the fils and get back topical folder groupings from Claude.
    func organize(fils: [FilClusterInput], transactionID: String) async throws -> [OrganizedFolder] {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }

        let payload = RequestBody(
            query: "",
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) },
            organize: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SurfacingError.empty }
        guard http.statusCode == 200 else {
            let body = errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            log.notice("organize http \(http.statusCode, privacy: .public)")
            throw SurfacingError.http(http.statusCode, String(body.prefix(200)))
        }

        guard let decoded = try? JSONDecoder().decode(OrganizeResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }

        var dropped = 0
        let folders = decoded.groups.map { group -> OrganizedFolder in
            var ids: [UUID] = []
            for number in group.fils {
                let index = number - 1
                if fils.indices.contains(index) {
                    ids.append(fils[index].id)
                } else {
                    dropped += 1
                }
            }
            return OrganizedFolder(name: group.name, summary: group.description ?? "", filIDs: ids)
        }
        if dropped > 0 {
            log.notice("organize: dropped \(dropped, privacy: .public) out-of-range note number(s)")
        }
        return folders
    }

    /// Pro "file the Bin": propose which of the folders you already have each loose fil belongs
    /// in. Returns one entry per fil, in the order sent — `folder` is nil for "leave it loose",
    /// which the proxy also substitutes for any folder name the model invented.
    ///
    /// Callers must handle an all-nil result: the model is told that nil beats a wrong guess, so
    /// "nothing fit" is a real outcome and not an error.
    func fileIntoFolders(
        folders: [FolderChoice],
        fils: [FilClusterInput],
        transactionID: String
    ) async throws -> [FiledFil] {
        guard !transactionID.isEmpty else { throw SurfacingError.notSubscribed }
        // The proxy rejects an empty folder list; the caller is expected to run organize instead.
        guard !folders.isEmpty else { throw SurfacingError.empty }

        let payload = RequestBody(
            query: "",
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) },
            file: true,
            folders: folders.map { RequestFolder(name: $0.name, description: $0.summary) }
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(transactionID, forHTTPHeaderField: "X-Fil-Transaction-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SurfacingError.empty }
        guard http.statusCode == 200 else {
            let body = errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            log.notice("file http \(http.statusCode, privacy: .public)")
            throw SurfacingError.http(http.statusCode, String(body.prefix(200)))
        }

        guard let decoded = try? JSONDecoder().decode(FileResponse.self, from: data) else {
            throw SurfacingError.badJSON
        }

        // Map back to real identities. A name the proxy let through still has to match a folder
        // we hold, so a rename racing the request drops that one fil to loose rather than
        // filing it somewhere arbitrary.
        let byName = Dictionary(folders.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        var placed = 0
        let result: [FiledFil] = decoded.assignments.compactMap { assignment in
            let index = assignment.fil - 1
            guard fils.indices.contains(index) else { return nil }
            let folderID = assignment.folder.flatMap { byName[$0] }
            if folderID != nil { placed += 1 }
            return FiledFil(filID: fils[index].id, folderID: folderID)
        }
        log.notice("file: \(placed, privacy: .public)/\(result.count, privacy: .public) placed")
        return result
    }

    /// Pull the proxy's `{ "error": "..." }` message out of a non-200 body, if present.
    private func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        let query: String
        let fils: [RequestFil]
        var summarize: Bool? = nil
        var window: String? = nil
        var organize: Bool? = nil
        var snippets: Bool? = nil
        var describe: Bool? = nil
        var file: Bool? = nil
        var folders: [RequestFolder]? = nil
    }
    private struct RequestFolder: Encodable {
        let name: String
        let description: String
    }
    private struct FileResponse: Decodable {
        struct Assignment: Decodable {
            let fil: Int
            let folder: String?
        }
        let assignments: [Assignment]
    }
    private struct SnippetsResponse: Decodable {
        let parts: [String]
    }
    private struct RequestFil: Encodable {
        let text: String
        let metadata: String
    }
    private struct ProxyResponse: Decodable {
        let summary: String
        let relevant: [Int]
        let suggestion: String?
    }

    private struct OrganizeResponse: Decodable {
        let groups: [OrganizeGroup]
    }
    private struct OrganizeGroup: Decodable {
        let name: String
        let description: String?
        let fils: [Int]
    }
}

/// Fil's voice never uses em dashes (see the fil-voice guidance). Swap any the model returns for a
/// comma, and tidy the spacing. (Previously lived alongside the removed on-device title service.)
private extension String {
    nonisolated var withoutEmDashes: String {
        replacingOccurrences(of: " — ", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
