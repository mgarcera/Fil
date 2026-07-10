import Foundation
import NaturalLanguage

/// Groups fils into emergent, on-device semantic themes. See docs/features/theme-clustering.md.
///
/// v1: sentence embeddings (`NLEmbedding`) → greedy cosine clustering → representative-keyword names,
/// with a deterministic keyword-grouping fallback if embeddings aren't available for the corpus
/// language. Runs off the main actor and works only on value data — `Note` objects never cross the
/// actor boundary (they stay on the main actor; the view maps the returned UUIDs back to fils).
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

    /// Cosine-similarity floor for two fils to share a theme. Tune empirically against real clusters.
    private let similarityThreshold = 0.75
    /// Named theme sections beyond this fold into "everything else".
    private let maxNamedClusters = 7
    /// Cap embedded text length — sentence embeddings don't need the whole transcript.
    private let maxEmbedChars = 600

    /// In-memory embedding cache (per launch), keyed by fil id → (vector, textHash).
    private var cache: [UUID: (vector: [Double], hash: Int)] = [:]

    /// Produces theme clusters for the given fils, newest-first inputs preserved within each cluster.
    func clusters(for inputs: [FilClusterInput]) -> [FilCluster] {
        guard !inputs.isEmpty else { return [] }

        guard let vectors = embed(inputs) else {
            return keywordFallback(inputs)   // no embeddings for this language → deterministic grouping
        }

        return semanticClusters(inputs, vectors: vectors)
    }

    // MARK: - Embedding

    private func embed(_ inputs: [FilClusterInput]) -> [UUID: [Double]]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: dominantLanguage(inputs)) else {
            return nil
        }

        var vectors: [UUID: [Double]] = [:]
        for input in inputs {
            let text = String(input.text.prefix(maxEmbedChars))
            let hash = text.hashValue
            if let cached = cache[input.id], cached.hash == hash {
                vectors[input.id] = cached.vector
                continue
            }
            guard let vector = embedding.vector(for: text) else { continue }
            cache[input.id] = (vector, hash)
            vectors[input.id] = vector
        }
        return vectors.isEmpty ? nil : vectors
    }

    private func dominantLanguage(_ inputs: [FilClusterInput]) -> NLLanguage {
        let sample = inputs.prefix(25).map(\.text).joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Semantic clustering (greedy, threshold-based)

    private func semanticClusters(_ inputs: [FilClusterInput], vectors: [UUID: [Double]]) -> [FilCluster] {
        struct Bucket { var centroid: [Double]; var members: [FilClusterInput] }
        var buckets: [Bucket] = []

        for input in inputs {
            guard let vector = vectors[input.id] else { continue }
            var bestIndex = -1
            var bestSimilarity = -1.0
            for (index, bucket) in buckets.enumerated() {
                let similarity = cosine(vector, bucket.centroid)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestIndex = index
                }
            }
            if bestIndex >= 0, bestSimilarity >= similarityThreshold {
                let count = Double(buckets[bestIndex].members.count)
                buckets[bestIndex].centroid = runningMean(buckets[bestIndex].centroid, count: count, adding: vector)
                buckets[bestIndex].members.append(input)
            } else {
                buckets.append(Bucket(centroid: vector, members: [input]))
            }
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

    private func runningMean(_ centroid: [Double], count: Double, adding vector: [Double]) -> [Double] {
        guard centroid.count == vector.count else { return centroid }
        return zip(centroid, vector).map { ($0 * count + $1) / (count + 1) }
    }

    private func firstIndex(of members: [FilClusterInput], in inputs: [FilClusterInput]) -> Int {
        let ids = Set(members.map(\.id))
        return inputs.firstIndex { ids.contains($0.id) } ?? Int.max
    }
}
