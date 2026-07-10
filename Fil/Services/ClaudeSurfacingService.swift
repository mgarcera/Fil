import Foundation
import OSLog

/// TEMPORARY dev-key spike (blank-canvas surfacing, docs/features/blank-canvas-home.md).
///
/// Calls the Anthropic API DIRECTLY from the app with a locally-stored key, purely to validate
/// Claude-powered surfacing before we build the real thing. This must NEVER ship: a production build
/// has to proxy through a server that holds the key and checks the user's subscription — an embedded
/// key would be extracted and abused. The key here lives only in on-device storage, never in the repo.
///
/// One pass: given a query + the user's fils, Claude picks the genuinely relevant ones and writes a
/// short synthesis — replacing the weak on-device embedding retrieval.
actor ClaudeSurfacingService {
    static let shared = ClaudeSurfacingService()

    struct Surfacing: Sendable {
        let summary: String
        let relevantIDs: [UUID]   // best-match order, as chosen by the model
    }

    enum SurfacingError: LocalizedError {
        case missingKey, http(Int, String), empty, badJSON

        var errorDescription: String? {
            switch self {
            case .missingKey:            return "Add a Claude dev key to try surfacing."
            case let .http(code, body):  return "Claude request failed (\(code)). \(body)"
            case .empty:                 return "Claude returned an empty response."
            case .badJSON:               return "Couldn't read Claude's response."
            }
        }
    }

    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "claude-spike")

    func surface(query: String, fils: [FilClusterInput], apiKey: String) async throws -> Surfacing {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SurfacingError.missingKey }

        let numbered = fils.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")

        let system = """
            You help someone explore their own private notes (they call each one a "fil"). Given a \
            query — a domain, mood, or question — and a numbered list of their notes, do two things:
            1. Pick the notes GENUINELY relevant to the query (by kind of thought, topic, or feeling), \
            best first. Be selective; omit notes that don't truly relate. If none relate, return an \
            empty list.
            2. Write a short, warm synthesis (2-4 sentences, second person, lowercase, in their voice) \
            of what they've been thinking about this — grounded ONLY in the notes, no invention.

            Respond with ONLY a JSON object, no prose or code fences:
            {"summary": "...", "relevant": [numbers]}
            """
        let userMessage = "Query: \(query)\n\nNotes:\n\(numbered)"

        let requestBody = RequestBody(
            model: model,
            max_tokens: 800,
            system: system,
            messages: [.init(role: "user", content: userMessage)]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SurfacingError.empty }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.notice("claude http \(http.statusCode, privacy: .public)")
            throw SurfacingError.http(http.statusCode, String(body.prefix(200)))
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw SurfacingError.empty
        }

        let parsed = try parse(text)
        let ids = parsed.relevant.compactMap { number -> UUID? in
            let index = number - 1
            return fils.indices.contains(index) ? fils[index].id : nil
        }
        log.notice("claude surface(\"\(query, privacy: .public)\"): \(ids.count, privacy: .public) fils")
        return Surfacing(summary: parsed.summary, relevantIDs: ids)
    }

    /// Extracts the {"summary","relevant"} object from the model's text, tolerating stray wrapping.
    private func parse(_ text: String) throws -> Parsed {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw SurfacingError.badJSON
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8), let parsed = try? JSONDecoder().decode(Parsed.self, from: data) else {
            throw SurfacingError.badJSON
        }
        return parsed
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }
    private struct Message: Encodable {
        let role: String
        let content: String
    }
    private struct APIResponse: Decodable {
        let content: [ContentBlock]
    }
    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    private struct Parsed: Decodable {
        let summary: String
        let relevant: [Int]
    }
}
