import Foundation

@main
struct ThemeRecoveryRegression {
    static func main() {
        let current = URL(string: "https://lumiverse.example:8443/chat/chat%201?panel=details&filter=a%2Bb&filter=c#message-2")!
        let recovered = NativeThemeRecovery.url(for: current, enabled: true)!
        let components = URLComponents(url: recovered, resolvingAgainstBaseURL: false)!
        precondition(components.scheme == "https" && components.host == "lumiverse.example" && components.port == 8443)
        precondition(components.percentEncodedPath == "/chat/chat%201" && components.fragment == "message-2")
        precondition(components.queryItems == [URLQueryItem(name: "panel", value: "details"),
            URLQueryItem(name: "filter", value: "a+b"), URLQueryItem(name: "filter", value: "c"),
            URLQueryItem(name: "safe-theme", value: "1")])
        precondition(NativeThemeRecovery.url(for: recovered, enabled: true) == recovered, "Repeated recovery must not add duplicate flags")
        precondition(NativeThemeRecovery.url(for: recovered, enabled: false) == current)

        for query in ["safe-theme", "safe-theme=0", "safe-theme=false&safe-theme=1", "safe-theme=1&safe-theme=off", "%73afe-theme=false"] {
            let original = URL(string: "http://localhost:8080/?\(query)")!
            precondition(NativeThemeRecovery.url(for: original, enabled: true)?.absoluteString == "http://localhost:8080/?safe-theme=1")
            precondition(NativeThemeRecovery.url(for: original, enabled: false)?.absoluteString == "http://localhost:8080/")
        }
        let routed = URL(string: "https://lumiverse.example/chat/another-chat")!
        precondition(NativeThemeRecovery.url(for: routed, enabled: false) == routed, "Restoration must reload even if routing already removed the query")
        for address in ["tauri://localhost/index.html", "http://tauri.localhost/index.html", "file:///tmp/page.html", "about:blank"] {
            for enabled in [true, false] {
                precondition(NativeThemeRecovery.url(for: URL(string: address), enabled: enabled) == nil)
            }
        }
        precondition(NativeThemeRecovery.url(for: nil, enabled: true) == nil)
    }
}
