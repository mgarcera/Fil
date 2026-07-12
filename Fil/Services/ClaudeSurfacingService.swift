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
    }

    enum SurfacingError: LocalizedError {
        case missingConfig, http(Int, String), empty, badJSON

        var errorDescription: String? {
            switch self {
            case .missingConfig:         return "Set the surfacing proxy URL to try surfacing."
            case let .http(code, body):  return "Surfacing request failed (\(code)). \(body)"
            case .empty:                 return "The proxy returned an empty response."
            case .badJSON:               return "Couldn't read the proxy's response."
            }
        }
    }

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "surfacing")

    /// - Parameters:
    ///   - endpoint: the proxy URL (e.g. https://fil-surfacing-proxy.<acct>.workers.dev).
    ///   - secret: the shared secret matched against the proxy's PROXY_SHARED_SECRET.
    func surface(query: String, fils: [FilClusterInput], endpoint: String, secret: String) async throws -> Surfacing {
        let urlString = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { throw SurfacingError.missingConfig }

        let payload = RequestBody(
            query: query,
            fils: fils.map { RequestFil(text: $0.text, metadata: $0.metadata) }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(secret, forHTTPHeaderField: "X-Fil-Proxy-Key")
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
        return Surfacing(summary: decoded.summary.withoutEmDashes, relevantIDs: ids)
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
    }
    private struct RequestFil: Encodable {
        let text: String
        let metadata: String
    }
    private struct ProxyResponse: Decodable {
        let summary: String
        let relevant: [Int]
    }
}
