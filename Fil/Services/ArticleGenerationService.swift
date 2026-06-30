import Foundation
import FoundationModels

@Generable(description: "A polished article generated from a voice transcript")
struct ArticleResponse {
    @Guide(description: "A short, descriptive title for the article")
    var title: String

    @Guide(description: "The polished written article based on the transcript")
    var article: String

    @Guide(description: "A single short keyword or tag that captures the main topic, two to four words max")
    var keyword: String

    @Guide(description: "Actionable open to-dos as short verb-led phrases, not full sentences", .maximumCount(10))
    var todos: [String]
}

@Generable(description: "Lightweight metadata extracted from a voice transcript")
struct NoteMetadataResponse {
    @Guide(description: "A short, descriptive title for the note")
    var title: String

    @Guide(description: "A single short keyword or tag that captures the main topic, two to four words max")
    var keyword: String

    @Guide(description: "Actionable open to-dos as short verb-led phrases, not full sentences", .maximumCount(10))
    var todos: [String]
}

@Generable(description: "An appended paragraph that extends an existing article")
private struct AppendedFilingResponse {
    @Guide(description: "A short paragraph that adds new detail to the existing article without rewriting it")
    var paragraph: String
}

@Generable(description: "A refreshed list of to-dos extracted from an article and transcript")
private struct TodoRefreshResponse {
    @Guide(description: "Actionable open to-dos as short verb-led phrases, not full sentences", .maximumCount(10))
    var todos: [String]
}

enum CalibrationVariantMode: String, Identifiable {
    case balanced
    case tighter
    case fuller
    case cleaner
    case warmer

    var id: String { rawValue }
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
            - a short descriptive title
            - one concise keyword or tag, two to four words max
            - open actionable to-dos if any are explicitly present

            The title should be compact, clear, and grounded in the transcript.
            The keyword should be specific enough to recognize the note later, but short.
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
        content.title = WritingStyleFormatter.applyTitleStyle(to: content.title)
        content.keyword = sanitizedKeyword(
            content.keyword,
            transcript: transcript,
            transcriptAnalysis: transcriptAnalysis
        )
        content.todos = sanitizeTodos(content.todos)
        return content
    }

    func refreshTodos(
        from transcript: String,
        currentArticle: String,
        userProfile: UserProfile? = nil
    ) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
            You are extracting still-relevant action items from one person's transcript and edited article. \
            Only return concrete tasks, reminders, errands, next steps, or follow-up actions that are explicitly \
            present in the provided article or transcript. Prefer the current article as the authoritative edited \
            version when deciding what tasks are active. Do not invent tasks. \
            Return only open actions that a person could realistically check off. \
            Do not return completed events, reflections, memories, descriptions, observations, or summaries. \
            A memorable moment is not a to-do unless the text explicitly contains a follow-up, reminder, plan, \
            unresolved preparation step, or other unfinished action. \
            Do not return themes, narrative sentences, or vague intentions that cannot stand alone as a useful to-do. \
            Write each to-do as a concise action phrase, usually starting with a verb. \
            If the source contains a longer prep-oriented or learning-oriented task, you may compress it into a cleaner action phrase \
            while preserving the core action. \
            Examples: "follow up with nithin", "update the q1 report", "prepare my presentation for the dfss senior director", \
            "prepare for the reloshare training", "put my notes in one place for the reloshare training", "go through the transportation module". \
            Do not write full sentences. Do not include punctuation unless needed inside a proper noun. \
            Good outputs: ["update the q1 report", "follow up with nithin", "prepare my presentation for the dfss senior director", "prepare for the reloshare training", "go through the transportation module"] \
            Bad outputs: ["i had a great conversation with ben", "got great feedback from nithin", "spent time on the report", "the q1 report"] \
            If there are no action items, return an empty list.
            """)

        let response = try await session.respond(
            to: Prompt {
                """
                Transcript:
                \(transcript)

                Current edited article:
                \(currentArticle)
                """
            },
            generating: TodoRefreshResponse.self
        )

        return sanitizeTodos(response.content.todos)
    }

    func generateAppendedFiling(
        from prompt: String,
        transcript: String,
        currentArticle: String,
        userProfile: UserProfile? = nil
    ) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You are extending an existing first-person article with one new paragraph. \
            Do not rewrite or summarize the existing article. Add only the new material implied by \
            the user's latest fil'ng note. Keep the paragraph in first person and grounded in the \
            provided transcript, current article, and add-fil'ng prompt. \
            The new paragraph should feel like a natural continuation of the existing article rather \
            than a restart. Do not invent unrelated people, events, or settings. \
            Keep it concise, usually 2 to 4 sentences. Return only the new paragraph.
            """)

        let response = try await session.respond(
            to: Prompt {
                defaultVoicePrompt

                """
                Transcript:
                \(transcript)

                Current article:
                \(currentArticle)

                Add fil'ng:
                \(prompt)
                """
            },
            generating: AppendedFilingResponse.self
        )

        return WritingStyleFormatter.applyVisibleStyle(
            to: response.content.paragraph.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            userProfile: userProfile
        )
    }

    func generateArticle(
        from transcript: String,
        userProfile: UserProfile? = nil,
        calibrationNotes: [String] = [],
        currentArticle: String? = nil,
        variantMode: CalibrationVariantMode = .balanced
    ) async throws -> ArticleResponse {
        let session = LanguageModelSession(instructions: """
            You are a writing assistant working from a single speaker's voice transcript. \
            Always assume the transcript is spoken by the same person who will read the result. \
            Write in first person using "I" statements and preserve that perspective throughout. \
            Never rewrite the speaker as "you", "they", "them", "the user", or by name unless \
            the transcript explicitly quotes someone else. Produce a polished written article. \
            This is not a dictation-cleanup task. Turn rough spoken notes into fuller written \
            thoughts with clear connective tissue and slightly more complete reasoning than the \
            raw transcript provides. Preserve the speaker's meaning and stay grounded in what \
            was actually said. You may smooth out phrasing, connect fragmented thoughts, and \
            clarify what the speaker likely meant, but never invent events, details, people, \
            or storylines that are not present or clearly implied in the transcript. \
            If the transcript is very short (a few words or a single sentence), the article must also \
            be very short. Do not expand a brief transcript into multiple paragraphs or a full story. \
            A one-sentence transcript should produce at most a one-to-two-sentence article. \
            If the transcript is too vague or incoherent to form a full article, keep the output \
            short and honest. A brief, accurate piece is always better than a longer fabricated one. \
            Keep the writing compact. Prefer tight, efficient paragraphs over long expansion, and \
            include only the context needed to complete the thought well. \
            Format the article into short logical paragraphs, usually 2 to 4 paragraphs total, \
            with a blank line between paragraphs. Avoid returning one large wall of text. \
            The article body must contain only the article itself. Do not append metadata like \
            "Keyword:", "Keywords:", "Tags:", topic lists, or summaries at the end of the article. \
            Use Fil's default voice: relaxed, understated, message-native, and informal without forced slang or internet parody. \
            Keep the writing direct and grounded. Do not use the word "lowkey" in the output. \
            Also extract any action items or to-dos mentioned. This includes explicit plans, \
            reminders, errands, next steps, and time-sensitive intentions introduced either in \
            the original transcript or in calibration notes. If a calibration note implies a \
            concrete task, reminder, or follow-up action, include it in todos unless it is too \
            vague to turn into a useful item. Return only open actions, not completed events, \
            observations, memories, or descriptive sentences. Write each todo as a short verb-led \
            action phrase, not a full sentence. You may compress longer preparation or review tasks into cleaner action phrases while keeping the core action. \
            Good todo examples: "update the q1 report", "follow up with nithin", "prepare my presentation for the dfss senior director", "prepare for the reloshare training", "go through the transportation module". \
            Bad todo examples: "i had a great conversation with ben", "got feedback from nithin", "worked on the report". \
            If there are no action items, return an empty list \
            for todos.
            """)

        let response = try await session.respond(
            to: articlePrompt(
                for: transcript,
                userProfile: userProfile,
                calibrationNotes: calibrationNotes,
                currentArticle: currentArticle,
                variantMode: variantMode
            ),
            generating: ArticleResponse.self
        )

        var content = response.content
        let transcriptAnalysis = analyzeTranscript(transcript)
        content.article = formatArticleBody(content.article)
        if transcriptAnalysis.requiresLiteralHandling,
           articleContainsUnsupportedDetail(content.article, comparedTo: transcriptAnalysis) {
            content.article = literalArticleFallback(from: transcript)
        }
        content.keyword = sanitizedKeyword(
            content.keyword,
            transcript: transcript,
            transcriptAnalysis: transcriptAnalysis
        )
        content.article = WritingStyleFormatter.applyVisibleStyle(to: content.article, userProfile: userProfile)
        content.title = WritingStyleFormatter.applyTitleStyle(to: content.title)
        return content
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

    private func formatArticleBody(_ article: String) -> String {
        let cleaned = removeTrailingMetadata(from: article)
        if cleaned.contains("\n\n") {
            return cleaned
        }

        let sentences = sentenceSplit(from: cleaned)
        guard sentences.count > 3 else { return cleaned }

        let targetParagraphCount = min(4, max(2, Int(ceil(Double(sentences.count) / 3.0))))
        let sentencesPerParagraph = Int(ceil(Double(sentences.count) / Double(targetParagraphCount)))

        let paragraphs = stride(from: 0, to: sentences.count, by: sentencesPerParagraph).map { start in
            sentences[start..<min(start + sentencesPerParagraph, sentences.count)].joined(separator: " ")
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func removeTrailingMetadata(from article: String) -> String {
        let patterns = [
            #"\s+Keywords?:\s+.*$"#,
            #"\s+Tags?:\s+.*$"#,
            #"\s+Topic:\s+.*$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(article.startIndex..., in: article)
                if let match = regex.firstMatch(in: article, options: [], range: range) {
                    let trimmedRange = Range(match.range, in: article) ?? article.endIndex..<article.endIndex
                    return article[..<trimmedRange.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return article.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func articlePrompt(
        for transcript: String,
        userProfile: UserProfile?,
        calibrationNotes: [String],
        currentArticle: String?,
        variantMode: CalibrationVariantMode
    ) -> Prompt {
        let transcriptAnalysis = analyzeTranscript(transcript)

        return Prompt {
            defaultVoicePrompt

            """
            Keep the user's register, but do not collapse the piece into clipped dictation.
            The output should still feel rounded out, coherent, and more complete than the transcript.
            Do not imitate filler words, transcription artifacts, or spoken rambling.
            Do not exaggerate quirks or turn the voice into a caricature.
            This rule overrides all voice behavior: never fabricate events, people, conversations,
            or details that are not in the transcript. If the transcript is too sparse to fill out,
            write less rather than inventing more.
            """

            if transcriptAnalysis.requiresLiteralHandling {
                """
                Sparse transcript handling:
                The transcript is very short or fragmentary. Treat every concrete noun, person, place,
                and action in it as the full set of available facts. Do not infer scene-setting,
                motivations, emotional takeaways, dialogue, locations, or chronology that are not
                explicitly stated. Stay extremely close to the transcript. The safest acceptable output
                is a single short sentence or fragment that lightly smooths the wording without adding
                new factual content.
                """
            }

            if let currentArticle,
               !currentArticle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                """
                Current generated article:
                \(currentArticle)

                Use this as the base draft for the revision. Preserve its structure, focus, and
                supported details unless a calibration note requires a specific change. Do not
                re-summarize from scratch. If the current article contains any statement that is
                unsupported by the transcript or contradicted by a calibration note, remove or
                rewrite that statement instead of preserving it. Preserve the article's existing
                richness, completeness, and paragraph development unless a calibration note
                explicitly asks for a shorter or simpler rewrite.
                """
            }

            if !calibrationNotes.isEmpty {
                """
                Calibration notes:
                These are explicit user corrections and clarifications. Treat them as grounding
                constraints and follow them over weak inference or embellishment. They override the
                current article wherever there is any tension. Re-evaluate every concrete noun,
                count, relationship, and claim against these notes before producing the revision.
                Treat calibration notes as authoritative user-provided facts and corrections for
                this revision, even when they add detail that was omitted from the original
                transcript. If a calibration note introduces a concrete detail, incorporate that
                detail explicitly into the revised article instead of ignoring it or leaving the
                prior wording unchanged.
                Make the smallest effective revision needed to incorporate these notes. Keep the
                article anchored to the same underlying moment and subject matter as the current
                article. Do not introduce new themes, openings, scene-setting, or side details
                unless they are already present in the current article or explicitly stated in a
                calibration note. When possible, integrate a new note by inserting or refining
                the relevant sentence or paragraph rather than replacing the article with a
                thinner summary. Do not drop existing concrete details just to make room for the
                new note unless the new note directly contradicts them. If a calibration note
                refers to a person, place, event, or detail that is already mentioned in the
                current article, revise that existing passage instead of appending a separate
                duplicate mention later. Prefer merging new information into the nearest relevant
                sentence or paragraph. Only append a brand-new sentence when the calibration note
                introduces a genuinely new moment that is not already represented in the draft.
                Preserve unrelated compatible details elsewhere in the article, even when the
                calibration note only targets one passage. Do not delete later activities,
                locations, or side moments unless they directly conflict with the calibration
                note or are unsupported by the transcript. If a calibration note expresses a
                clear future plan, intention, reminder, or action item, treat it as a must-include
                follow-up detail even when it does not overlap an existing paragraph directly.
                In that case, append or lightly weave in a brief closing sentence that preserves
                the current draft while making the plan explicit. Also reflect those action-oriented
                calibration notes in the todos output. If a calibration note clearly describes a
                task, reminder, or plan, do not omit it from todos.
                If a calibration note negates, corrects, or replaces an existing claim in the
                current article, treat it as an explicit contradiction. Remove or rewrite the
                contradicted sentence rather than appending a clarification beside it. Also remove
                nearby follow-up inferences, scene details, or future plans that depended on the
                incorrect claim. Prefer replacement over coexistence when the note says the article
                got a concrete action, event, location, or plan wrong.
                """

                for note in calibrationNotes {
                    "- \(note)"
                }
            }

            """
            Revision mode:
            \(variantInstructions(for: variantMode))
            """

            "Transcript:\n\(transcript)"
        }
    }

    private func variantInstructions(for mode: CalibrationVariantMode) -> String {
        switch mode {
        case .balanced:
            return "Keep the article clearly tied to the original draft, but allow moderate rephrasing so the calibration notes fit naturally and the result reads smoothly. Preserve the draft's overall richness and keep the revised version feeling as complete as the original."
        case .tighter:
            return "Keep the calibrated facts intact, but make the rewrite a little tighter and more concise. Remove redundancy, shorten transitions, and compress the wording without dropping compatible details."
        case .fuller:
            return "Keep the calibrated facts intact, but let the rewrite feel slightly fuller and more rounded. Add connective tissue and flow while preserving the same facts and overall structure."
        case .cleaner:
            return "Keep the calibrated facts intact, but make the rewrite cleaner, more direct, and more organized. Favor clarity and efficient phrasing over flourish."
        case .warmer:
            return "Keep the calibrated facts intact, but make the rewrite feel a little warmer and more personal. Preserve the same events and details while softening the tone slightly."
        }
    }

    private var defaultVoicePrompt: String {
        """
        Fil voice:
        - relaxed, understated, message-native, and informal without forced slang or internet parody
        - direct and grounded without sounding packaged
        - never use the word "lowkey" in the output
        """
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

    private func articleContainsUnsupportedDetail(
        _ article: String,
        comparedTo transcriptAnalysis: TranscriptAnalysis
    ) -> Bool {
        let articleWords = article
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let novelWords = articleWords.filter { word in
            !Self.allowedNovelWords.contains(word) && !transcriptAnalysis.contentWords.contains(word)
        }

        return !novelWords.isEmpty
    }

    private func literalArticleFallback(from transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let lastCharacter = trimmed.last, [".", "!", "?"].contains(lastCharacter) {
            return trimmed
        }
        return trimmed + "."
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
