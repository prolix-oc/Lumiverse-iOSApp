import Foundation

@main
struct MediaCacheRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-cache-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = URL(string: "https://media.example")!
        let base = "https://media.example:443/api/v1/images/avatar"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jwZkAAAAASUVORK5CYII=")!
        var clock = Date()
        func cookie(_ value: String = "secret", domain: String = "media.example", path: String = "/", httpOnly: Bool = true, expires: Date? = nil) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: "__Secure-better-auth.session_token", .value: value,
                .domain: domain, .path: path, .secure: "TRUE"]
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expires = expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)!
        }
        func scope(_ account: String = "alice", _ cookies: [HTTPCookie]? = nil) -> String? {
            NativeMediaCacheStore.scope(origin: origin, account: account, cookies: cookies ?? [cookie()], now: clock)
        }
        let alice = scope()!, bob = scope("bob")!
        precondition(alice != bob && alice != scope("alice", [cookie("rotated")]))
        precondition(alice == NativeMediaCacheStore.scope(origin: URL(string: "https://media.example:443")!, account: "alice", cookies: [cookie()], now: clock))
        precondition(scope("alice", [cookie(domain: "other.example")]) == nil)
        precondition(scope("alice", [cookie(path: "/api/v1/imag")]) == nil)
        precondition(scope("alice", [cookie(httpOnly: false)]) == nil)
        precondition(scope("alice", [cookie(expires: clock.addingTimeInterval(-1))]) == nil)
        precondition(NativeMediaCacheStore.scope(origin: URL(string: "http://media.example")!, account: "alice", cookies: [cookie()]) == nil)
        precondition(NativeMediaCacheStore.imageKey("/api/v1/images/avatar?size=lg", origin: origin) == base + "?size=lg")
        for bad in ["https://other.example/api/v1/images/avatar", "/api/v1/characters/a/avatar?size=lg", "/api/v1/images/avatar?size=lg&size=sm", "/api/v1/images/avatar?codec=h264", "/api/v1/images/avatar#x"] {
            precondition(NativeMediaCacheStore.imageKey(bad, origin: origin) == nil, bad)
        }
        let store = NativeMediaCacheStore(root: root, now: { clock })
        for tier in ["", "?size=sm", "?size=lg"] { precondition(store.write(scope: alice, key: base + tier, bytes: png, contentType: "image/png")) }
        let reopened = NativeMediaCacheStore(root: root, now: { clock })
        precondition(reopened.read(scope: alice, key: base + "?size=lg")?.bytes == png)
        precondition(reopened.read(scope: bob, key: base) == nil)
        precondition(!store.write(scope: alice, key: base, bytes: Data("<svg/>".utf8), contentType: "image/svg+xml"))
        precondition(!store.write(scope: alice, key: base, bytes: Data(repeating: 0, count: NativeMediaCacheStore.maxImageBytes + 1), contentType: "image/png"))
        reopened.invalidate(scope: alice, key: base + "?size=sm")
        for tier in ["", "?size=sm", "?size=lg"] { precondition(reopened.read(scope: alice, key: base + tier) == nil) }
        precondition(reopened.write(scope: alice, key: base, bytes: png, contentType: "image/png"))
        clock.addTimeInterval(NativeMediaCacheStore.maxAge + 1)
        precondition(reopened.read(scope: alice, key: base) == nil)
        let limited = NativeMediaCacheStore(root: root, maxBytes: 1024, maxEntries: 2, now: { clock })
        precondition(limited.write(scope: alice, key: base, bytes: png, contentType: "image/png"))
        clock.addTimeInterval(1)
        precondition(limited.write(scope: bob, key: base, bytes: png, contentType: "image/png"))
        clock.addTimeInterval(1)
        precondition(limited.read(scope: alice, key: base) != nil)
        clock.addTimeInterval(1)
        precondition(limited.write(scope: alice, key: base + "?size=lg", bytes: png, contentType: "image/png"))
        precondition(limited.read(scope: bob, key: base) == nil)
        limited.clear(scope: alice)
        precondition(limited.read(scope: alice, key: base) == nil)
        precondition(limited.write(scope: alice, key: base, bytes: png, contentType: "image/png"))
        let file = root.appendingPathComponent(alice).appendingPathComponent(NativeMediaCacheStore.digest(base) + ".cache")
        try Data("corrupt".utf8).write(to: file)
        precondition(limited.read(scope: alice, key: base) == nil)
        let tiny = NativeMediaCacheStore(root: root, maxBytes: 1)
        precondition(!tiny.write(scope: alice, key: base, bytes: png, contentType: "image/png"))
    }
}
