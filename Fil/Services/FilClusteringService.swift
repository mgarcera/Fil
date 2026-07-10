import Foundation
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

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.masongarcera.Fil", category: "clustering")

    /// Produces theme clusters for the given fils, newest-first inputs preserved within each cluster.
    func clusters(for inputs: [FilClusterInput]) async -> [FilCluster] {
        guard !inputs.isEmpty else { return [] }

        let result: [FilCluster]
        if let vectors = await embed(inputs) {
            result = semanticClusters(inputs, vectors: meanCentered(vectors))
        } else {
            result = keywordFallback(inputs)   // no embeddings for this language → deterministic grouping
        }

        log.notice("clusters(\(inputs.count, privacy: .public) fils): \(result.map { "\($0.name)×\($0.filIDs.count)" }.joined(separator: ", "), privacy: .public)")
        return result
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
