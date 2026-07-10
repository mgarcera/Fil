import Foundation
import FoundationModels
import NaturalLanguage
import OSLog

/// Groups fils into emergent, on-device semantic themes. See docs/features/theme-clustering.md.
///
/// v1: contextual embeddings (`NLContextualEmbedding`) → greedy cosine clustering → representative-
/// keyword names, with a deterministic keyword-grouping fallback if embeddings aren't available for
/// the corpus language. Runs off the main actor and works only on value data — `Note` objects never
/// cross the actor boundary (they stay on the main actor; the view maps the returned UUIDs back to fils).
///
/// Why contextual, not `NLEmbedding.sentenceEmbedding`: Apple no longer ships the static sentence-
/// embedding asset for English on current OSes (`sentenceEmbedding(for: .english)` returns nil,
/// logging "Unable to locate Asset for sentence embedding model"). `NLContextualEmbedding` downloads
/// its model over-the-air once via `requestAssets()`, then runs fully on-device/offline thereafter.
struct FilClusterInput: Sendable {
    let id: UUID
    let text: String     // transcript (or title/keyword) used for embedding
    let keyword: String  // the fil's display label, used to name its cluster
}

struct FilCluster: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let filIDs: [UUID]   // newest-first, mirroring the input order
}

/// Which engine produced a grouping — surfaced so a silent fallback can never masquerade as the
/// real (LLM) result during iteration.
enum FilClusteringEngine: String, Sendable {
    case model        // on-device LLM — the real kind-of-thought grouping
    case embeddings   // topical similarity fallback (LLM unavailable/failed)
    case keyword      // deterministic keyword fallback (no ML available)
}

struct FilClusteringResult: Sendable {
    let clusters: [FilCluster]
    let engine: FilClusteringEngine
}

/// Ranked fils for a domain query (blank-canvas surfacing, docs/features/blank-canvas-home.md).
struct FilRetrievalResult: Sendable {
    let filIDs: [UUID]   // best match first
    let engine: FilClusteringEngine
}

// MARK: - Emergent LLM grouping (guided generation)

@Generable(description: "A grouping of a person's short personal notes by the kind of thinking each note is")
struct FilGroupingResponse {
    @Guide(description: "The groups. Every note number belongs to exactly one group.", .count(3...8))
    var groups: [FilGroupResult]
}

@Generable
struct FilGroupResult {
    @Guide(description: "One or two natural lowercase words (e.g. \"reflections\", \"small joys\") naming the kind of thought or feeling these notes share. No underscores. Not a topic label.")
    var name: String
    @Guide(description: "The numbers of the notes that belong in this group")
    var noteNumbers: [Int]
}

actor FilClusteringService {
    static let shared = FilClusteringService()

    /// Cosine-similarity floor for two fils to share a theme, measured on *mean-centered* vectors
    /// (see `meanCentered`). Centering removes the shared component that made raw contextual cosines
    /// all crowd near 1.0, so the usable range drops well below a raw-embedding threshold. Tune
    /// against the cluster-size log: one giant grab-bag → raise it; all singletons → lower it.
    private let similarityThreshold = 0.5
    /// Named theme sections beyond this fold into "everything else".
    private let maxNamedClusters = 7
    /// Cap embedded text length — a representative slice is enough and keeps embedding fast.
    private let maxEmbedChars = 600

    /// In-memory embedding cache (per launch), keyed by fil id → (vector, textHash).
    private var cache: [UUID: (vector: [Double], hash: Int)] = [:]

    /// Contextual embedding model, loaded lazily once its assets are on-device. Cached across calls.
    private var contextual: NLContextualEmbedding?
    private var contextualLanguage: NLLanguage?

    /// Last computed grouping + the fil-id set it was computed from. Grouping is stable: we only re-run
    /// the (slow, non-deterministic) engine once the note set has changed by `recomputeThreshold` fils.
    /// Smaller changes reuse the cached grouping so themes don't reshuffle on every new fil.
    private var lastGrouping: [FilCluster] = []
    private var lastGroupingIDs: Set<UUID> = []
    private var lastEngine: FilClusteringEngine = .keyword
    private let recomputeThreshold = 4

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "clustering")

    /// Produces theme clusters for the given fils, newest-first inputs preserved within each cluster.
    func clusters(for inputs: [FilClusterInput]) async -> FilClusteringResult {
        guard !inputs.isEmpty else { return FilClusteringResult(clusters: [], engine: lastEngine) }

        // Reuse the cached grouping unless the note set has changed past the threshold — keeps themes
        // stable across new fils and avoids re-running the engine (and its non-determinism) constantly.
        let currentIDs = Set(inputs.map(\.id))
        if !lastGrouping.isEmpty {
            let changed = currentIDs.symmetricDifference(lastGroupingIDs).count
            if changed < recomputeThreshold {
                let reconciled = reconcile(lastGrouping, with: inputs)
                log.notice("clusters(\(inputs.count, privacy: .public) fils): reusing cached grouping (Δ\(changed, privacy: .public), \(self.lastEngine.rawValue, privacy: .public))")
                return FilClusteringResult(clusters: reconciled, engine: lastEngine)
            }
        }

        // Tiered: on-device LLM (groups by *kind of thought*, the real goal) → embeddings (topical
        // similarity) → deterministic keyword grouping. Each tier degrades gracefully to the next.
        let result: [FilCluster]
        let engine: FilClusteringEngine
        do {
            if let grouped = try await llmGrouping(inputs) {
                result = grouped
                engine = .model
            } else if let vectors = await embed(inputs) {
                result = semanticClusters(inputs, vectors: meanCentered(vectors))
                engine = .embeddings
            } else {
                result = keywordFallback(inputs)
                engine = .keyword
            }
        } catch {
            // Cancelled mid-run (e.g. the prototype was closed). Do NOT fall back to embeddings and do
            // NOT cache — a cancellation must never poison the cache with a worse grouping. Return the
            // prior grouping if we have one so nothing flashes; next open recomputes cleanly.
            log.notice("grouping cancelled — keeping prior grouping, not caching")
            let salvaged = lastGrouping.isEmpty ? keywordFallback(inputs) : reconcile(lastGrouping, with: inputs)
            return FilClusteringResult(clusters: salvaged, engine: lastGrouping.isEmpty ? .keyword : lastEngine)
        }

        // Only cache real model groupings. Fallbacks (embeddings/keyword) are provisional — leaving
        // the cache empty means the next open retries the LLM instead of serving cached junk, so a
        // single transient failure can't lock in the worse result.
        if engine == .model {
            lastGrouping = result
            lastGroupingIDs = currentIDs
            lastEngine = engine
        }
        log.notice("clusters(\(inputs.count, privacy: .public) fils, \(engine.rawValue, privacy: .public)): \(result.map { "\($0.name)×\($0.filIDs.count)" }.joined(separator: ", "), privacy: .public)")
        return FilClusteringResult(clusters: result, engine: engine)
    }

    /// Applies a cached grouping to the current fils without re-running the engine: drops fils that
    /// were landfilled, and folds any brand-new fils into "everything else" so nothing disappears.
    private func reconcile(_ cached: [FilCluster], with inputs: [FilClusterInput]) -> [FilCluster] {
        let present = Set(inputs.map(\.id))
        var seen = Set<UUID>()

        var result: [FilCluster] = cached.compactMap { cluster in
            let ids = cluster.filIDs.filter { present.contains($0) && seen.insert($0).inserted }
            return ids.isEmpty ? nil : FilCluster(name: cluster.name, filIDs: ids)
        }

        let newcomers = inputs.filter { !seen.contains($0.id) }.map(\.id)
        if !newcomers.isEmpty {
            if let index = result.firstIndex(where: { $0.name == "everything else" }) {
                let merged = result[index].filIDs + newcomers
                result[index] = FilCluster(name: "everything else", filIDs: merged)
            } else {
                result.append(FilCluster(name: "everything else", filIDs: newcomers))
            }
        }
        return result
    }

    // MARK: - Query retrieval (blank-canvas surfacing)

    /// Ranks fils by relevance to a free-text domain query ("work", "times i felt lost"). Embeds the
    /// query and each fil with the same contextual model, mean-centers to fight anisotropy, and sorts
    /// by cosine to the query. Falls back to keyword substring matching when embeddings are absent.
    /// Retrieval by topic is exactly what embeddings are good at — the right tool here, unlike the
    /// register clustering. No summary yet (that's v2); this validates retrieval quality first.
    func retrieve(query: String, from inputs: [FilClusterInput], limit: Int = 12) async -> FilRetrievalResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !inputs.isEmpty else { return FilRetrievalResult(filIDs: [], engine: .keyword) }

        let language = dominantLanguage(inputs)
        if let model = await loadContextual(language),
           let queryVector = pooledVector(model, text: q, language: language) {

            var ids: [UUID] = []
            var vecs: [[Double]] = []
            for input in inputs {
                let text = String(input.text.prefix(maxEmbedChars))
                let hash = text.hashValue
                let vector: [Double]
                if let cached = cache[input.id], cached.hash == hash {
                    vector = cached.vector
                } else if let v = pooledVector(model, text: text, language: language) {
                    cache[input.id] = (v, hash)
                    vector = v
                } else { continue }
                ids.append(input.id)
                vecs.append(vector)
            }

            if !ids.isEmpty {
                // Mean-center query + fils together, then rank fils by cosine to the query.
                let mean = centroid(of: vecs + [queryVector])
                let centeredQuery = subtracting(queryVector, mean)
                let ranked = zip(ids, vecs)
                    .map { (id: $0.0, score: cosine(subtracting($0.1, mean), centeredQuery)) }
                    .sorted { $0.score > $1.score }

                log.notice("retrieve(\"\(q, privacy: .public)\", \(ids.count, privacy: .public) fils) top: \(ranked.prefix(6).map { String(format: "%.2f", $0.score) }.joined(separator: ", "), privacy: .public)")

                let floor = 0.08   // drop clearly-unrelated fils; tune against the score log
                let kept = ranked.filter { $0.score > floor }.prefix(limit)
                if !kept.isEmpty {
                    return FilRetrievalResult(filIDs: kept.map(\.id), engine: .embeddings)
                }
            }
        }

        return keywordRetrieve(q, inputs, limit: limit)
    }

    private func keywordRetrieve(_ query: String, _ inputs: [FilClusterInput], limit: Int) -> FilRetrievalResult {
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !terms.isEmpty else { return FilRetrievalResult(filIDs: [], engine: .keyword) }

        let scored = inputs.compactMap { input -> (id: UUID, score: Int)? in
            let hay = (input.text + " " + input.keyword).lowercased()
            let score = terms.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
            return score > 0 ? (input.id, score) : nil
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)

        return FilRetrievalResult(filIDs: scored.map(\.id), engine: .keyword)
    }

    private func subtracting(_ a: [Double], _ b: [Double]) -> [Double] {
        guard a.count == b.count else { return a }
        return zip(a, b).map(-)
    }

    // MARK: - LLM grouping

    private static let groupingInstructions = """
        You organize a person's short personal notes by the KIND of thinking each one is —
        the mood, stance, or purpose behind it — not by its topic. Two notes about completely
        different topics can be the same kind of thought.

        Examples of the distinctions to draw:
        - "i'm in love and things are going well" + "great day for new music" → self check ins
        - "feeling stressed but i'll figure it out" + "where do i even fit" → uncertainty and searching
        - "remember how small i am" → inside thoughts
        - "look up alice walker's books" → things to explore
        - "respond to dave" + "plan the rooftop party" → things to do

        Notice how good feelings, anxious feelings, and philosophical reflections are SEPARATE kinds,
        not one "feelings" pile. Draw distinctions at least that fine.

        Rules:
        - Sort every note into exactly one group.
        - Aim for five to seven focused groups. No single group should hold more than about a quarter
          of the notes — if one would, split it into finer, more specific kinds.
        - Name each group with one or two natural words, lowercase (for example: "reflections",
          "small joys", "to do", "searching"). Keep it short. Never use underscores or run words
          together.
        - Never leave a note out.
        """

    /// Emergent grouping via the on-device model: it reads the notes and invents the groups + names.
    /// Returns nil (→ embedding fallback) when Apple Intelligence is unavailable or generation fails.
    /// Rethrows `CancellationError` so the caller can skip the fallback and avoid caching a partial run.
    private func llmGrouping(_ inputs: [FilClusterInput]) async throws -> [FilCluster]? {
        guard SystemLanguageModel.default.isAvailable else {
            log.notice("on-device model unavailable — embedding/keyword fallback")
            return nil
        }

        let numbered = inputs.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")

        // Retry once before giving up: failures here are usually transient (model cold/busy right
        // after launch), and the same corpus often succeeds on a second attempt.
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            let session = LanguageModelSession(instructions: Self.groupingInstructions)
            do {
                let response = try await session.respond(
                    to: Prompt { numbered },
                    generating: FilGroupingResponse.self
                )
                return mapGrouping(response.content, inputs: inputs)
            } catch {
                // Cancellation is not a failure to fall back from — propagate it so the run is discarded.
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                log.notice("LLM grouping attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) failed (\(error.localizedDescription, privacy: .public))")
            }
        }
        log.notice("LLM grouping failed — embedding fallback")
        return nil
    }

    /// Maps the model's note-number groups back to fils, defending against hallucinated, duplicate, or
    /// out-of-range numbers. Any note the model didn't place falls into "everything else".
    private func mapGrouping(_ response: FilGroupingResponse, inputs: [FilClusterInput]) -> [FilCluster] {
        var assigned = Set<Int>()
        var clusters: [FilCluster] = []

        for group in response.groups {
            var indices: [Int] = []
            for number in group.noteNumbers {
                let index = number - 1
                guard inputs.indices.contains(index), !assigned.contains(index) else { continue }
                assigned.insert(index)
                indices.append(index)
            }
            guard !indices.isEmpty else { continue }
            indices.sort()   // input order is newest-first, so keep it that way within the group
            clusters.append(FilCluster(name: cleanName(group.name), filIDs: indices.map { inputs[$0].id }))
        }

        let leftover = inputs.indices.filter { !assigned.contains($0) }
        if !leftover.isEmpty {
            clusters.append(FilCluster(name: "everything else", filIDs: leftover.map { inputs[$0].id }))
        }
        return clusters
    }

    /// Turns a model-emitted label into a human name: snake_case/dashes → spaces, collapse whitespace.
    private func cleanName(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return spaced.isEmpty ? "thoughts" : spaced
    }

    // MARK: - Embedding

    private func embed(_ inputs: [FilClusterInput]) async -> [UUID: [Double]]? {
        let language = dominantLanguage(inputs)
        guard let model = await loadContextual(language) else { return nil }

        var vectors: [UUID: [Double]] = [:]
        for input in inputs {
            let text = String(input.text.prefix(maxEmbedChars))
            let hash = text.hashValue
            if let cached = cache[input.id], cached.hash == hash {
                vectors[input.id] = cached.vector
                continue
            }
            guard let vector = pooledVector(model, text: text, language: language) else { continue }
            cache[input.id] = (vector, hash)
            vectors[input.id] = vector
        }
        return vectors.isEmpty ? nil : vectors
    }

    /// Lazily builds the contextual embedding model, downloading its assets over-the-air on first use.
    /// Returns nil (→ keyword fallback) if there's no model for the language or the download fails.
    private func loadContextual(_ language: NLLanguage) async -> NLContextualEmbedding? {
        if let contextual, contextualLanguage == language { return contextual }

        guard let model = NLContextualEmbedding(language: language) else {
            log.notice("no contextual embedding model for \(language.rawValue, privacy: .public) — keyword fallback")
            return nil
        }

        if !model.hasAvailableAssets {
            do {
                let result = try await model.requestAssets()
                guard result == .available else {
                    log.notice("contextual assets not available for \(language.rawValue, privacy: .public) — keyword fallback")
                    return nil
                }
            } catch {
                log.notice("contextual asset request failed (\(error.localizedDescription, privacy: .public)) — keyword fallback")
                return nil
            }
        }

        do {
            try model.load()
        } catch {
            log.notice("contextual model load failed (\(error.localizedDescription, privacy: .public)) — keyword fallback")
            return nil
        }

        contextual = model
        contextualLanguage = language
        log.notice("contextual embedding ready for \(language.rawValue, privacy: .public)")
        return model
    }

    /// Mean-pools a fil's subword token vectors into a single sentence-level vector.
    private func pooledVector(_ model: NLContextualEmbedding, text: String, language: NLLanguage) -> [Double]? {
        guard !text.isEmpty, let result = try? model.embeddingResult(for: text, language: language) else { return nil }

        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            if sum.isEmpty {
                sum = vector
            } else if sum.count == vector.count {
                for i in 0..<sum.count { sum[i] += vector[i] }
            }
            count += 1
            return true
        }
        guard count > 0, !sum.isEmpty else { return nil }
        return sum.map { $0 / Double(count) }
    }

    private func dominantLanguage(_ inputs: [FilClusterInput]) -> NLLanguage {
        let sample = inputs.prefix(25).map(\.text).joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Semantic clustering (agglomerative, average-linkage)

    private func semanticClusters(_ inputs: [FilClusterInput], vectors: [UUID: [Double]]) -> [FilCluster] {
        let items = inputs.filter { vectors[$0.id] != nil }
        guard !items.isEmpty else { return keywordFallback(inputs) }
        let vecs = items.map { vectors[$0.id]! }
        let n = items.count

        // Precompute the pairwise cosine matrix (n² is trivial at phone scale).
        var sim = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let s = cosine(vecs[i], vecs[j])
                sim[i][j] = s
                sim[j][i] = s
            }
        }

        // Agglomerative average-linkage: repeatedly merge the two most-similar clusters until nothing
        // exceeds the threshold. Order-independent (no greedy centroid drift), and average-linkage
        // resists both single-linkage chaining and complete-linkage over-fragmentation.
        var groups: [[Int]] = (0..<n).map { [$0] }
        func averageLinkage(_ a: [Int], _ b: [Int]) -> Double {
            var total = 0.0
            for i in a { for j in b { total += sim[i][j] } }
            return total / Double(a.count * b.count)
        }
        while groups.count > 1 {
            var bestA = -1, bestB = -1, best = -1.0
            for i in 0..<groups.count {
                for j in (i + 1)..<groups.count {
                    let s = averageLinkage(groups[i], groups[j])
                    if s > best { best = s; bestA = i; bestB = j }
                }
            }
            guard best >= similarityThreshold else { break }
            groups[bestA].append(contentsOf: groups[bestB])
            groups.remove(at: bestB)
        }

        struct Bucket { var centroid: [Double]; var members: [FilClusterInput] }
        let buckets: [Bucket] = groups.map { indices in
            Bucket(centroid: centroid(of: indices.map { vecs[$0] }), members: indices.map { items[$0] })
        }

        // Singletons pool into "everything else"; the rest are named clusters.
        let named = buckets.filter { $0.members.count > 1 }
        let loners = buckets.filter { $0.members.count == 1 }.flatMap(\.members)

        // Largest, most-recent themes first; cap and fold the tail into "everything else".
        let ordered = named.sorted { lhs, rhs in
            if lhs.members.count != rhs.members.count { return lhs.members.count > rhs.members.count }
            return firstIndex(of: lhs.members, in: inputs) < firstIndex(of: rhs.members, in: inputs)
        }
        let kept = ordered.prefix(maxNamedClusters)
        let folded = ordered.dropFirst(maxNamedClusters).flatMap(\.members) + loners

        var result: [FilCluster] = kept.map { bucket in
            FilCluster(
                name: name(for: bucket.members, vectors: vectors, centroid: bucket.centroid),
                filIDs: bucket.members.map(\.id)
            )
        }
        if !folded.isEmpty {
            let foldedSorted = folded.sorted { firstIndex(of: [$0], in: inputs) < firstIndex(of: [$1], in: inputs) }
            result.append(FilCluster(name: "everything else", filIDs: foldedSorted.map(\.id)))
        }
        return result
    }

    /// Names a cluster after the keyword of the fil nearest its centroid — a representative label.
    /// (v2 will replace this with a FoundationModels-generated theme name.)
    private func name(for members: [FilClusterInput], vectors: [UUID: [Double]], centroid: [Double]) -> String {
        let central = members.max { lhs, rhs in
            cosine(vectors[lhs.id] ?? [], centroid) < cosine(vectors[rhs.id] ?? [], centroid)
        }
        let label = central?.keyword.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "thoughts" : label.lowercased()
    }

    // MARK: - Deterministic fallback (no embeddings)

    private func keywordFallback(_ inputs: [FilClusterInput]) -> [FilCluster] {
        var groups: [String: [FilClusterInput]] = [:]
        var loners: [FilClusterInput] = []
        for input in inputs {
            let key = input.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty { loners.append(input) } else { groups[key, default: []].append(input) }
        }

        var result: [FilCluster] = groups
            .filter { $0.value.count > 1 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(maxNamedClusters)
            .map { FilCluster(name: $0.key, filIDs: $0.value.map(\.id)) }

        let named = Set(result.flatMap(\.filIDs))
        let rest = inputs.filter { !named.contains($0.id) }
        if !rest.isEmpty {
            result.append(FilCluster(name: "everything else", filIDs: rest.map(\.id)))
        }
        return result
    }

    // MARK: - Math

    /// Subtracts the corpus mean from each vector ("all-but-the-mean"). Contextual embeddings are
    /// highly anisotropic — every vector shares one dominant direction, so raw cosine similarities all
    /// bunch near 1.0 and unrelated fils cluster together. Removing the mean cancels that shared
    /// component and spreads the similarity distribution so the threshold can actually separate themes.
    /// Corpus-dependent, so it's applied fresh each run on a copy — the cache still holds raw vectors.
    private func meanCentered(_ vectors: [UUID: [Double]]) -> [UUID: [Double]] {
        guard let dim = vectors.values.first?.count, dim > 0, vectors.count > 1 else { return vectors }

        var mean = [Double](repeating: 0, count: dim)
        for vector in vectors.values where vector.count == dim {
            for i in 0..<dim { mean[i] += vector[i] }
        }
        let n = Double(vectors.count)
        for i in 0..<dim { mean[i] /= n }

        var centered: [UUID: [Double]] = [:]
        for (id, vector) in vectors where vector.count == dim {
            centered[id] = zip(vector, mean).map { $0 - $1 }
        }
        return centered
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = normA.squareRoot() * normB.squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }

    private func centroid(of vectors: [[Double]]) -> [Double] {
        guard let dim = vectors.first?.count, dim > 0 else { return [] }
        var sum = [Double](repeating: 0, count: dim)
        for vector in vectors where vector.count == dim {
            for i in 0..<dim { sum[i] += vector[i] }
        }
        let n = Double(vectors.count)
        return sum.map { $0 / n }
    }

    private func firstIndex(of members: [FilClusterInput], in inputs: [FilClusterInput]) -> Int {
        let ids = Set(members.map(\.id))
        return inputs.firstIndex { ids.contains($0.id) } ?? Int.max
    }
}
