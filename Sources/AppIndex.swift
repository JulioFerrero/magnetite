import AppKit

struct AppEntry: Hashable {
    let url: URL
    /// Name shown in the list (Finder's localized display name).
    let name: String
    /// Normalized names to match against: display name, file name, bundle name.
    let searchKeys: [SearchKey]
    /// Stable identity for usage stats: bundle identifier, or path when there is none.
    let id: String
}

/// A normalized string plus the offsets where words start (for "vsc" → Visual Studio Code).
struct SearchKey: Hashable {
    let text: [Character]
    let wordStarts: [Int]

    init(_ raw: String) {
        let original = Array(raw)
        let folded = Array(normalize(raw))
        text = folded
        var starts: [Int] = []
        let separators: Set<Character> = [" ", "-", "_", ".", "(", "/", "+"]
        let sameLength = original.count == folded.count
        for i in folded.indices {
            if separators.contains(folded[i]) { continue }
            if i == 0 || separators.contains(folded[i - 1]) {
                starts.append(i)
            } else if sameLength, original[i].isUppercase, original[i - 1].isLowercase {
                starts.append(i) // camelCase: CleanMyMac, TablePlus
            } else if folded[i].isNumber != folded[i - 1].isNumber {
                starts.append(i)
            }
        }
        wordStarts = starts
    }
}

func normalize(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
}

enum AppIndex {
    private static let roots = [
        "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
        NSString(string: "~/Applications").expandingTildeInPath,
    ]
    private static let extras = ["/System/Library/CoreServices/Finder.app"]

    /// Modification dates of the folders a scan walked. A folder's date changes
    /// whenever an app inside it is added, removed or replaced by an update.
    typealias Stamps = [String: Date]

    /// True when none of the scanned folders changed, so a rescan can be skipped
    /// (a couple dozen stat calls instead of reading every app's Info.plist).
    static func isUnchanged(_ stamps: Stamps) -> Bool {
        !stamps.isEmpty && stamps.allSatisfy { path, date in
            (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) == date
        }
    }

    /// Walks the application folders (a few levels deep, so "Adobe X/Adobe X.app" and
    /// "Chrome Apps.localized/*.app" are found). Takes a few milliseconds.
    static func scan() -> (apps: [AppEntry], stamps: Stamps) {
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var seenIDs = Set<String>()
        var apps: [AppEntry] = []
        var stamps: Stamps = [:]
        func stamp(_ url: URL) {
            stamps[url.path] = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath() // Safari.app is a symlink into a cryptex
            guard seenPaths.insert(resolved.path).inserted, fm.fileExists(atPath: resolved.path) else { return }
            let info = NSDictionary(contentsOf: resolved.appendingPathComponent("Contents/Info.plist"))
            let bundleID = info?["CFBundleIdentifier"] as? String
            if let bundleID, !seenIDs.insert(bundleID).inserted { return }

            var name = fm.displayName(atPath: resolved.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            let fileName = resolved.deletingPathExtension().lastPathComponent
            let bundleName = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String

            var keys = [name]
            for alias in [fileName, bundleName].compactMap({ $0 }) where !keys.contains(alias) {
                keys.append(alias)
            }
            apps.append(AppEntry(url: resolved, name: name, searchKeys: keys.map(SearchKey.init), id: bundleID ?? resolved.path))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let walker = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants] // not .skipsHiddenFiles: /Applications/Safari.app is flagged hidden
            ) else { continue }
            stamp(rootURL)
            for case let url as URL in walker {
                if url.lastPathComponent.hasPrefix(".") {
                    walker.skipDescendants()
                } else if url.pathExtension == "app" {
                    autoreleasepool { add(url) }
                    walker.skipDescendants()
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if walker.level < 3 { stamp(url) } else { walker.skipDescendants() }
                }
            }
        }
        extras.forEach { add(URL(fileURLWithPath: $0)) }

        return (apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, stamps)
    }
}

/// App icons rendered once at list size, so scrolling never waits on IconServices.
final class IconCache {
    private var images: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "magnetite.icons", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let size: CGFloat

    init(size: CGFloat) { self.size = size }

    func icon(for url: URL) -> NSImage {
        if let cached = images[url] { return cached }
        let image = render(url)
        images[url] = image
        return image
    }

    func prewarm(_ apps: [AppEntry]) {
        let missing = apps.map(\.url).filter { images[$0] == nil }
        guard !missing.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let rendered = missing.map { ($0, self.render($0)) }
            DispatchQueue.main.async {
                for (url, image) in rendered where self.images[url] == nil { self.images[url] = image }
            }
        }
    }

    /// One small @2x bitmap per app. The pool drops the full-size icon macOS
    /// hands back right away instead of after all 100+ are rendered.
    private func render(_ url: URL) -> NSImage {
        autoreleasepool {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let pixels = Int(size * 2)
            guard let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return icon }
            context.interpolationQuality = .high
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            guard let image = context.makeImage() else { return icon }
            return NSImage(cgImage: image, size: NSSize(width: size, height: size))
        }
    }
}
