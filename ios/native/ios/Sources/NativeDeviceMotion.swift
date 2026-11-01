import CoreMotion
import UIKit
import WebKit

/// Fused gyro/accelerometer attitude for the selected page's visible cards.
/// Raw gyro integration would drift; an arbitrary vertical frame needs no compass.
final class NativeDeviceMotion {
    private let manager = CMMotionManager()
    private weak var webview: WKWebView?
    private var id: String?
    private var origin: String?
    private var pendingDelivery = false
    private var generation = 0
    private var reset = true
    private var accessibilityObserver: NSObjectProtocol?

    init(webview: WKWebView) {
        self.webview = webview
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateActivity() }
    }

    deinit {
        manager.stopDeviceMotionUpdates()
        if let observer = accessibilityObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func start(id: String) -> [String: Any] {
        stop()
        guard !id.isEmpty, id.count <= 100, manager.isDeviceMotionAvailable,
              let origin = NativeServerOrigin.canonical(webview?.url) else { return ["available": false] }
        self.id = id
        self.origin = origin
        updateActivity()
        return ["available": true]
    }

    func stop(id: String? = nil) {
        if let id = id, id != self.id { return }
        self.id = nil
        origin = nil
        pause()
    }

    private func pause() {
        generation += 1
        pendingDelivery = false
        manager.stopDeviceMotionUpdates()
    }

    func updateActivity(isActive: Bool = true) {
        guard isActive, id != nil, let webview = webview,
              NativeServerOrigin.canonical(webview.url) == origin,
              webview.window?.windowScene?.activationState == .foregroundActive,
              !UIAccessibility.isReduceMotionEnabled else {
            pause()
            return
        }
        guard !manager.isDeviceMotionActive else { return }
        generation += 1
        let currentGeneration = generation
        let currentID = id
        reset = true
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, self.generation == currentGeneration,
                  let id = self.id, id == currentID, let webview = self.webview,
                  NativeServerOrigin.canonical(webview.url) == self.origin else { return }
            if error != nil {
                self.stop()
                webview.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('lumiverse:ios-device-motion', {detail: detail}))",
                    arguments: ["detail": ["id": id, "available": false]], in: nil, in: .page, completionHandler: nil)
                return
            }
            guard let motion = motion, !self.pendingDelivery,
                  webview.window?.windowScene?.activationState == .foregroundActive,
                  !UIAccessibility.isReduceMotionEnabled else { return }
            let q = motion.attitude.quaternion
            let detail: [String: Any] = ["id": id, "reset": self.reset,
                "quaternion": ["x": q.x, "y": q.y, "z": q.z, "w": q.w]]
            self.reset = false
            // Bound bridge work to one delivery; skip samples if WebKit is busy.
            self.pendingDelivery = true
            webview.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('lumiverse:ios-device-motion', {detail: detail}))",
                arguments: ["detail": detail], in: nil, in: .page) { [weak self] _ in
                    guard let self = self, self.generation == currentGeneration else { return }
                    self.pendingDelivery = false
                }
        }
    }
}
