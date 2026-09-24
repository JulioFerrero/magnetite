import AppKit

struct AppEntry: Hashable {
    let url: URL, name: String, searchKeys: [SearchKey], id: String
}

struct SearchKey: Hashable {
    let text: [Character], wordStarts: [Int]

    init(_ raw: String) {
        let original = Array(raw), folded = Array(normalize(raw)), separators = Set(" -_.(/+")
        text = folded
        wordStarts = folded.indices.filter { i in
            !separators.contains(folded[i]) && (i == 0 || separators.contains(folded[i - 1])
                || (original.count == folded.count && original[i].isUppercase && original[i - 1].isLowercase)
                || folded[i].isNumber != folded[i - 1].isNumber)
        }
    }
}

func normalize(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
}

enum AppIndex {
    typealias Stamps = [String: Date]

    private static let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                                NSString(string: "~/Applications").expandingTildeInPath].map { URL(fileURLWithPath: $0) }

    static func isUnchanged(_ stamps: Stamps) -> Bool {
        !stamps.isEmpty && stamps.allSatisfy { (try? FileManager.default.attributesOfItem(atPath: $0.key)[.modificationDate] as? Date) == $0.value }
    }

    static func scan() -> (apps: [AppEntry], stamps: Stamps) {
        let fm = FileManager.default
        var seenPaths = Set<String>(), seenIDs = Set<String>(), apps: [AppEntry] = [], stamps: Stamps = [:]
        func stamp(_ url: URL) { stamps[url.path] = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        func add(_ url: URL) {
            let url = url.resolvingSymlinksInPath()
            guard seenPaths.insert(url.path).inserted, fm.fileExists(atPath: url.path) else { return }
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let bundleID = info?["CFBundleIdentifier"] as? String
            if let bundleID, !seenIDs.insert(bundleID).inserted { return }
            let display = fm.displayName(atPath: url.path), name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
            let keys = [name, url.deletingPathExtension().lastPathComponent, info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String]
                .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            apps.append(AppEntry(url: url, name: name, searchKeys: keys.map(SearchKey.init), id: bundleID ?? url.path))
        }
        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: .skipsPackageDescendants)
            else { continue }
            stamp(root)
            for case let url as URL in walker {
                if url.lastPathComponent.hasPrefix(".") {
                    walker.skipDescendants()
                } else if url.pathExtension == "app" {
                    autoreleasepool { add(url) }
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

final class IconCache {
    private var images: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "magnetite.icons", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let size: CGFloat

    init(size: CGFloat) { self.size = size }

    func icon(for url: URL) -> NSImage {
        if images[url] == nil { images[url] = render(url) }
        return images[url]!
    }

    func prewarm(_ apps: [AppEntry]) {
        let missing = apps.map(\.url).filter { images[$0] == nil }
        queue.async {
            let rendered = missing.map { ($0, self.render($0)) }
            DispatchQueue.main.async { for (url, image) in rendered where self.images[url] == nil { self.images[url] = image } }
        }
    }

    private func render(_ url: URL) -> NSImage {
        autoreleasepool {
            let icon = NSWorkspace.shared.icon(forFile: url.path), pixels = Int(size * 2)
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return icon }
            context.interpolationQuality = .high
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: size, height: size)) } ?? icon
        }
    }
}
