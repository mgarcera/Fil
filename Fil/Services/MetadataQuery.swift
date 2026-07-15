import Foundation

/// Classifies a search query as a pure metadata/filter query — by type ("photos", "links"), time
/// ("today", "recently"), or to-dos ("todos") — so it can be answered deterministically from a fil's
/// real fields rather than as a text match. Text matching never worked for these: a photo fil's text
/// doesn't contain the word "photo", a link fil's doesn't contain "link", nothing says "today". A
/// content/semantic query returns nil here and falls through to keyword (free) or cloud (Pro) search.
enum MetadataQuery {
    enum FilType { case photo, link, voice, video, pdf, note }
    enum TimeWindow { case today, yesterday, thisWeek, recent, forgotten }

    struct Filter: Equatable {
        var types: Set<FilType> = []
        var todosOnly = false
        var time: TimeWindow?
    }

    // Trigger vocabularies — plurals + common synonyms, matched token-wise.
    private static let photo: Set<String> = ["photo", "photos", "picture", "pictures", "pic", "pics", "image", "images"]
    private static let link: Set<String> = ["link", "links", "url", "urls", "website", "websites"]
    private static let voice: Set<String> = ["voice", "recording", "recordings", "audio", "memo", "memos"]
    private static let video: Set<String> = ["video", "videos"]
    private static let pdf: Set<String> = ["pdf", "pdfs"]
    private static let noteType: Set<String> = ["note", "notes", "text", "typed", "written"]
    private static let todo: Set<String> = ["todo", "todos", "task", "tasks", "do", "dos", "checklist"]
    private static let today: Set<String> = ["today"]
    private static let yesterday: Set<String> = ["yesterday"]
    private static let week: Set<String> = ["week"]
    private static let recent: Set<String> = ["recent", "recently", "recents", "lately", "latest", "new", "newest"]
    private static let forgotten: Set<String> = ["forgotten", "forget", "forgot", "missed", "miss", "old", "older", "oldest", "earlier", "earliest"]

    /// Words that carry no filter meaning; dropped before deciding whether the query is a pure filter.
    private static let filler: Set<String> = ["my", "show", "me", "all", "the", "a", "an", "see", "find", "get", "view", "just", "of", "mine", "for", "with", "that", "have", "has", "i", "which", "this", "to", "open", "any", "some", "list"]
    /// Generic words for "a fil" — meaningless as a filter, so dropped too (e.g. "today thoughts").
    private static let generic: Set<String> = ["thoughts", "thought", "fils", "fil", "stuff", "things", "thing", "entries", "entry"]

    /// Returns a Filter when the query is *entirely* filter vocabulary (type/time/to-do words + filler),
    /// else nil — so "photos from italy" ("italy" is content) goes to real search, but "recent photos"
    /// resolves to a filter.
    static func classify(_ query: String) -> Filter? {
        let cleaned = query.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
        let tokens = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) && !generic.contains($0) }
        guard !tokens.isEmpty else { return nil }

        let vocab = photo.union(link).union(voice).union(video).union(pdf)
            .union(noteType).union(todo).union(today).union(yesterday).union(week).union(recent).union(forgotten)
        // A token outside the filter vocabulary means this is a content query, not a pure filter.
        guard tokens.allSatisfy({ vocab.contains($0) }) else { return nil }

        let set = Set(tokens)
        var filter = Filter()
        if !set.isDisjoint(with: photo) { filter.types.insert(.photo) }
        if !set.isDisjoint(with: link) { filter.types.insert(.link) }
        if !set.isDisjoint(with: voice) { filter.types.insert(.voice) }
        if !set.isDisjoint(with: video) { filter.types.insert(.video) }
        if !set.isDisjoint(with: pdf) { filter.types.insert(.pdf) }
        if !set.isDisjoint(with: noteType) { filter.types.insert(.note) }
        if !set.isDisjoint(with: todo) { filter.todosOnly = true }

        // Time windows are mutually exclusive; first match wins.
        if !set.isDisjoint(with: today) { filter.time = .today }
        else if !set.isDisjoint(with: yesterday) { filter.time = .yesterday }
        else if set.contains("week") { filter.time = .thisWeek }
        else if !set.isDisjoint(with: forgotten) { filter.time = .forgotten }
        else if !set.isDisjoint(with: recent) { filter.time = .recent }

        guard !filter.types.isEmpty || filter.todosOnly || filter.time != nil else { return nil }
        return filter
    }
}
