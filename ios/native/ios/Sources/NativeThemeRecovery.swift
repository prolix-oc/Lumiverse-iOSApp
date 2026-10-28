import Foundation

/// Use the frontend's pre-render recovery path even when themed page controls are inaccessible.
enum NativeThemeRecovery {
    static func url(for current: URL?, enabled: Bool) -> URL? {
        guard NativeServerOrigin.canonical(current) != nil, let current = current,
              var components = URLComponents(url: current, resolvingAgainstBaseURL: false) else { return nil }
        // Preserve encoding on unrelated values: decoding/re-encoding a %2B
        // as a literal + would make URLSearchParams read it as a space.
        var items = zip(components.queryItems ?? [], components.percentEncodedQueryItems ?? [])
            .filter { $0.0.name != "safe-theme" }.map { $0.1 }
        if enabled { items.append(URLQueryItem(name: "safe-theme", value: "1")) }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        return components.url
    }
}
