import CryptoKit
import Foundation

/// Compressed raster bytes only. All methods are called on the bridge's serial queue.
final class NativeMediaCacheStore {
    static let maxImageBytes = 2 * 1024 * 1024
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private let root: URL
    private let maxBytes: Int
    private let maxEntries: Int
    private let now: () -> Date
    private var files: [URL: (bytes: Int, accessed: Date)] = [:]
    private var indexed = false

    struct Entry: Codable {
        let contentType: String
        let expires: Date
        let bytes: Data
    }

    init(root: URL, maxBytes: Int = 128 * 1024 * 1024, maxEntries: Int = 512, now: @escaping () -> Date = Date.init) {
        self.root = root; self.maxBytes = maxBytes; self.maxEntries = maxEntries; self.now = now
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Exclude resolvers, remote proxies, videos, arbitrary query parameters and other origins.
    static func imageKey(_ raw: String, origin: URL) -> String? {
        guard raw.count <= 2048, let url = URL(string: raw, relativeTo: origin)?.absoluteURL,
              url.user == nil, url.password == nil, url.fragment == nil,
              NativeServerOrigin.canonical(url) == NativeServerOrigin.canonical(origin),
              let canonical = NativeServerOrigin.canonical(origin),
              url.path.range(of: "^/api/v1/images/[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = parts.queryItems ?? []
        guard query.isEmpty || (query.count == 1 && query[0].name == "size" && ["sm", "lg"].contains(query[0].value ?? "")) else { return nil }
        return canonical + url.path + (query.isEmpty ? "" : "?size=\(query[0].value!)")
    }

    /// Bind bytes to HttpOnly session cookies as well as server and account. A caller cannot
    /// retrieve another account's cache merely by supplying its public account ID.
    static func scope(origin: URL, account: String, cookies: [HTTPCookie], now: Date = Date()) -> String? {
        guard !account.isEmpty, account.utf8.count <= 256, let canonical = NativeServerOrigin.canonical(origin), let host = origin.host?.lowercased() else { return nil }
        let session = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let path = "/api/v1/images/"
            let pathMatches = path == cookie.path || (path.hasPrefix(cookie.path)
                && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return ["better-auth.session_token", "__Secure-better-auth.session_token", "__Host-better-auth.session_token"].contains(cookie.name)
                && cookie.isHTTPOnly && !cookie.value.isEmpty
                && (cookie.expiresDate == nil || cookie.expiresDate! > now)
                && (host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain)))
                && (!cookie.isSecure || origin.scheme == "https")
                && pathMatches
        }.map { [$0.name, $0.domain, $0.path, $0.value] }.sorted { $0.joined() < $1.joined() }
        guard !session.isEmpty, let encoded = try? JSONSerialization.data(withJSONObject: [canonical, account, session]) else { return nil }
        return digest(encoded.base64EncodedString())
    }

    private func file(_ scope: String, _ key: String) -> URL {
        root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(Self.digest(key) + ".cache").resolvingSymlinksInPath()
    }

    private func index() {
        guard !indexed else { return }; indexed = true
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) {
            for case let url as URL in enumerator where url.pathExtension == "cache" {
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true {
                    // Normalize both enumerated and requested URLs: Foundation
                    // can enumerate /var files using their /private/var alias.
                    files[url.resolvingSymlinksInPath()] = (values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
                }
            }
        }
        trim()
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        files.removeValue(forKey: url)
        let directory = url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true { try? FileManager.default.removeItem(at: directory) }
    }

    private func trim() {
        var bytes = files.values.reduce(0) { $0 + $1.bytes }
        for (url, info) in files.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            if bytes <= maxBytes && files.count <= maxEntries { break }
            remove(url); bytes -= info.bytes
        }
    }

    func read(scope: String, key: String) -> Entry? {
        index()
        let url = file(scope, key)
        guard let info = files[url] else { return nil }
        guard info.bytes <= Self.maxImageBytes * 4 / 3 + 1024,
              let bytes = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: bytes),
              entry.expires > now(), Self.validRaster(entry.bytes, type: entry.contentType) else { remove(url); return nil }
        files[url] = (info.bytes, now())
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return entry
    }

    @discardableResult func write(scope: String, key: String, bytes: Data, contentType: String) -> Bool {
        index()
        guard Self.validRaster(bytes, type: contentType),
              let encoded = try? JSONEncoder().encode(Entry(contentType: contentType, expires: now().addingTimeInterval(Self.maxAge), bytes: bytes)), encoded.count <= maxBytes else { return false }
        let url = file(scope, key)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            #endif
            files[url] = (encoded.count, now()); trim()
            return files[url] != nil
        } catch { remove(url); return false }
    }

    func clear(scope: String) {
        index()
        for url in Array(files.keys) where url.deletingLastPathComponent().lastPathComponent == scope { remove(url) }
    }

    func invalidate(scope: String, key: String) {
        index()
        let base = key.components(separatedBy: "?")[0]
        for variant in [base, base + "?size=sm", base + "?size=lg"] { remove(file(scope, variant)) }
    }

    static func validRaster(_ data: Data, type: String) -> Bool {
        guard !data.isEmpty, data.count <= maxImageBytes else { return false }
        let b = [UInt8](data.prefix(32))
        switch type {
        case "image/png": return b.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        case "image/jpeg": return b.starts(with: [255, 216, 255])
        case "image/gif": return b.starts(with: Array("GIF87a".utf8)) || b.starts(with: Array("GIF89a".utf8))
        case "image/webp": return b.count >= 12 && String(bytes: b[0..<4], encoding: .ascii) == "RIFF" && String(bytes: b[8..<12], encoding: .ascii) == "WEBP"
        case "image/avif": return b.count >= 16 && String(bytes: b[4..<8], encoding: .ascii) == "ftyp" && ["avif", "avis"].contains(String(bytes: b[8..<12], encoding: .ascii) ?? "")
        default: return false
        }
    }
}
