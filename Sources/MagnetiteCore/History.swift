import Foundation

public final class History {
    private var launches = UserDefaults.standard.dictionary(forKey: "launches") as? [String: [Double]] ?? [:] { didSet { UserDefaults.standard.set(launches, forKey: "launches") } }
    private var picks = UserDefaults.standard.dictionary(forKey: "picks") as? [String: String] ?? [:] { didSet { UserDefaults.standard.set(picks, forKey: "picks") } }
    public init() {}
    public func record(_ app: AppEntry, query: String) {
        launches[app.id] = Array(((launches[app.id] ?? []) + [Date().timeIntervalSince1970]).suffix(30))
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty { picks[q] = app.id }
    }
    public func forget(_ app: AppEntry?) {
        launches = launches.filter { app != nil && $0.key != app?.id }
        picks = picks.filter { app != nil && $0.value != app?.id }
    }
    func frecency(_ app: AppEntry, now: Double) -> Double { (launches[app.id] ?? []).reduce(0) { $0 + pow(0.5, (now - $1) / (14 * 86_400)) } }
    public func rank(_ apps: [AppEntry], query: String) -> [AppEntry] {
        let q = normalize(query.trimmingCharacters(in: .whitespaces)), chars = Array(q), now = Date().timeIntervalSince1970
        return apps.compactMap { app -> (app: AppEntry, score: Double)? in
            guard let match = app.searchKeys.compactMap({ $0.score(chars) }).max() else { return nil }
            return (app, match + min(150, 40 * log2(1 + frecency(app, now: now))) + (app.id == picks[q] ? 400 : 0))
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.app.name.count < $1.app.name.count }.map(\.app)
    }
    public func suggestions(_ apps: [AppEntry], limit: Int) -> [AppEntry] {
        let now = Date().timeIntervalSince1970
        return apps.map { ($0, frecency($0, now: now)) }.filter { $0.1 > 0.05 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
