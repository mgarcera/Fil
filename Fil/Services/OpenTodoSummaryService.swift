import Foundation
import FoundationModels

struct OpenTodoEntry: Identifiable, Hashable {
    let id: String
    let todoText: String
    let noteUUID: UUID
    let noteTitle: String
    let noteKeyword: String
    let noteTimestamp: Date
    let noteGradientStartHex: String
    let noteGradientEndHex: String
    let contextSnippet: String
}

struct OpenTodoSummary {
    let text: String
    let cards: [OpenTodoCardSummary]
}

struct OpenTodoCardSummary: Identifiable {
    let id: String
    let summary: String
    let todoText: String
    let noteUUID: UUID
    let gradientStartHex: String
    let gradientEndHex: String
}

@Generable(description: "A first-person recap of still-open to-dos")
private struct OpenTodoSummaryResponse {
    @Guide(description: "A concise paragraph recap of still-open to-dos in chronological order")
    var summary: String
}

@Generable(description: "A generated card for one grouped set of open to-dos")
private struct OpenTodoCardContentResponse {
    @Guide(description: "A concise first-person card summary with concrete task detail and a light follow-up thought when appropriate")
    var summary: String
}

final class OpenTodoSummaryService {
    static let shared = OpenTodoSummaryService()
    private var cachedSummaries: [String: OpenTodoSummary] = [:]

    func generateSummary(
        from entries: [OpenTodoEntry],
        context: FilTimeContext,
        userProfile: UserProfile? = nil,
        cacheKey: String? = nil
    ) async throws -> OpenTodoSummary {
        guard !entries.isEmpty else {
            return OpenTodoSummary(text: "", cards: [])
        }

        if let cacheKey, let cached = cachedSummaries[cacheKey] {
            return cached
        }

        let sortedEntries = entries.sorted { $0.noteTimestamp < $1.noteTimestamp }
        let summarySession = LanguageModelSession(instructions: """
            You are a concise assistant recapping one person's still-open to-dos. \
            Always assume every to-do belongs to the same speaker. \
            Write only in first person using "I" statements. \
            Never refer to the speaker as "they", "them", "the user", or by name. \
            You will receive time context and chronological to-do entries. Use them. \
            Keep the recap grounded in the provided open to-dos only. Do not invent new tasks, \
            locations, people, or motivations. You may add light connective phrasing, but every \
            concrete task must come directly from an open to-do entry. \
            Mention the actual open to-do wording rather than summarizing the broader article. \
            Mention items in strict chronological order based on their note timestamps, oldest first. \
            If an item is from today and the day is still in progress, prefer present-tense phrasing \
            like "today I plan to" or "I still need to." For older items, retrospective phrasing like \
            "yesterday I had to" is acceptable. \
            You may use note title, keyword, or context snippet to lightly frame a task, but do not \
            duplicate the full note content or turn this into a productivity dashboard. \
            Keep the recap compact, warm, and summary-like. Produce 2 to 5 sentences total. \
            Use Fil's default voice: relaxed, understated, message-native, and informal without forced slang or internet parody. \
            Keep the writing direct and grounded. Do not use the word "lowkey" in the output.
            """)

        let response = try await summarySession.respond(
            to: summaryPrompt(for: sortedEntries, context: context, userProfile: userProfile),
            generating: OpenTodoSummaryResponse.self
        )

        let summaryText = WritingStyleFormatter.applyVisibleStyle(
            to: response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            userProfile: userProfile
        )
        let groups = groupedEntries(from: sortedEntries)
        let cards = try await buildCards(groups: groups, context: context, userProfile: userProfile)
        let summary = OpenTodoSummary(text: summaryText, cards: cards)

        if let cacheKey {
            cachedSummaries[cacheKey] = summary
        }

        return summary
    }

    private func summaryPrompt(
        for entries: [OpenTodoEntry],
        context: FilTimeContext,
        userProfile: UserProfile?
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"

        let entryLines = entries.map { entry in
            """
            ID: \(entry.id)
            Timestamp: \(formatter.string(from: entry.noteTimestamp))
            Note title: \(entry.noteTitle)
            Note keyword: \(entry.noteKeyword.isEmpty ? "none" : entry.noteKeyword)
            Context snippet: \(entry.contextSnippet.isEmpty ? "none" : entry.contextSnippet)
            Open to-do: \(entry.todoText)
            """
        }

        return """
            Time Context:
            \(context.promptDescription)

            \(defaultVoicePrompt)

            Open To-Dos:
            \(entryLines.joined(separator: "\n\n"))
            """
    }

    private func buildCards(
        groups: [OpenTodoCardGroup],
        context: FilTimeContext,
        userProfile: UserProfile?
    ) async throws -> [OpenTodoCardSummary] {
        var cards: [OpenTodoCardSummary] = []

        for group in groups {
            let generated = cardCopy(for: group, context: context)

            cards.append(OpenTodoCardSummary(
                id: group.id,
                summary: WritingStyleFormatter.applyVisibleStyle(
                    to: sanitizedCardSummary(generated, fallback: generated),
                    userProfile: userProfile
                ),
                todoText: group.entries.map(\.todoText).joined(separator: ", "),
                noteUUID: group.noteUUID,
                gradientStartHex: group.gradientStartHex,
                gradientEndHex: group.gradientEndHex
            ))
        }

        return cards
    }

    private func cardCopy(for group: OpenTodoCardGroup, context: FilTimeContext) -> String {
        let phrases = cardActionPhrases(for: group, context: context)
        let lead = requiredLead(for: group, context: context)
        let actions = joinedActionPhrase(phrases)
        let firstSentence = "\(lead) \(actions)."

        guard shouldAddFollowUpSentence(for: group, phrases: phrases, context: context) else {
            return firstSentence
        }

        return "\(firstSentence) \(followUpSentence(for: group, phrases: phrases, context: context))"
    }

    private func sanitizedCardSummary(_ text: String, fallback: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "..", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return fallback }
        return compact
    }

    private func validatedCardSummary(
        _ text: String,
        requiredLead: String,
        fallback: String,
        group: OpenTodoCardGroup,
        context: FilTimeContext
    ) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()

        let forbiddenFragments = [
            "don't want to",
            "do not want to",
            "i'm excited",
            "i am excited",
            "i hope",
            "when i get home",
            "from work",
            "weather app"
        ]

        if forbiddenFragments.contains(where: { lowercased.contains($0) }) {
            return fallback
        }

        if !lowercased.hasPrefix(requiredLead.lowercased()) {
            return fallback
        }

        let sentences = sentenceComponents(in: normalized)
        if sentences.count != 2 {
            return fallback
        }

        if cardType(for: group) == .clustered, normalized.count > 220 {
            return fallback
        }

        if containsUnsupportedGeneratedDetail(in: normalized, group: group) {
            return fallback
        }

        if context.dayPartition.isToday(group.noteTimestamp) {
            let forbiddenTodayPhrases = [
                "today, i had to",
                "today, i needed to",
                "today, i was supposed to"
            ]
            if forbiddenTodayPhrases.contains(where: { lowercased.contains($0) }) {
                return fallback
            }
        }

        return normalized
    }

    private func requiredLead(for group: OpenTodoCardGroup, context: FilTimeContext) -> String {
        if context.dayPartition.isToday(group.noteTimestamp) {
            return "today, i plan to"
        }
        if context.dayPartition.isYesterday(group.noteTimestamp) {
            return "yesterday, i had to"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: group.noteTimestamp).lowercased()
        return "on \(weekday), i had to"
    }

    private func cardType(for group: OpenTodoCardGroup) -> OpenTodoCardType {
        group.entries.count > 1 ? .clustered : .single
    }

    private func cardActionPhrases(for group: OpenTodoCardGroup, context: FilTimeContext) -> [String] {
        let normalized = group.entries.map {
            polishedTodoPhrase(
                shiftRelativeDayTerms(
                    in: normalizedTodoPhrase($0.todoText),
                    from: group.noteTimestamp,
                    context: context
                )
            )
        }
        .filter { !$0.isEmpty }

        var selected: [String] = []
        for phrase in normalized {
            let key = phrase.lowercased()
            let overlapsExisting = selected.contains { existing in
                let existingKey = existing.lowercased()
                return existingKey.contains(key) || key.contains(existingKey)
            }
            if !overlapsExisting {
                selected.append(phrase)
            }
        }

        if cardType(for: group) == .clustered, specificityBudget(for: group) == .one {
            return Array(selected.prefix(1))
        }

        return Array(selected.prefix(2))
    }

    private func joinedActionPhrase(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0:
            return "follow through on it"
        case 1:
            return phrases[0]
        case 2:
            return "\(phrases[0]) and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases[phrases.count - 1])"
        }
    }

    private func shouldAddFollowUpSentence(
        for group: OpenTodoCardGroup,
        phrases: [String],
        context: FilTimeContext
    ) -> Bool {
        guard !context.dayPartition.isToday(group.noteTimestamp) else {
            return false
        }
        return phrases.count == 1
    }

    private func followUpSentence(
        for group: OpenTodoCardGroup,
        phrases: [String],
        context: FilTimeContext
    ) -> String {
        if context.dayPartition.isYesterday(group.noteTimestamp) {
            return "i should make sure i work on it today."
        }

        let label = relativeLabel(for: group.noteTimestamp, context: context)
        return "i should make sure i keep working on it after \(label)."
    }

    private func sentenceComponents(in text: String) -> [String] {
        text
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fallbackTopic(for group: OpenTodoCardGroup) -> String? {
        let keyword = group.entries.first?.noteKeyword.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !keyword.isEmpty {
            return keyword.lowercased()
        }

        let title = group.entries.first?.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title.lowercased()
    }

    private func representativeClusteredPhrases(for group: OpenTodoCardGroup, context: FilTimeContext) -> [String] {
        let normalized = group.entries.map {
            normalizedRepresentativePhrase(
                shiftRelativeDayTerms(
                    in: normalizedTodoPhrase($0.todoText),
                    from: group.noteTimestamp,
                    context: context
                )
            )
        }

        var selected: [String] = []
        for phrase in normalized {
            guard !phrase.isEmpty else { continue }
            let key = phrase.lowercased()
            let overlapsExisting = selected.contains { existing in
                let existingKey = existing.lowercased()
                return existingKey.contains(key) || key.contains(existingKey)
            }
            if !overlapsExisting {
                selected.append(phrase)
            }
            if selected.count == 2 {
                break
            }
        }

        let fallbackSelection = selected.isEmpty ? Array(normalized.prefix(2)) : selected
        return clusteredPhraseBudgetedSelection(from: fallbackSelection, sourceEntries: group.entries)
    }

    private func normalizedRepresentativePhrase(_ phrase: String) -> String {
        let trimmed = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("check ") {
            return "checking " + String(trimmed.dropFirst("check ".count))
        }
        if lowercased.hasPrefix("make sure to ") {
            return String(trimmed.dropFirst("make sure to ".count))
        }
        if lowercased.hasPrefix("prepare ") {
            return "preparing " + String(trimmed.dropFirst("prepare ".count))
        }
        if lowercased.hasPrefix("plan ") {
            return "planning " + String(trimmed.dropFirst("plan ".count))
        }
        if lowercased.hasPrefix("test ") {
            return "testing " + String(trimmed.dropFirst("test ".count))
        }
        if lowercased.hasPrefix("gather ") {
            return "gathering " + String(trimmed.dropFirst("gather ".count))
        }
        if lowercased.hasPrefix("hang ") {
            return "hanging " + String(trimmed.dropFirst("hang ".count))
        }
        if lowercased.hasPrefix("review ") {
            return "reviewing " + String(trimmed.dropFirst("review ".count))
        }

        return trimmed
    }

    private func joinedRepresentativePhrases(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0:
            return "the most important pieces"
        case 1:
            return phrases[0]
        case 2:
            return "\(phrases[0]) and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases[phrases.count - 1])"
        }
    }

    private func clusteredPhraseBudgetedSelection(
        from phrases: [String],
        sourceEntries: [OpenTodoEntry]
    ) -> [String] {
        guard !phrases.isEmpty else { return phrases }

        let sourceWordCount = sourceEntries.reduce(0) { partialResult, entry in
            partialResult + wordCount(in: entry.todoText)
        }
        let phraseWordCount = phrases.reduce(0) { partialResult, phrase in
            partialResult + wordCount(in: phrase)
        }

        let shouldCollapseToOne =
            phrases.count > 1 &&
            (sourceEntries.count >= 2 && sourceWordCount >= 18 || phraseWordCount >= 12)

        if shouldCollapseToOne {
            return [phrases[0]]
        }

        return phrases
    }

    private func specificityBudget(for group: OpenTodoCardGroup) -> OpenTodoSpecificityBudget {
        let representativePhrases = group.entries.map {
            normalizedRepresentativePhrase(normalizedTodoPhrase($0.todoText))
        }
        let sourceWordCount = group.entries.reduce(0) { partialResult, entry in
            partialResult + wordCount(in: entry.todoText)
        }
        let phraseWordCount = representativePhrases.reduce(0) { partialResult, phrase in
            partialResult + wordCount(in: phrase)
        }

        if group.entries.count >= 2 && (sourceWordCount >= 18 || phraseWordCount >= 12) {
            return .one
        }

        return .two
    }

    private func wordCount(in text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private func containsUnsupportedGeneratedDetail(in summary: String, group: OpenTodoCardGroup) -> Bool {
        let summaryLowercased = summary.lowercased()
        let sourceCorpus = sourceCorpus(for: group)
        let sensitiveTerms = [
            "tester feedback",
            "beta tester",
            "beta testers",
            "tester",
            "testers"
        ]

        return sensitiveTerms.contains { term in
            summaryLowercased.contains(term) && !sourceCorpus.contains(term)
        }
    }

    private func sourceCorpus(for group: OpenTodoCardGroup) -> String {
        let todos = group.entries.map(\.todoText).joined(separator: " ")
        let titles = group.entries.map(\.noteTitle).joined(separator: " ")
        let keywords = group.entries.map(\.noteKeyword).joined(separator: " ")
        let snippets = group.entries.map(\.contextSnippet).joined(separator: " ")
        return [todos, titles, keywords, snippets]
            .joined(separator: " ")
            .lowercased()
    }


    private func groupedEntries(from entries: [OpenTodoEntry]) -> [OpenTodoCardGroup] {
        let grouped = Dictionary(grouping: entries, by: \.noteUUID)

        return grouped.values
            .compactMap { entriesForNote in
                guard let first = entriesForNote.first else { return nil }
                return OpenTodoCardGroup(
                    id: first.noteUUID.uuidString,
                    noteUUID: first.noteUUID,
                    noteTimestamp: first.noteTimestamp,
                    gradientStartHex: first.noteGradientStartHex,
                    gradientEndHex: first.noteGradientEndHex,
                    entries: entriesForNote
                )
            }
            .sorted { $0.noteTimestamp < $1.noteTimestamp }
    }

    private func combinedTodoPhrase(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0:
            return ""
        case 1:
            return phrases[0]
        case 2:
            return "\(phrases[0]) and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases[phrases.count - 1])"
        }
    }

    private func normalizedTodoPhrase(_ todoText: String) -> String {
        var phrase = todoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "i need to ",
            "i still need to ",
            "i have to ",
            "i had to ",
            "i should ",
            "need to ",
            "have to ",
            "should ",
            "remember to ",
            "plan to ",
            "to "
        ]

        for prefix in prefixes where phrase.lowercased().hasPrefix(prefix) {
            phrase.removeFirst(prefix.count)
            break
        }

        return phrase
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t-.,"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func polishedTodoPhrase(_ phrase: String) -> String {
        var polished = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let literalReplacements: [(String, String)] = [
            ("following up with", "follow up with"),
            ("follow-up with", "follow up with"),
            ("prepare for presentation", "prepare my presentation"),
            ("presentation to ", "presentation for "),
            ("dfss senior director", "the dfss senior director"),
            (" q1 ", " the q1 ")
        ]

        for (source, replacement) in literalReplacements {
            polished = replacingCaseInsensitive(source, in: polished, with: replacement)
        }

        polished = polished
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;"))

        return polished
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

    private func shiftRelativeDayTerms(
        in text: String,
        from noteTimestamp: Date,
        context: FilTimeContext
    ) -> String {
        var updated = text
        let replacements: [(String, Int)] = [
            ("today", 0),
            ("tomorrow", 1),
            ("yesterday", -1)
        ]

        for (term, dayOffset) in replacements {
            updated = replacingStandaloneTerm(
                term,
                in: updated,
                with: relativeLabel(
                    for: context.calendar.date(byAdding: .day, value: dayOffset, to: noteTimestamp) ?? noteTimestamp,
                    context: context
                )
            )
        }

        return updated
    }

    private func replacingStandaloneTerm(_ term: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: term))\\b", options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func relativeLabel(for date: Date, context: FilTimeContext) -> String {
        context.dayPartition.relativeLabel(for: date)
    }

    private var defaultVoicePrompt: String {
        """
        Fil voice:
        - relaxed, understated, message-native, and informal without forced slang or internet parody
        - direct and task-native without sounding packaged
        - never use the word "lowkey" in the output
        """
    }

}

private struct OpenTodoCardGroup {
    let id: String
    let noteUUID: UUID
    let noteTimestamp: Date
    let gradientStartHex: String
    let gradientEndHex: String
    let entries: [OpenTodoEntry]
}

private enum OpenTodoCardType: String {
    case single
    case clustered
}

private enum OpenTodoSpecificityBudget: String {
    case one
    case two
}
