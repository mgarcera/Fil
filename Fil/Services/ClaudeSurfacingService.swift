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
}
