import Foundation

@main struct SpindleEncryptionCheck {
    static func main() throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let credential = input["credential"] as! String, registrationId = input["registrationId"] as! String
        let key = NotificationSecurity.spindleActivityKey(credential: credential, registrationId: registrationId)
        precondition(key.base64EncodedString() == input["key"] as! String)
        precondition(NotificationSecurity.spindleActivityKey(credential: credential, registrationId: "other-registration") != key)
        let envelope = input["envelope"] as! [String: Any]
        let clear = try NotificationSecurity.openEnvelope(envelope, key: key, bundleId: "chat.lumiverse.ios", environment: "development")
        precondition(clear["title"] as? String == "Private activity 🦊")
        for invalidKey in [NotificationSecurity.spindleActivityKey(credential: "wrong", registrationId: registrationId),
                           NotificationSecurity.spindleActivityKey(credential: credential, registrationId: "other-registration")] {
            do { _ = try NotificationSecurity.openEnvelope(envelope, key: invalidKey, bundleId: "chat.lumiverse.ios", environment: "development"); fatalError("Accepted another registration's key") }
            catch { }
        }
        print("PASS: backend encryption decrypts in CryptoKit with a registration-scoped key and no Keychain lookup.")
    }
}
