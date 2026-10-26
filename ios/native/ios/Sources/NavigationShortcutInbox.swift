import Foundation

/// Compiled in both the app target (App Intents metadata) and the Swift plugin.
/// UserDefaults holds only a short-lived navigation action, never chat content.
enum NavigationShortcutInbox {
    enum Action: String, Codable { case resumeChat = "resume-chat", favorites }
    struct Request: Codable {
        let id: UUID
        let action: Action
        let createdAt: Date
    }
    static let changed = Notification.Name("chat.lumiverse.navigation-shortcut")
    private static let key = "lumiverse.shortcuts.pending.v1"

    @discardableResult
    static func enqueue(_ action: Action, defaults: UserDefaults = .standard, now: Date = Date()) -> Request {
        let request = Request(id: UUID(), action: action, createdAt: now)
        defaults.set(try? JSONEncoder().encode(request), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
        return request
    }

    static func pending(defaults: UserDefaults = .standard, now: Date = Date()) -> Request? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let request = try? JSONDecoder().decode(Request.self, from: data),
              (-5...600).contains(now.timeIntervalSince(request.createdAt)) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return request
    }

    @discardableResult
    static func acknowledge(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        guard let request = pending(defaults: defaults), request.id.uuidString == id else { return false }
        defaults.removeObject(forKey: key)
        return true
    }
}
