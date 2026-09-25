import Foundation

public struct LauncherState {
    public enum Row {
        case header(String), app(AppEntry, removable: Bool = false)
        public var app: AppEntry? { if case .app(let app, _) = self { app } else { nil } }
    }
    public private(set) var rows: [Row] = []
    public var selected: Int?, hovered: Int?
    public var selectedApp: AppEntry? { selected.flatMap { rows[$0].app } }
    public init() {}
    public mutating func load(_ apps: [AppEntry], query: String, history: History, suggestions: Int, update: AppEntry? = nil) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let suggested = history.suggestions(apps, limit: suggestions), ids = Set(suggested.map(\.id))
            let recent: [Row] = suggested.isEmpty ? [] : [.header("Suggestions")] + suggested.map { .app($0, removable: true) }
            let updates: [Row] = update.map { [.header("New Version"), .app($0)] } ?? []
            rows = updates + recent + [.header("Applications")] + apps.filter { !ids.contains($0.id) }.map { .app($0) }
        } else {
            let results = history.rank(apps, query: query)
            rows = results.isEmpty ? [] : [.header("Results")] + results.map { .app($0) }
        }
        (selected, hovered) = (rows.firstIndex { $0.app != nil && $0.app != update }, nil)
    }
    public func app(at row: Int?) -> Int? { row.flatMap { rows.indices.contains($0) && rows[$0].app != nil ? $0 : nil } }
    public func step(_ delta: Int) -> (row: Int, reveal: Int)? {
        guard var next = selected.map({ $0 + delta }) else { return nil }
        while rows.indices.contains(next), rows[next].app == nil { next += delta }
        guard rows.indices.contains(next) else { return nil }
        return (next, delta < 0 && next > 0 && rows[next - 1].app == nil ? next - 1 : next)
    }
}
