import UIKit
import WebKit

/// Exercise the native recognizer and injected guard with the same 500 ms page
/// timer as the shared frontend. DOM-only tests cannot verify this interaction.
final class ControlsGestureHost: UIViewController {
    private var controlsGesture: AppControlsGesture?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        let script = try! String(contentsOf: Bundle.main.url(forResource: "mobile-init", withExtension: "js")!)
        configuration.userContentController.addUserScript(WKUserScript(source: script,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let webview = WKWebView(frame: .zero, configuration: configuration)
        view = webview
        let gesture = AppControlsGesture { [weak self] _ in
            guard let self = self, self.presentedViewController == nil else { return }
            let controls = UIAlertController(title: "App controls", message: nil, preferredStyle: .alert)
            controls.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self.present(controls, animated: true)
        }
        controlsGesture = gesture
        webview.addGestureRecognizer(gesture)
        webview.loadHTMLString("""
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5">
        <style>
        body { font: 18px -apple-system; margin: 0; }
        header { position: sticky; top: 0; padding: 8px; background: white; z-index: 1; }
        #message { height: 230px; margin: 20px; background: #ded1ef; padding: 16px; }
        #spacer { height: 2000px; background: linear-gradient(white, #ded1ef); }
        </style></head><body>
        <header><p id="menus">Page menus: 0</p><p id="cancels">Touch cancels: 0</p>
        <p id="zoom">Page zoom: 1</p><p id="scroll">Page scroll: 0</p>
        <button id="tap">Tap target</button><p id="clicks">Page clicks: 0</p></header>
        <div id="message" role="button" tabindex="0">Message target</div><div id="spacer"></div>
        <script>
        let timer, menus = 0, cancels = 0, clicks = 0, start;
        const message = document.getElementById('message');
        message.addEventListener('touchstart', event => {
            clearTimeout(timer);
            start = event.touches[0];
            timer = setTimeout(() => message.dispatchEvent(new MouseEvent('contextmenu', {bubbles: true, cancelable: true})), 500);
        });
        message.addEventListener('touchmove', event => {
            const touch = event.touches[0];
            if (touch && start && Math.hypot(touch.clientX - start.clientX, touch.clientY - start.clientY) > 10) clearTimeout(timer);
        });
        message.addEventListener('touchend', () => clearTimeout(timer));
        message.addEventListener('touchcancel', () => {
            clearTimeout(timer);
            document.getElementById('cancels').textContent = 'Touch cancels: ' + ++cancels;
        });
        document.addEventListener('contextmenu', event => {
            event.preventDefault();
            document.getElementById('menus').textContent = 'Page menus: ' + ++menus;
        });
        document.getElementById('tap').onclick = () => document.getElementById('clicks').textContent = 'Page clicks: ' + ++clicks;
        visualViewport.addEventListener('resize', () => document.getElementById('zoom').textContent = 'Page zoom: ' + visualViewport.scale.toFixed(2));
        window.addEventListener('scroll', () => document.getElementById('scroll').textContent = 'Page scroll: ' + Math.round(scrollY));
        </script></body></html>
        """, baseURL: URL(string: "https://gesture-test.invalid"))
    }
}
