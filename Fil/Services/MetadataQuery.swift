import Foundation

/// Classifies a search query as a pure metadata/filter query — by type ("photos", "links"), time
/// ("today", "last month", "3 weeks ago"), or to-dos ("todos") — so it can be answered
/// deterministically from a fil's real fields rather than as a text match. Text matching never worked
/// for these: a photo fil's text doesn't contain the word "photo", a link fil's doesn't contain
/// "link", nothing says "today". A content/semantic query returns nil here and falls through to
/// keyword (free) or cloud (Pro) search.
enum MetadataQuery {
    enum FilType { case photo, link, voice, video, pdf, note }

    /// A parsed temporal intent. `recent`/`forgotten` are count-based (the caller takes the top/bottom
    /// N); every other case resolves to a calendar-aligned date interval via `interval(now:)`.
    enum TimeSpec: Equatable {
        case recent, forgotten
        case today, yesterday, tonight, morning, weekend
        case thisWeek, lastWeek
        case thisMonth, lastMonth
        case thisYear, lastYear
        case daysAgo(Int), weeksAgo(Int), monthsAgo(Int), yearsAgo(Int)
        case weekday(Int)      // Calendar .weekday: 1 = Sunday ... 7 = Saturday
        case monthOfYear(Int)  // 1 = January ... 12 = December

        /// The date range this spec covers, relative to `now`. Calendar-aligned (a week is the current
        /// locale week, a month runs from the 1st, a year from Jan 1). Returns nil for the count-based
        /// `recent`/`forgotten`, which the caller handles by position instead of date.
        func interval(now: Date, calendar cal: Calendar = .current) -> DateInterval? {
            switch self {
            case .recent, .forgotten:
                return nil
            case .today:
                return cal.dateInterval(of: .day, for: now)
            case .yesterday:
                guard let d = cal.date(byAdding: .day, value: -1, to: now) else { return nil }
                return cal.dateInterval(of: .day, for: d)
            case .tonight:
                let start = cal.startOfDay(for: now)
                guard let six = cal.date(byAdding: .hour, value: 18, to: start),
                      let tomorrow = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
                return DateInterval(start: six, end: tomorrow)
            case .morning:
                let start = cal.startOfDay(for: now)
                guard let noon = cal.date(byAdding: .hour, value: 12, to: start) else { return nil }
                return DateInterval(start: start, end: noon)
            case .weekend:
                let sat = Self.mostRecent(weekday: 7, from: now, cal: cal)   // Saturday
                guard let end = cal.date(byAdding: .day, value: 2, to: sat) else { return nil }
                return DateInterval(start: sat, end: end)
            case .thisWeek:
                return cal.dateInterval(of: .weekOfYear, for: now)
            case .lastWeek:
                guard let d = cal.date(byAdding: .weekOfYear, value: -1, to: now) else { return nil }
                return cal.dateInterval(of: .weekOfYear, for: d)
            case .thisMonth:
                return cal.dateInterval(of: .month, for: now)
            case .lastMonth:
                guard let d = cal.date(byAdding: .month, value: -1, to: now) else { return nil }
                return cal.dateInterval(of: .month, for: d)
            case .thisYear:
                return cal.dateInterval(of: .year, for: now)
            case .lastYear:
                guard let d = cal.date(byAdding: .year, value: -1, to: now) else { return nil }
                return cal.dateInterval(of: .year, for: d)
            case .daysAgo(let n):
                guard let d = cal.date(byAdding: .day, value: -n, to: now) else { return nil }
                return cal.dateInterval(of: .day, for: d)
            case .weeksAgo(let n):
                guard let d = cal.date(byAdding: .weekOfYear, value: -n, to: now) else { return nil }
                return cal.dateInterval(of: .weekOfYear, for: d)
            case .monthsAgo(let n):
                guard let d = cal.date(byAdding: .month, value: -n, to: now) else { return nil }
                return cal.dateInterval(of: .month, for: d)
            case .yearsAgo(let n):
                guard let d = cal.date(byAdding: .year, value: -n, to: now) else { return nil }
                return cal.dateInterval(of: .year, for: d)
            case .weekday(let w):
                let day = Self.mostRecent(weekday: w, from: now, cal: cal)
                return cal.dateInterval(of: .day, for: day)
            case .monthOfYear(let m):
                let curMonth = cal.component(.month, from: now)
                let curYear = cal.component(.year, from: now)
                // Most recent occurrence: this year if the month has arrived, otherwise last year.
                let year = m <= curMonth ? curYear : curYear - 1
                var comps = DateComponents()
                comps.year = year; comps.month = m; comps.day = 1
                guard let d = cal.date(from: comps) else { return nil }
                return cal.dateInterval(of: .month, for: d)
            }
        }

        /// A short human phrase for this window, used to tell the summarizer what stretch of time it's
        /// reflecting on so it can look back appropriately ("this year", "last month", "3 days ago").
        var label: String {
            switch self {
            case .recent:            return "recently"
            case .forgotten:         return "a while ago"
            case .today:             return "today"
            case .yesterday:         return "yesterday"
            case .tonight:           return "tonight"
            case .morning:           return "this morning"
            case .weekend:           return "the weekend"
            case .thisWeek:          return "this week"
            case .lastWeek:          return "last week"
            case .thisMonth:         return "this month"
            case .lastMonth:         return "last month"
            case .thisYear:          return "this year"
            case .lastYear:          return "last year"
            case .daysAgo(let n):    return n == 1 ? "a day ago" : "\(n) days ago"
            case .weeksAgo(let n):   return n == 1 ? "a week ago" : "\(n) weeks ago"
            case .monthsAgo(let n):  return n == 1 ? "a month ago" : "\(n) months ago"
            case .yearsAgo(let n):   return n == 1 ? "a year ago" : "\(n) years ago"
            case .weekday(let w):    return Self.weekdayNames.indices.contains(w - 1) ? Self.weekdayNames[w - 1] : "that day"
            case .monthOfYear(let m): return Self.monthNames.indices.contains(m - 1) ? Self.monthNames[m - 1] : "that month"
            }
        }

        private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        private static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

        /// The most recent day (at 00:00) matching `weekday`, at or before `now`.
        private static func mostRecent(weekday w: Int, from now: Date, cal: Calendar) -> Date {
            let todayW = cal.component(.weekday, from: now)
            var diff = todayW - w
            if diff < 0 { diff += 7 }
            let day = cal.date(byAdding: .day, value: -diff, to: now) ?? now
            return cal.startOfDay(for: day)
        }
    }

    struct Filter: Equatable {
        var types: Set<FilType> = []
        var todosOnly = false
        var time: TimeSpec?
    }

    // MARK: - Vocabularies

    // Type triggers — plurals + common synonyms, matched token-wise.
    private static let photo: Set<String> = ["photo", "photos", "picture", "pictures", "pic", "pics", "image", "images"]
    private static let link: Set<String> = ["link", "links", "url", "urls", "website", "websites"]
    private static let voice: Set<String> = ["voice", "recording", "recordings", "audio", "memo", "memos"]
    private static let video: Set<String> = ["video", "videos"]
    private static let pdf: Set<String> = ["pdf", "pdfs"]
    private static let noteType: Set<String> = ["note", "notes", "text", "typed", "written"]
    private static let todo: Set<String> = ["todo", "todos", "task", "tasks", "do", "dos", "checklist"]

    // Time modifiers. "past"/"over" read as the current period-to-date ("the past week" = this week);
    // "last"/"previous" read as the whole previous period ("last week" = the prior calendar week). When
    // both appear ("this past week"), current wins.
    private static let currentMods: Set<String> = ["this", "current", "past"]
    private static let previousMods: Set<String> = ["last", "previous"]
    private static let recentSyn: Set<String> = ["recent", "recently", "recents", "lately", "latest", "new", "newest"]
    private static let forgottenSyn: Set<String> = ["forgotten", "forget", "forgot", "missed", "miss", "old", "older", "oldest", "earlier", "earliest"]

    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]
    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "couple": 2, "few": 3, "several": 5
    ]
    private static let units: [String: String] = [
        "day": "day", "days": "day", "week": "week", "weeks": "week",
        "month": "month", "months": "month", "year": "year", "years": "year"
    ]

    /// Words that carry no filter meaning; dropped before parsing. (Temporal modifiers like "this" /
    /// "last" / "past" are NOT here — the time parser needs them.)
    private static let filler: Set<String> = ["my", "show", "me", "all", "the", "a", "an", "see", "find", "get", "view", "just", "of", "mine", "for", "with", "have", "has", "i", "which", "to", "open", "any", "some", "list", "over", "from", "in", "on", "at"]
    /// Generic words for "a fil" — meaningless as a filter, so dropped too (e.g. "today thoughts").
    private static let generic: Set<String> = ["thoughts", "thought", "fils", "fil", "stuff", "things", "thing", "entries", "entry"]

    // MARK: - Classify

    /// Returns a Filter when the query is *entirely* filter vocabulary (type + time + to-do words +
    /// filler), else nil — so "photos from italy" ("italy" is content) goes to real search, but "recent
    /// photos" or "photos from last month" resolve to a filter.
    static func classify(_ query: String) -> Filter? {
        let cleaned = query.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
        let tokens = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) && !generic.contains($0) }
        guard !tokens.isEmpty else { return nil }

        var filter = Filter()
        var timeTokens: [String] = []
        // Pull type + to-do words out; whatever's left is a candidate time expression.
        for t in tokens {
            if photo.contains(t) { filter.types.insert(.photo) }
            else if link.contains(t) { filter.types.insert(.link) }
            else if voice.contains(t) { filter.types.insert(.voice) }
            else if video.contains(t) { filter.types.insert(.video) }
            else if pdf.contains(t) { filter.types.insert(.pdf) }
            else if noteType.contains(t) { filter.types.insert(.note) }
            else if todo.contains(t) { filter.todosOnly = true }
            else { timeTokens.append(t) }
        }

        // A leftover expression must parse cleanly as time, or the whole query is content, not a filter.
        if !timeTokens.isEmpty {
            guard let spec = parseTime(timeTokens) else { return nil }
            filter.time = spec
        }

        guard !filter.types.isEmpty || filter.todosOnly || filter.time != nil else { return nil }
        return filter
    }

    /// Parses a temporal expression — the tokens left after type/to-do/filler were removed. Must consume
    /// EVERY token (any unrecognized word means the query is really a content search) or it returns nil.
    private static func parseTime(_ toks: [String]) -> TimeSpec? {
        var isCurrent = false
        var isPrevious = false
        var sawAgo = false
        var number: Int?
        var unit: String?
        var standalone: TimeSpec?

        for t in toks {
            if currentMods.contains(t) { isCurrent = true }
            else if previousMods.contains(t) { isPrevious = true }
            else if t == "ago" { sawAgo = true }
            else if let u = units[t] { if unit != nil { return nil }; unit = u }
            else if let n = Int(t) ?? numberWords[t] { if number != nil { return nil }; number = n }
            else if let s = singleWordSpec(t) { if standalone != nil { return nil }; standalone = s }
            else { return nil }   // unknown token → not a pure time query
        }

        // A named point in time (today, monday, june, recent...) stands alone; it can't mix with a
        // counted unit expression.
        if let standalone {
            guard unit == nil, number == nil, !sawAgo else { return nil }
            return standalone
        }

        guard let unit else { return nil }

        // "N units ago" — a specific past day / week / month / year.
        if sawAgo {
            let n = number ?? 1
            switch unit {
            case "day":   return .daysAgo(n)
            case "week":  return .weeksAgo(n)
            case "month": return .monthsAgo(n)
            case "year":  return .yearsAgo(n)
            default:      return nil
            }
        }

        // A bare number with a unit but no "ago" ("3 weeks") is ambiguous — treat as content.
        if number != nil { return nil }

        // "this/last <unit>" (or a bare unit → the current period).
        let previous = isPrevious && !isCurrent
        switch unit {
        case "day":   return previous ? .yesterday : .today
        case "week":  return previous ? .lastWeek : .thisWeek
        case "month": return previous ? .lastMonth : .thisMonth
        case "year":  return previous ? .lastYear : .thisYear
        default:      return nil
        }
    }

    /// A single word that names a point in time on its own.
    private static func singleWordSpec(_ t: String) -> TimeSpec? {
        switch t {
        case "today":    return .today
        case "yesterday": return .yesterday
        case "tonight":  return .tonight
        case "morning":  return .morning
        case "weekend":  return .weekend
        default: break
        }
        if recentSyn.contains(t) { return .recent }
        if forgottenSyn.contains(t) { return .forgotten }
        if let w = weekdays[t] { return .weekday(w) }
        if let m = months[t] { return .monthOfYear(m) }
        return nil
    }
}
