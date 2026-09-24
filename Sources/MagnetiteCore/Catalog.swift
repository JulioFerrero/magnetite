import Foundation

public struct AppEntry: Hashable {
    public let url: URL, name: String, id: String
    let searchKeys: [SearchKey]
}

public enum Catalog {
    public typealias Stamps = [String: Date]
    private static let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                                NSString(string: "~/Applications").expandingTildeInPath].map { URL(fileURLWithPath: $0) }
    public static func isUnchanged(_ stamps: Stamps) -> Bool {
        !stamps.isEmpty && stamps.allSatisfy { (try? FileManager.default.attributesOfItem(atPath: $0.key)[.modificationDate] as? Date) == $0.value }
    }
    public static func scan() -> (apps: [AppEntry], stamps: Stamps) {
        let fm = FileManager.default
        var seenPaths = Set<String>(), seenIDs = Set<String>(), apps: [AppEntry] = [], stamps: Stamps = [:]
        func stamp(_ url: URL) { stamps[url.path] = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        func add(_ url: URL) {
            let url = url.resolvingSymlinksInPath()
            guard seenPaths.insert(url.path).inserted, fm.fileExists(atPath: url.path) else { return }
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")), bundleID = info?["CFBundleIdentifier"] as? String
            if let bundleID, !seenIDs.insert(bundleID).inserted { return }
            let display = fm.displayName(atPath: url.path), name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
            let keys = [name, url.deletingPathExtension().lastPathComponent, info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String]
                .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            apps.append(AppEntry(url: url, name: name, id: bundleID ?? url.path, searchKeys: keys.map(SearchKey.init)))
        }
        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: .skipsPackageDescendants) else { continue }
            stamp(root)
            for case let url as URL in walker {
                if url.lastPathComponent.hasPrefix(".") || url.pathExtension == "app" {
                    if url.pathExtension == "app" { autoreleasepool { add(url) } }
                    walker.skipDescendants()
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walker.level < 3 ? stamp(url) : walker.skipDescendants()
                }
            }
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        return (apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, stamps)
    }
}
