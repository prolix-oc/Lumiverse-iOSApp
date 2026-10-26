import Foundation

@main struct ShortcutRegression {
    static func main() {
        let suite = "lumiverse.shortcut-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let first = NavigationShortcutInbox.enqueue(.resumeChat, defaults: defaults, now: now)
        precondition(NavigationShortcutInbox.pending(defaults: defaults)?.id == first.id)
        let second = NavigationShortcutInbox.enqueue(.favorites, defaults: defaults, now: now)
        precondition(!NavigationShortcutInbox.acknowledge(first.id.uuidString, defaults: defaults))
        precondition(NavigationShortcutInbox.pending(defaults: defaults)?.id == second.id)
        precondition(NavigationShortcutInbox.acknowledge(second.id.uuidString, defaults: defaults))
        precondition(NavigationShortcutInbox.pending(defaults: defaults) == nil)
        NavigationShortcutInbox.enqueue(.resumeChat, defaults: defaults, now: now.addingTimeInterval(-601))
        precondition(NavigationShortcutInbox.pending(defaults: defaults, now: now) == nil)
        NavigationShortcutInbox.enqueue(.favorites, defaults: defaults, now: now.addingTimeInterval(60))
        precondition(NavigationShortcutInbox.pending(defaults: defaults, now: now) == nil)
    }
}
