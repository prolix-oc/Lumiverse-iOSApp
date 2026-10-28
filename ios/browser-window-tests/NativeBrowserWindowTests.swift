import XCTest
import UIKit
import WebKit
import Network

@MainActor
final class NativeBrowserWindowTests: XCTestCase {
    private var window: UIWindow!
    private var root: UIViewController!
    private var main: WKWebView!
    private var windows: NativeBrowserWindows!
    private var server: BrowserFixture!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try BrowserFixture()
        try await server.start()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(source: "window.mainOnlyBridge = true; window.__LUMIVERSE_IOS_NATIVE__ = {}; window.__TAURI_INTERNALS__ = {}",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        main = WKWebView(frame: root.view.bounds, configuration: configuration)
        root.view.addSubview(main)
        main.load(URLRequest(url: server.url("/app")))
        try await wait { self.main.url?.path == "/app" && !self.main.isLoading }
        _ = try await js("window.results = []; document.cookie = 'fixture=1; path=/'; window.addEventListener('message', e => results.push(e.data))")
    }

    override func tearDown() async throws {
        windows?.closeAll()
        root.dismiss(animated: false)
        window.isHidden = true
        main.removeFromSuperview()
        windows = nil
        main = nil
        root = nil
        window = nil
        server.stop()
        server = nil
    }

    func testReservedWindowRedirectsToCallbackOnceAndClosesWithoutInheritingBridge() async throws {
        // Reproduce the shipping wrapper's missing create-WebView handler.
        try await assertJS("!!window.open('about:blank')", false)
        XCTAssertNil(root.presentedViewController)
        windows = NativeBrowserWindows(webview: main)
        try await assertJS("window.popup = window.open('about:blank'); !!popup", true)
        try await wait { self.root.presentedViewController is UINavigationController }
        _ = try await js("setTimeout(() => popup.location.href = '\(server.providerURL("/authorize?flow=pkce").absoluteString)', 50)")
        try await waitForResult("pkce")
        try await wait { self.root.presentedViewController == nil }
        try await assertJS("popup.closed", true)
        try await assertJS("results[0].bridge", false)
        try await assertJS("results[0].native", "undefined")
        try await assertJS("results[0].ipc", "undefined")
        try await assertJS("results[0].cookie", true)
        XCTAssertEqual(server.hits("/authorize?flow=pkce"), 1)
        XCTAssertEqual(server.hits("/callback?flow=pkce"), 1)
        XCTAssertEqual(main.url?.path, "/app")
    }

    func testExtensionDirectAndNestedWindowsPreserveTheirOpeners() async throws {
        windows = NativeBrowserWindows(webview: main)
        _ = try await js("window.popup = window.open('\(server.providerURL("/nested").absoluteString)'); true")
        try await waitForResult("nested")
        try await wait { self.root.presentedViewController == nil }
        try await assertJS("popup.closed", true)
        XCTAssertEqual(server.hits("/authorize?flow=nested"), 1)
        XCTAssertEqual(server.hits("/callback?flow=nested"), 1)
    }

    func testCallbackStorageSurvivesASeveredOpener() async throws {
        windows = NativeBrowserWindows(webview: main)
        _ = try await js("window.popup = window.open('about:blank'); popup.opener = null; popup.location = '\(server.providerURL("/authorize?flow=storage").absoluteString)'")
        try await waitJS("localStorage.getItem('completed:storage') === 'code-storage'")
        try await wait { self.root.presentedViewController == nil }
        try await assertJS("popup.closed", true)
        try await assertJS("results.length", 0)
    }

    func testNativeCloseButtonCancelsBlankAndLoadedWindows() async throws {
        windows = NativeBrowserWindows(webview: main)
        for target in ["about:blank", server.providerURL("/manual").absoluteString] {
            _ = try await js("window.popup = window.open('\(target)'); true")
            try await wait { self.root.presentedViewController is UINavigationController }
            try await Task.sleep(nanoseconds: 400_000_000)
            let navigation = try XCTUnwrap(root.presentedViewController as? UINavigationController)
            let button = try XCTUnwrap(navigation.topViewController?.navigationItem.rightBarButtonItem)
            XCTAssertEqual(button.accessibilityLabel, "Close authorization window")
            _ = (button.target as? NSObject)?.perform(try XCTUnwrap(button.action))
            try await wait { self.root.presentedViewController == nil }
            try await assertJS("popup.closed", true)
        }
        XCTAssertEqual(main.url?.path, "/app")
    }

    func testMainDelegateStillWorksAndPopupsBlockNativeSchemesAndExcessWindows() async throws {
        let original = ConfirmDelegate()
        main.uiDelegate = original
        windows = NativeBrowserWindows(webview: main)
        try await assertJS("confirm('Keep main delegate')", true)
        XCTAssertEqual(original.calls, 1)
        try await assertJS("!!window.open('file:///private/test')", false)
        try await assertJS("!!window.open('tauri://localhost/index.html')", false)
        try await assertJS("window.popups = Array.from({length: 5}, () => window.open('about:blank')); popups.filter(Boolean).length", 4)
        try await Task.sleep(nanoseconds: 400_000_000)
        let navigation = try XCTUnwrap(root.presentedViewController as? UINavigationController)
        XCTAssertEqual(navigation.viewControllers.count, 4)
        let child = try XCTUnwrap(navigation.topViewController?.view.subviews.first as? WKWebView)
        child.load(URLRequest(url: URL(string: "tauri://localhost/index.html")!))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotEqual(child.url?.scheme, "tauri")
        windows.closeAll()
        try await wait { self.root.presentedViewController == nil }
        try await assertJS("confirm('Still attached')", true)
        XCTAssertEqual(original.calls, 2)
    }

    private func assertJS<Value: Equatable>(_ script: String, _ expected: Value,
        file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await js(script) as? Value
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func js(_ script: String) async throws -> Any? { try await main.evaluateJavaScript(script) }

    private func wait(_ predicate: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertTrue(predicate(), "Timed out waiting for native browser state")
    }

    private func waitJS(_ script: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if try await js(script) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for browser condition: \(script)")
    }

    private func waitForResult(_ flow: String) async throws {
        try await waitJS("results.some(r => r.flow === '\(flow)')")
    }
}

private final class ConfirmDelegate: NSObject, WKUIDelegate {
    var calls = 0
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        calls += 1
        completionHandler(true)
    }
}

/// Two browser origins on one local HTTP listener exercise real network
/// redirects and WebKit's cookie/storage and opener behavior.
private final class BrowserFixture {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "lumiverse.browser-fixture")
    private let lock = NSLock()
    private var requests: [String: Int] = [:]
    private var port: UInt16 = 0

    init() throws { listener = try NWListener(using: .tcp, on: .any) }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: self.port = self.listener.port!.rawValue; continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                connection.start(queue: self.queue)
                self.receive(connection, bytes: Data())
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    func providerURL(_ path: String) -> URL { URL(string: "http://localhost:\(port)\(path)")! }
    func hits(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return requests[path] ?? 0 }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            let bytes = bytes + (data ?? Data())
            guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                if !complete && error == nil { self.receive(connection, bytes: bytes) }
                else { connection.cancel() }
                return
            }
            let path = text.components(separatedBy: " ").dropFirst().first ?? "/"
            self.lock.lock(); self.requests[path, default: 0] += 1; self.lock.unlock()
            let flow = URLComponents(string: "http://fixture\(path)")?.queryItems?.first(where: { $0.name == "flow" })?.value ?? ""
            var status = "200 OK", headers = "", body = "<h1>Browser fixture</h1>"
            if path.hasPrefix("/authorize") {
                status = "302 Found"
                headers = "Location: \(self.url("/callback?flow=\(flow)").absoluteString)\r\n"
            } else if path.hasPrefix("/callback") {
                body = """
                <script>
                const result = {flow:'\(flow)', code:'code-\(flow)', bridge:!!window.mainOnlyBridge,
                  native:typeof window.__LUMIVERSE_IOS_NATIVE__, ipc:typeof window.__TAURI_INTERNALS__, cookie:document.cookie.includes('fixture=1')};
                localStorage.setItem('completed:\(flow)', result.code);
                window.opener?.postMessage(result, '*');
                setTimeout(() => window.close(), 100);
                </script>
                """
            } else if path == "/nested" {
                body = """
                <script>
                window.addEventListener('message', event => { window.opener.postMessage(event.data, '*'); setTimeout(() => window.close(), 100); });
                window.open('\(self.providerURL("/authorize?flow=nested").absoluteString)');
                </script>
                """
            }
            let payload = Data(body.utf8)
            let response = Data("HTTP/1.1 \(status)\r\n\(headers)Content-Type: text/html\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8) + payload
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
