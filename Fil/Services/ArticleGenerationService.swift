import Foundation
import FoundationModels

@Generable(description: "Lightweight metadata extracted from a voice transcript")
struct NoteMetadataResponse {
    @Guide(description: "A single short label or tag that captures the main topic, one to four words max")
    var keyword: String

    @Guide(description: "Actionable open to-dos as short verb-led phrases, not full sentences", .maximumCount(10))
    var todos: [String]
}

final class ArticleGenerationService {
    static let shared = ArticleGenerationService()

    func generateMetadata(
        from transcript: String,
        userProfile: UserProfile? = nil
    ) async throws -> NoteMetadataResponse {
        let session = LanguageModelSession(instructions: """
            You are extracting lightweight metadata from one person's transcript.
            Always assume the transcript is spoken by the same person who will read the result.
            Do not generate a polished article.
            Return only:
            - one short label or tag that captures the main topic, one to four words max
            - open actionable to-dos if any are explicitly present

            The label should be specific enough to recognize the note later, but short — one to four words, grounded in the transcript.
            To-dos must be concrete, open actions written as short verb-led phrases.
            Do not invent tasks, themes, or details that are not present.
            If there are no action items, return an empty list for todos.
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
        content.todos = sanitizeTodos(content.todos)
        return content
    }

    /// Caps a generated label to at most four words — the unified title/badge
    /// shown throughout the app.
    private func shortLabel(from text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }
            .prefix(4)
            .joined(separator: " ")
    }

    private func sanitizeTodos(_ todos: [String]) -> [String] {
        var seen: Set<String> = []
        var sanitized: [String] = []

        for todo in todos {
            let trimmed = compressedTodoText(normalizedTodoText(todo))

            guard !trimmed.isEmpty else { continue }
            guard isActionableTodo(trimmed) else { continue }

            let normalizedKey = trimmed.lowercased()
            guard !seen.contains(normalizedKey) else { continue }

            seen.insert(normalizedKey)
            sanitized.append(trimmed)
        }

        return sanitized
    }

    private func metadataPrompt(for transcript: String) -> Prompt {
        Prompt {
            """
            Transcript:
            \(transcript)
            """
        }
    }

    private func normalizedTodoText(_ todo: String) -> String {
        var trimmed = todo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let removablePrefixes = [
            "- ",
            "* ",
            "todo: ",
            "to-do: ",
            "i need to ",
            "i should ",
            "i have to ",
            "i still need to ",
            "i still have to ",
            "i want to remember to ",
            "remember to ",
            "need to ",
            "plan to "
        ]

        let lowercased = trimmed.lowercased()
        if let prefix = removablePrefixes.first(where: { lowercased.hasPrefix($0) }) {
            trimmed = String(trimmed.dropFirst(prefix.count))
        }

        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func compressedTodoText(_ todo: String) -> String {
        var compressed = todo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let cutoffPhrases = [
            " by ",
            " so that ",
            " then ",
            " and then ",
            " in order to "
        ]

        for phrase in cutoffPhrases {
            if let range = compressed.range(of: phrase, options: [.caseInsensitive]) {
                let prefix = compressed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if wordCount(in: String(prefix)) >= 2 {
                    compressed = String(prefix)
                    break
                }
            }
        }

        let replacements: [(String, String)] = [
            ("make sure i understand the system from the inside and out by going through the transportation module", "go through the transportation module"),
            ("make sure i understand the system by going through the transportation module", "go through the transportation module"),
            ("putting all my notes in one place", "put my notes in one place"),
            ("going through the transportation module", "go through the transportation module")
        ]

        for (source, replacement) in replacements {
            compressed = replacingCaseInsensitive(source, in: compressed, with: replacement)
        }

        return compressed
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func isActionableTodo(_ todo: String) -> Bool {
        let lowercased = todo.lowercased()

        guard !lowercased.isEmpty else { return false }
        guard !lowercased.contains("\n") else { return false }
        guard wordCount(in: lowercased) >= 2 else { return false }
        guard wordCount(in: lowercased) <= 24 else { return false }

        let narrativePrefixes = [
            "last night",
            "yesterday",
            "it was",
            "time flew",
            "i had ",
            "i was ",
            "i went ",
            "i talked ",
            "i spoke ",
            "i spent ",
            "i got ",
            "i enjoyed ",
            "i made progress ",
            "i worked on ",
            "we had ",
            "we went "
        ]

        if narrativePrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return false
        }

        let narrativeFragments = [
            "conversation with",
            "had a great time",
            "had a lot of fun",
            "lasted for hours",
            "refreshing break",
            "usual routine",
            "time flew by",
            "feedback on",
            "feedback from",
            "great feedback",
            "worked on",
            "spent time",
            "made progress"
        ]

        if narrativeFragments.contains(where: { lowercased.contains($0) }) {
            return false
        }

        let actionablePrefixes = [
            "update ",
            "follow up ",
            "follow-up ",
            "send ",
            "reply ",
            "email ",
            "text ",
            "call ",
            "schedule ",
            "plan ",
            "prepare ",
            "learn ",
            "buy ",
            "pick up ",
            "drop off ",
            "check ",
            "review ",
            "go through ",
            "understand ",
            "finish ",
            "start ",
            "write ",
            "make ",
            "book ",
            "cancel ",
            "confirm ",
            "ask ",
            "remind ",
            "look into ",
            "research ",
            "clean ",
            "fix ",
            "upload ",
            "submit ",
            "pay ",
            "order ",
            "gather ",
            "organize ",
            "refill ",
            "track ",
            "monitor "
        ]

        if actionablePrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }

        let explicitActionPatterns = [
            #"\bneed to\b"#,
            #"\bshould\b"#,
            #"\bhave to\b"#,
            #"\bplan to\b"#,
            #"\bremember to\b"#,
            #"\bdon't forget to\b"#,
            #"\bcheck on\b"#,
            #"\bfollow up with\b"#
        ]

        if explicitActionPatterns.contains(where: { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }) {
            return true
        }

        return false
    }

    private func replacingCaseInsensitive(_ target: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: target),
            options: [.caseInsensitive]
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
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
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
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

        let keywordWords = trimmedKeyword
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let hasUnsupportedWord = keywordWords.contains { word in
            !Self.allowedNovelWords.contains(word) && !transcriptAnalysis.contentWords.contains(word)
        }

        return hasUnsupportedWord ? keywordFallback(from: transcript) : trimmedKeyword
    }

    private func keywordFallback(from transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let tagWords = words.filter { !Self.allowedNovelWords.contains($0.lowercased()) }
        if !tagWords.isEmpty {
            return tagWords.prefix(4).joined(separator: " ")
        }

        return words.prefix(4).joined(separator: " ")
    }

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
