import Foundation

/// Scores how well a query matches a name. Tiers, best first: exact, prefix,
/// word prefix ("chr" → Google Chrome), initials ("vsc" → Visual Studio Code),
/// substring, then in-order fuzzy ("gchr" → Google Chrome). nil means no match.
enum Matcher {
    static func score(_ query: [Character], _ key: SearchKey) -> Double? {
        let text = key.text
        guard !query.isEmpty else { return nil }

        if text == query { return 1000 }
        if text.starts(with: query) { return 900 + 50 * Double(query.count) / Double(text.count) }

        for (n, start) in key.wordStarts.enumerated() where start > 0 && text[start...].starts(with: query) {
            return 800 - Double(n)
        }

        let initials = key.wordStarts.map { text[$0] }
        if query.count >= 2, initials.starts(with: query) { return 750 }

        if let offset = firstIndex(of: query, in: text) { return 600 - Double(offset) }

        return fuzzy(query, key)
    }

    /// Every query character must appear in order, starting at a word start
    /// (so "not" doesn't match "Screenshot"). Rewards consecutive runs and hits
    /// at word starts; penalizes gaps.
    private static func fuzzy(_ query: [Character], _ key: SearchKey) -> Double? {
        let needle = query.filter { $0 != " " }
        guard let first = needle.first,
              let start = key.wordStarts.first(where: { key.text[$0] == first }) else { return nil }
        let text = key.text
        let wordStarts = Set(key.wordStarts)
        var score = 300.0
        var ti = start + 1
        var previous = start
        for ch in needle.dropFirst() {
            while ti < text.count, text[ti] != ch { ti += 1 }
            guard ti < text.count else { return nil }
            if ti == previous + 1 { score += 12 }
            else if wordStarts.contains(ti) { score += 8 }
            else { score -= Double(min(ti - previous, 10)) * 2 }
            previous = ti
            ti += 1
        }
        return max(score, 100)
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for i in 0...(haystack.count - needle.count) where haystack[i..<(i + needle.count)].elementsEqual(needle) {
            return i
        }
        return nil
    }
}

/// Remembers what you open so frequent apps rise to the top, and which app you
/// picked for a given query so typing it again selects the same app.
final class Usage {
    private let defaults = UserDefaults.standard
    private var launches: [String: [Double]]
    private var picks: [String: String]
    private static let halfLife: Double = 14 * 86_400

    init() {
        launches = defaults.dictionary(forKey: "launches") as? [String: [Double]] ?? [:]
        picks = defaults.dictionary(forKey: "picks") as? [String: String] ?? [:]
    }

    func record(_ app: AppEntry, query: String) {
        var times = launches[app.id] ?? []
        times.append(Date().timeIntervalSince1970)
        launches[app.id] = Array(times.suffix(30))
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty { picks[q] = app.id }
        defaults.set(launches, forKey: "launches")
        defaults.set(picks, forKey: "picks")
    }

    /// Sum of launches, each decaying with a two-week half-life.
    func frecency(_ app: AppEntry, now: Double = Date().timeIntervalSince1970) -> Double {
        (launches[app.id] ?? []).reduce(0) { $0 + pow(0.5, (now - $1) / Self.halfLife) }
    }

    func rank(_ apps: [AppEntry], query: String) -> [AppEntry] {
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        let chars = Array(q)
        let picked = picks[q]
        let now = Date().timeIntervalSince1970
        var scored: [(app: AppEntry, score: Double)] = []
        for app in apps {
            guard let match = app.searchKeys.compactMap({ Matcher.score(chars, $0) }).max() else { continue }
            var score = match + min(150, 40 * log2(1 + frecency(app, now: now)))
            if app.id == picked { score += 400 }
            scored.append((app, score))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.app.name.count < $1.app.name.count }
            .map(\.app)
    }

    func suggestions(_ apps: [AppEntry], limit: Int) -> [AppEntry] {
        let now = Date().timeIntervalSince1970
        return apps
            .map { ($0, frecency($0, now: now)) }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
