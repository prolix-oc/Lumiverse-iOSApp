import AppIntents
import Foundation

@available(iOS 16.0, *)
struct ResumeLastChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume last chat"
    static var description = IntentDescription("Open your last chat on the selected Lumiverse server after signing in.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationShortcutInbox.enqueue(.resumeChat)
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open favorites"
    static var description = IntentDescription("Show your favorite characters on the selected Lumiverse server.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationShortcutInbox.enqueue(.favorites)
        return .result()
    }
}

@available(iOS 16.0, *)
struct LumiverseAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ResumeLastChatIntent(), phrases: [
            "Resume my last chat in \(.applicationName)",
            "Open my last chat in \(.applicationName)"
        ], shortTitle: "Resume last chat", systemImageName: "bubble.left.and.bubble.right")
        AppShortcut(intent: OpenFavoritesIntent(), phrases: [
            "Open favorites in \(.applicationName)",
            "Show my favorite characters in \(.applicationName)"
        ], shortTitle: "Open favorites", systemImageName: "heart")
    }
}
