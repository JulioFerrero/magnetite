import CryptoKit
import Foundation

public struct Update: Decodable {
    struct Asset: Decodable { let name: String, browserDownloadUrl: URL, digest: String? }
    let tagName: String, assets: [Asset]
    public let htmlUrl: URL
    public var entry: AppEntry { AppEntry(url: Bundle.main.bundleURL, name: "Update Magnetite to \(tagName.dropFirst())", id: tagName, searchKeys: []) }
}

public enum Updater {
    private static let session = URLSession(configuration: .ephemeral), app = Bundle.main.bundleURL
    private static let latest = URL(string: "https://api.github.com/repos/JulioFerrero/magnetite/releases/latest")!
    private static var nextCheck = Date.distantPast
    public static func check(_ found: @escaping (Update) -> Void) {
        guard app.pathExtension == "app", Date() > nextCheck else { return }
        nextCheck = Date() + 86_400
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        session.dataTask(with: latest) { data, _, _ in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let update = data.flatMap({ try? decoder.decode(Update.self, from: $0) }),
                  update.tagName.dropFirst().compare(current, options: .numeric) == .orderedDescending else { return }
            DispatchQueue.main.async { found(update) }
        }.resume()
    }
    public static func install(_ update: Update, done: @escaping (Bool) -> Void) {
        guard let asset = update.assets.first(where: { $0.name.hasSuffix(".zip") }) else { return done(false) }
        session.dataTask(with: asset.browserDownloadUrl) { data, _, _ in
            let installed = data.map { replace(with: $0, digest: asset.digest) } ?? false
            DispatchQueue.main.async { done(installed) }
        }.resume()
    }
    private static func replace(with zip: Data, digest: String?) -> Bool {
        let fm = FileManager.default
        guard digest == "sha256:" + SHA256.hash(data: zip).map({ String(format: "%02x", $0) }).joined(),
              let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true) else { return false }
        defer { try? fm.removeItem(at: dir) }
        let archive = dir.appendingPathComponent("Magnetite.zip")
        guard (try? zip.write(to: archive)) != nil, let unzip = spawn("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path]) else { return false }
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0, (try? fm.replaceItemAt(app, withItemAt: dir.appendingPathComponent("Magnetite.app"))) != nil else { return false }
        return spawn("/bin/sh", ["-c", "while kill -0 $0 2>/dev/null; do sleep 0.1; done; open \"$1\"", "\(getpid())", app.path]) != nil
    }
    private static func spawn(_ tool: String, _ arguments: [String]) -> Process? {
        let process = Process()
        (process.executableURL, process.arguments) = (URL(fileURLWithPath: tool), arguments)
        return (try? process.run()) == nil ? nil : process
    }
}
