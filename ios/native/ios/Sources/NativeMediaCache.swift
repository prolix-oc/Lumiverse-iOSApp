import Foundation
import WebKit

/// Disk I/O never runs on the UI thread; networking stays in the authenticated WebView.
final class NativeMediaCache {
    static let shared = NativeMediaCache()
    private let queue = DispatchQueue(label: "chat.lumiverse.media-cache", qos: .userInitiated)
    private let store: NativeMediaCacheStore
    private var pending = 0

    init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LumiverseMedia-v1", isDirectory: true)
        store = NativeMediaCacheStore(root: root)
    }

    func handle(_ action: String, payload: [String: Any], webview: WKWebView, reply: @escaping (Any?, String?) -> Void) {
        guard pending < 12, let origin = webview.url, let canonical = NativeServerOrigin.canonical(origin),
              let account = payload["accountId"] as? String, !account.isEmpty, account.utf8.count <= 256 else { reply(nil, "Media cache unavailable."); return }
        let key = (payload["url"] as? String).flatMap { NativeMediaCacheStore.imageKey($0, origin: origin) }
        guard action == "mediaCache.clear" || key != nil else { reply(nil, "Unsupported media URL."); return }
        // Reject oversized messages before queuing work or converting base64.
        if action == "mediaCache.write", (payload["data"] as? String)?.utf8.count ?? Int.max > NativeMediaCacheStore.maxImageBytes * 4 / 3 + 4 {
            reply(nil, "Image exceeds cache limit."); return
        }
        pending += 1
        webview.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self, weak webview] cookies in
            guard let self = self else { reply(nil, "Media cache unavailable."); return }
            guard let webview = webview, NativeServerOrigin.canonical(webview.url) == canonical,
                  let scope = NativeMediaCacheStore.scope(origin: origin, account: account, cookies: cookies) else {
                self.pending -= 1; reply(nil, "No authenticated media cache session."); return
            }
            if (action == "mediaCache.write" || payload["scope"] != nil), payload["scope"] as? String != scope {
                self.pending -= 1; reply(nil, "Media cache session changed."); return
            }
            self.queue.async { [weak webview] in
                let result: [String: Any]
                switch action {
                case "mediaCache.read":
                    if let entry = self.store.read(scope: scope, key: key!) {
                        result = ["scope": scope, "data": entry.bytes.base64EncodedString(), "contentType": entry.contentType]
                    } else { result = ["scope": scope] }
                case "mediaCache.write":
                    let data = (payload["data"] as? String).flatMap { Data(base64Encoded: $0) }
                    result = ["stored": data.map { self.store.write(scope: scope, key: key!, bytes: $0, contentType: payload["contentType"] as? String ?? "") } ?? false]
                case "mediaCache.remove": self.store.invalidate(scope: scope, key: key!); result = ["removed": true]
                case "mediaCache.clear": self.store.clear(scope: scope); result = ["cleared": true]
                default: result = [:]
                }
                DispatchQueue.main.async { [weak webview] in
                    guard let webview = webview, NativeServerOrigin.canonical(webview.url) == canonical else {
                        self.pending -= 1; reply(nil, "Media cache server changed."); return
                    }
                    // A logout/cookie rotation during disk I/O must not reveal old bytes.
                    webview.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        self.pending -= 1
                        guard NativeServerOrigin.canonical(webview.url) == canonical,
                              NativeMediaCacheStore.scope(origin: origin, account: account, cookies: cookies) == scope else { reply(nil, "Media cache session changed."); return }
                        reply(result, nil)
                    }
                }
            }
        }
    }
}
