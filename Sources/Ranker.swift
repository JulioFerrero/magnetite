import Foundation

enum Matcher {
    static func score(_ query: [Character], _ key: SearchKey) -> Double? {
        let text = key.text
        guard !query.isEmpty else { return nil }
        if text == query { return 1000 }
        if text.starts(with: query) { return 900 + 50 * Double(query.count) / Double(text.count) }
        if let n = key.wordStarts.enumerated().first(where: { $0.element > 0 && text[$0.element...].starts(with: query) })?.offset { return 800 - Double(n) }
        if query.count >= 2, key.wordStarts.map({ text[$0] }).starts(with: query) { return 750 }
        if let offset = text.indices.first(where: { text[$0...].starts(with: query) }) { return 600 - Double(offset) }
        return fuzzy(query, key)
    }

    private static func fuzzy(_ query: [Character], _ key: SearchKey) -> Double? {
        let needle = query.filter { $0 != " " }, text = key.text, starts = Set(key.wordStarts)
        guard let first = needle.first, var previous = key.wordStarts.first(where: { text[$0] == first }) else { return nil }
        var score = 300.0
        for ch in needle.dropFirst() {
            guard let i = text[(previous + 1)...].firstIndex(of: ch) else { return nil }
            score += i == previous + 1 ? 12 : starts.contains(i) ? 8 : -2 * Double(min(i - previous, 10))
            previous = i
        }
        return max(score, 100)
    }
}

final class Usage {
    private var launches = UserDefaults.standard.dictionary(forKey: "launches") as? [String: [Double]] ?? [:] {
        didSet { UserDefaults.standard.set(launches, forKey: "launches") }
    }
    private var picks = UserDefaults.standard.dictionary(forKey: "picks") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(picks, forKey: "picks") }
    }

    func record(_ app: AppEntry, query: String) {
        launches[app.id] = Array(((launches[app.id] ?? []) + [Date().timeIntervalSince1970]).suffix(30))
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty { picks[q] = app.id }
    }

    func forget(_ app: AppEntry?) {
        if let app {
            launches[app.id] = nil
            picks = picks.filter { $0.value != app.id }
        } else {
            (launches, picks) = ([:], [:])
        }
    }

    func frecency(_ app: AppEntry, now: Double = Date().timeIntervalSince1970) -> Double {
        (launches[app.id] ?? []).reduce(0) { $0 + pow(0.5, (now - $1) / (14 * 86_400)) }
    }

    func rank(_ apps: [AppEntry], query: String) -> [AppEntry] {
        let q = normalize(query.trimmingCharacters(in: .whitespaces)), chars = Array(q), now = Date().timeIntervalSince1970
        return apps.compactMap { app -> (app: AppEntry, score: Double)? in
            guard let match = app.searchKeys.compactMap({ Matcher.score(chars, $0) }).max() else { return nil }
            return (app, match + min(150, 40 * log2(1 + frecency(app, now: now))) + (app.id == picks[q] ? 400 : 0))
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.app.name.count < $1.app.name.count }
        .map(\.app)
    }

    func suggestions(_ apps: [AppEntry], limit: Int) -> [AppEntry] {
        let now = Date().timeIntervalSince1970
        return apps.map { ($0, frecency($0, now: now)) }.filter { $0.1 > 0.05 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
