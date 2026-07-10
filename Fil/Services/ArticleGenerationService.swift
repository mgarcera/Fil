import Foundation
import FoundationModels

@Generable(description: "Lightweight metadata extracted from a voice transcript")
struct NoteMetadataResponse {
    @Guide(description: "A short, natural title for the note — one complete sentence (an independent clause) in the person's own voice, about four to ten words, grounded in the transcript")
    var keyword: String
}

final class ArticleGenerationService {
    static let shared = ArticleGenerationService()

    /// Instructions shared by real generation and prewarming, so both warm the same model path.
    private static let instructions = """
        You are writing a short title for one person's note, from their transcript.
        Always assume the transcript is spoken by the same person who will read the result.
        Do not generate a polished article.
        Write one short, natural sentence — a complete independent clause, in the person's
        own voice — that captures what the note is about. Aim for about four to ten words.

        Ground it in the transcript and do not invent themes or details that are not present.
        Keep it natural and specific enough to recognize the note later.
        """

    /// A prewarmed session, held so its asset loading completes and stays resident.
    private var warmupSession: LanguageModelSession?

    /// Loads the on-device model assets ahead of first use so the first real title generation
    /// isn't stalled by a cold start. A no-op when the model is unavailable or already warmed.
    /// Call once early (e.g. at app launch, after the first frame).
    func prewarm() {
        guard warmupSession == nil, SystemLanguageModel.default.isAvailable else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        warmupSession = session
    }

    func generateMetadata(
        from transcript: String
    ) async throws -> NoteMetadataResponse {
        let session = LanguageModelSession(instructions: Self.instructions)

        let response = try await session.respond(
            to: metadataPrompt(for: transcript),
            generating: NoteMetadataResponse.self
        )

        let transcriptAnalysis = analyzeTranscript(transcript)
        var content = response.content
        content.keyword = shortLabel(
            from: sanitizedKeyword(
                content.keyword,
                transcript: transcript,
                transcriptAnalysis: transcriptAnalysis
            )
        )
        return content
    }

    /// Always returns a usable title without throwing. Gates on the on-device model's
    /// availability and degrades to the local text fallback when Apple Intelligence is
    /// unavailable (Simulator, unsupported device, model still downloading) or when
    /// generation fails — so note creation can never be blocked or lose data on the AI step.
    func generateTitle(from text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if SystemLanguageModel.default.isAvailable {
            do {
                return try await generateMetadata(from: text).keyword
            } catch {
                // Fall through to the on-device text fallback below.
            }
        }

        return shortLabel(from: keywordFallback(from: text))
    }

    /// Shapes a generated label into a short, natural title — the unified
    /// title/badge shown throughout the app. Caps the length, trims trailing
    /// connective words so it never ends on a preposition, and capitalizes the
    /// first letter so it reads like a headline.
    private func shortLabel(from text: String) -> String {
        // Titles now read as full independent clauses, so keep the natural leading and trailing
        // words (an opening "I", a closing "to figure out") instead of stripping them down to a
        // terse fragment. Just cap the length and capitalize the first letter.
        var words = Array(wordTokens(from: text).prefix(Self.maxLabelWords))
        guard let first = words.first else { return "" }
        words[0] = first.prefix(1).uppercased() + first.dropFirst()
        return words.joined(separator: " ")
    }

    private func metadataPrompt(for transcript: String) -> Prompt {
        Prompt {
            """
            Transcript:
            \(transcript)
            """
        }
    }

    private func sentenceSplit(from text: String) -> [String] {
        let nsText = text as NSString
        var sentences: [String] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: .bySentences
        ) { substring, _, _, _ in
            if let substring {
                let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
            }
        }
        return sentences
    }

    private func analyzeTranscript(_ transcript: String) -> TranscriptAnalysis {
        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let words = wordTokens(from: normalized)
        let contentWords = Set(words.filter { !Self.allowedNovelWords.contains($0) })
        let sentenceCount = sentenceSplit(from: normalized).count
        let requiresLiteralHandling = words.count <= 7 || sentenceCount <= 1 && normalized.count <= 60
        return TranscriptAnalysis(
            contentWords: contentWords,
            requiresLiteralHandling: requiresLiteralHandling
        )
    }

    private func sanitizedKeyword(
        _ keyword: String,
        transcript: String,
        transcriptAnalysis: TranscriptAnalysis
    ) -> String {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcriptAnalysis.requiresLiteralHandling else { return trimmedKeyword }
        guard !trimmedKeyword.isEmpty else { return keywordFallback(from: transcript) }

        let keywordWords = wordTokens(from: trimmedKeyword).map { $0.lowercased() }
        let hasUnsupportedWord = keywordWords.contains { word in
            !Self.allowedNovelWords.contains(word) && !transcriptAnalysis.contentWords.contains(word)
        }

        return hasUnsupportedWord ? keywordFallback(from: transcript) : trimmedKeyword
    }

    /// Builds a clause-style title straight from the transcript when the model's
    /// keyword is unusable. Preserves natural word order and connectives, only
    /// dropping leading filler so the title starts on a meaningful word. Final
    /// length capping and capitalization are handled by `shortLabel`.
    private func keywordFallback(from transcript: String) -> String {
        var words = wordTokens(from: transcript)

        while let first = words.first,
              words.count > 1,
              isLabelStopWord(first) {
            words.removeFirst()
        }

        return words.joined(separator: " ")
    }

    /// Splits text into word tokens while keeping contractions and possessives
    /// intact (e.g. "it's" stays one token instead of splitting into "it" + "s").
    private func wordTokens(from text: String) -> [String] {
        text
            .components(separatedBy: Self.wordSeparators)
            .map { $0.trimmingCharacters(in: Self.apostrophes) }
            .filter { !$0.isEmpty }
    }

    /// Maximum number of words in a generated title — now a full clause, not a terse badge.
    private static let maxLabelWords = 12

    /// Filler, connective, and function words dropped when shaping a label so the
    /// two words that survive are the most meaningful ones
    /// (e.g. "it's okay to play with others" -> "Play others").
    private static let labelStopWords: Set<String> = [
        "a", "an", "the", "to", "of", "for", "with", "and", "or", "but",
        "by", "in", "on", "at", "as", "is", "are", "was", "were", "be",
        "that", "this", "from", "i", "i'm", "i've", "it", "it's", "that's",
        "let's", "what's", "there's", "here's", "well", "um", "uh", "okay",
        "ok", "so", "just", "really", "actually", "basically", "like",
        "my", "our", "your", "we", "they", "you", "he", "she"
    ]

    /// Stopword check that normalizes curly apostrophes to straight, so contractions
    /// like "it's" match regardless of which apostrophe character the text uses.
    private func isLabelStopWord(_ word: String) -> Bool {
        Self.labelStopWords.contains(word.lowercased().replacingOccurrences(of: "’", with: "'"))
    }

    private static let apostrophes = CharacterSet(charactersIn: "'’")

    /// Everything that is neither alphanumeric nor an apostrophe delimits a word.
    private static let wordSeparators = CharacterSet.alphanumerics
        .union(apostrophes)
        .inverted

    private static let allowedNovelWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by", "for", "from",
        "had", "has", "have", "he", "her", "hers", "him", "his", "i", "in", "into", "is", "it",
        "its", "me", "my", "of", "on", "or", "our", "ours", "she", "so", "that", "the", "their",
        "theirs", "them", "there", "they", "this", "to", "up", "was", "we", "were", "with", "you",
        "your", "yours"
    ]
}

private struct TranscriptAnalysis {
    let contentWords: Set<String>
    let requiresLiteralHandling: Bool
}
