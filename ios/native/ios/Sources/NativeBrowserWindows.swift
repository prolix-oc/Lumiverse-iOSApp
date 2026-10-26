import UIKit
import WebKit

/// Real child browsing contexts keep OAuth redirects, opener messaging and
/// window.close working without replacing the selected server's page.
final class NativeBrowserWindows: NSObject, WKUIDelegate, WKNavigationDelegate {
    private weak var main: WKWebView?
    private let original: WKUIDelegate?
    private var navigation: UINavigationController?
    private var pages: [BrowserPage] = []

    init(webview: WKWebView) {
        main = webview
        original = webview.uiDelegate
        super.init()
        webview.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webview.uiDelegate = self
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }

    private static func allows(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return url.absoluteString == "about:blank"
            || (["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let main = main, NativeServerOrigin.canonical(main.url) != nil,
              webView === main || pages.contains(where: { $0.webview === webView }),
              action.targetFrame == nil, Self.allows(action.request.url), pages.count < 4,
              let presenter = main.window?.rootViewController else { return nil }
        if navigation == nil && presenter.presentedViewController != nil { return nil }

        // Use WebKit's supplied configuration to retain the opener, process pool
        // and cookie/storage session. Give the child its own script controller:
        // provider pages must not inherit Tauri or the selected server's bridge.
        configuration.userContentController = WKUserContentController()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        child.navigationDelegate = self
        let page = BrowserPage(webview: child, close: { [weak self] in self?.closeVisibleWindow() })
        pages.append(page)
        if let navigation = navigation {
            navigation.setViewControllers(pages, animated: false)
        } else {
            let controller = UINavigationController(rootViewController: page)
            controller.modalPresentationStyle = .fullScreen
            navigation = controller
            presenter.present(controller, animated: true)
        }
        // WebKit loads the requested URL after connecting the returned view to
        // window.open. Loading it ourselves would race one-use OAuth callbacks.
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        remove(webView)
    }

    @objc func closeVisibleWindow() {
        guard let child = pages.last?.webview else { return }
        // Close the DOM context before removing UIKit so popup.closed also
        // reports cancellation to the opener. The toolbar remains a fallback
        // when a provider overrides window.close or its web process has failed.
        child.evaluateJavaScript("window.close()") { [weak self, weak child] _, _ in
            if let child = child { self?.remove(child) }
        }
    }

    func closeAll() {
        guard let first = pages.first?.webview else { return }
        first.evaluateJavaScript("window.close()", completionHandler: nil)
        remove(first)
    }

    private func remove(_ child: WKWebView) {
        guard let index = pages.firstIndex(where: { $0.webview === child }) else { return }
        let removed = Array(pages[index...])
        pages.removeSubrange(index...)
        for page in removed.reversed() {
            if page.webview !== child { page.webview.evaluateJavaScript("window.close()", completionHandler: nil) }
            page.webview.stopLoading()
            page.webview.uiDelegate = nil
            page.webview.navigationDelegate = nil
            page.webview.removeFromSuperview()
        }
        if pages.isEmpty {
            navigation?.dismiss(animated: false)
            navigation = nil
        } else {
            navigation?.setViewControllers(pages, animated: false)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.allows(action.request.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let page = pages.first(where: { $0.webview === webView }), let url = webView.url,
              let host = url.host else { return }
        // Show the destination without exposing callback codes or state.
        var address = URLComponents()
        address.scheme = url.scheme
        address.host = host
        address.port = url.port
        page.title = address.string ?? "Authorization"
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard webView === main else { decisionHandler(.deny); return }
        if original?.webView?(webView, requestMediaCapturePermissionFor: origin,
            initiatedByFrame: frame, type: type, decisionHandler: decisionHandler) == nil {
            decisionHandler(.deny)
        }
    }
}

private final class BrowserPage: UIViewController {
    let webview: WKWebView
    private let close: () -> Void

    init(webview: WKWebView, close: @escaping () -> Void) {
        self.webview = webview
        self.close = close
        super.init(nibName: nil, bundle: nil)
        title = "Authorization"
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
            target: self, action: #selector(closeWindow))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Close authorization window"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground
        webview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webview)
        NSLayoutConstraint.activate([
            webview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func closeWindow() { close() }
}
