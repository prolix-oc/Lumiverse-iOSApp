import UIKit

@MainActor
final class NativeHaptics {
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()
    private var lastPlayed = -Double.infinity

    func play(_ feedback: String) -> Bool {
        guard ["selection", "impact", "success", "error"].contains(feedback),
              UIApplication.shared.applicationState == .active else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayed >= 0.1 else { return false }
        lastPlayed = now
        switch feedback {
        case "selection": selection.selectionChanged()
        case "impact": impact.impactOccurred()
        case "success": notification.notificationOccurred(.success)
        default: notification.notificationOccurred(.error)
        }
        return true
    }
}
