import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct SpindleActivityAttributes: ActivityAttributes, Codable, Hashable {
    struct Envelope: Codable, Hashable {
        let version: Int
        let keyId: String
        let nonce: String
        let ciphertext: String
        let tag: String
        var dictionary: [String: Any] { ["version": version, "keyId": keyId, "nonce": nonce, "ciphertext": ciphertext, "tag": tag] }
    }
    struct ContentState: Codable, Hashable {
        let version: Int
        let encrypted: Envelope
    }
    let id: String
    let registrationId: String
    let accountId: String
    let serverOrigin: String
    let extensionName: String
    let bundleId: String
    let environment: String
    var renderKey: String? = nil

    /// Added by the host, never sent to the backend or APNs relay. ActivityKit
    /// persists this scoped key with the activity because rendering cannot use Keychain.
    func forRendering(credential: String) -> Self {
        var attributes = self
        attributes.renderKey = NotificationSecurity.spindleActivityKey(credential: credential, registrationId: registrationId).base64EncodedString()
        return attributes
    }

    func card(_ state: ContentState) -> SpindleActivityCard? {
        guard state.version == 1,
              let encoded = renderKey, let key = Data(base64Encoded: encoded), key.count == 32,
              let clear = try? NotificationSecurity.openEnvelope(state.encrypted.dictionary, key: key, bundleId: bundleId, environment: environment),
              clear["id"] as? String == id, clear["serverOrigin"] as? String == serverOrigin,
              let data = try? JSONSerialization.data(withJSONObject: clear),
              let card = try? JSONDecoder().decode(SpindleActivityCard.self, from: data),
              ["status", "progress", "image"].contains(card.layout), card.title.utf8.count <= 320, card.body.utf8.count <= 640,
              card.symbol.range(of: "^[a-z0-9.]{1,64}$", options: .regularExpression) != nil,
              card.progress.map({ $0.isFinite && $0 >= 0 && $0 <= 1 }) ?? true,
              card.imageBase64.map({ $0.utf8.count <= 936 }) ?? true else { return nil }
        return card
    }
}

struct SpindleActivityCard: Codable {
    let id: String
    let revision: Int
    let layout: String
    let title: String
    let body: String
    let symbol: String
    let progress: Double?
    let imageBase64: String?
    let terminal: Bool
}
