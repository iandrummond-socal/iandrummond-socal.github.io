import Foundation

enum SortMode: String, CaseIterable, Identifiable {
    case modified
    case title

    var id: String { rawValue }
    var label: String {
        switch self {
        case .modified: return "Modified"
        case .title: return "Title"
        }
    }
}

/// Pure, synchronous search over the in-memory notes. No I/O, so it is safe to run on every keystroke.
enum SearchEngine {
    static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// A note matches if every whitespace-separated token appears in its title or body (case-insensitive).
    /// Ranking: title starts with the query, then all tokens in the title, then body matches; ties by sort mode.
    static func filter(_ notes: [Note], query: String, sort: SortMode) -> [Note] {
        let toks = tokens(query)
        guard !toks.isEmpty else { return sorted(notes, by: sort) }
        let whole = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var ranked: [(rank: Int, note: Note)] = []
        for note in notes {
            var allInTitle = true
            var matches = true
            for t in toks {
                if note.lowerTitle.contains(t) { continue }
                allInTitle = false
                if !note.lowerBody.contains(t) { matches = false; break }
            }
            guard matches else { continue }
            let rank = note.lowerTitle.hasPrefix(whole) ? 0 : (allInTitle ? 1 : 2)
            ranked.append((rank, note))
        }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return isOrdered(a.note, before: b.note, by: sort)
        }
        return ranked.map(\.note)
    }

    static func sorted(_ notes: [Note], by sort: SortMode) -> [Note] {
        notes.sorted { isOrdered($0, before: $1, by: sort) }
    }

    /// Exact title match (case-insensitive, after the same cleaning a new title would get).
    static func exactMatch(in notes: [Note], title: String) -> Note? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = (FilenameRules.cleanTitle(trimmed) ?? trimmed).lowercased()
        return notes.first { $0.lowerTitle == key }
    }

    /// The single note whose title starts with the query, if exactly one does.
    static func uniquePrefixMatch(in notes: [Note], query: String) -> Note? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        var found: Note?
        for n in notes where n.lowerTitle.hasPrefix(q) {
            if found != nil { return nil }
            found = n
        }
        return found
    }

    private static func isOrdered(_ a: Note, before b: Note, by sort: SortMode) -> Bool {
        switch sort {
        case .modified:
            if a.modified != b.modified { return a.modified > b.modified }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .title:
            let order = a.title.localizedStandardCompare(b.title)
            if order != .orderedSame { return order == .orderedAscending }
            return a.modified > b.modified
        }
    }
}
