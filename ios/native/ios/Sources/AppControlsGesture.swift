import UIKit

/// The document-start guard in mobile-init.js cancels page handlers as soon as
/// the second finger lands. UIKit keeps the stationary hold and native zoom.
final class AppControlsGesture: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
    private let onHold: (CGPoint) -> Void

    init(onHold: @escaping (CGPoint) -> Void) {
        self.onHold = onHold
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(openControls))
        name = "lumiverse.app-controls"
        numberOfTouchesRequired = 2
        minimumPressDuration = 0.65
        allowableMovement = 18
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        cancelsTouchesInView = true
        delegate = self
    }

    @objc private func openControls() {
        if state == .began { onHold(location(in: view)) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
