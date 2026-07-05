import Foundation
import FoundationModels

@Generable(description: "Lightweight metadata extracted from a voice transcript")
struct NoteMetadataResponse {
    @Guide(description: "A short, natural title for the note — a brief phrase or clause that reads like a headline, up to six words, grounded in the transcript")
    var keyword: String
}

final class ArticleGenerationService {
    static let shared = ArticleGenerationService()

    func generateMetadata(
        from transcript: String
    ) async throws -> NoteMetadataResponse {
        let session = LanguageModelSession(instructions: """
            You are extracting a lightweight title from one person's transcript.
            Always assume the transcript is spoken by the same person who will read the result.
            Do not generate a polished article.
            Return only one short, natural title that captures the main topic — a brief
            phrase or clause that reads like a headline, up to six words.

            The title should read naturally, be specific enough to recognize the note later,
            and stay short — up to six words, grounded in the transcript.
            Do not invent themes or details that are not present.
            """)

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
        var words = wordTokens(from: text)

        // Drop leading filler first — before the word cap — so the label starts on a
        // meaningful word ("it's okay to call" -> "call") and the cap keeps real words
        // rather than the connectives. Mirrors the trailing trim below.
        while let first = words.first,
              words.count > 1,
              isLabelStopWord(first) {
            words.removeFirst()
        }

        words = Array(words.prefix(Self.maxLabelWords))

        while let last = words.last,
              words.count > 1,
              isLabelStopWord(last) {
            words.removeLast()
        }

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

    /// Maximum number of words in a generated title/badge.
    private static let maxLabelWords = 6

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
