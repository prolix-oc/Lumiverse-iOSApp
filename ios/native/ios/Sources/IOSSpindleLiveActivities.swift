import ActivityKit
import Foundation
import UIKit
import WebKit

/// Foreground creation and native token delivery continue independently of WebKit.
@available(iOS 16.1, *)
@MainActor
final class IOSSpindleLiveActivities: NSObject, URLSessionTaskDelegate {
    static let shared = IOSSpindleLiveActivities()
    private struct Item: Decodable {
        let registrationId: String
        let credential: String?
        let attributes: SpindleActivityAttributes
        let state: SpindleActivityAttributes.ContentState
        let expiresAt: Double
        let revision: Int
        let ended: Bool
        let delivery: String
    }
    private struct Record: Codable {
        let credential: String
        let attributes: SpindleActivityAttributes
        var state: SpindleActivityAttributes.ContentState
        let expiresAt: Double
        let delivery: String
        var revision: Int
        var nativeId: String?
        var token: String?
        var dismissed = false
        var revokedAt: Double?
    }
    private weak var webview: WKWebView?
    private var accountId: String?
    private var origin: String?
    private var enabled = false
    private var records: [String: Record] = [:]
    private var observers: [String: Task<Void, Never>] = [:]
    private var states: [String: Task<Void, Never>] = [:]
    private var uploads: [String: Task<Void, Never>] = [:]
    private var uploadAttempts: [String: UUID] = [:]
    private let handoff = LiveActivityHandoff()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 12
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private override init() {
        super.init()
        if let data = try? NotificationSecurity.read("spindle-activities"),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) { records = saved }
    }
    @discardableResult
    private func save() -> Bool {
        do { try NotificationSecurity.save("spindle-activities", JSONEncoder().encode(records)); return true }
        catch { return false }
    }
    var available: Bool {
        enabled && Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true
            && Bundle.main.object(forInfoDictionaryKey: "LumiversePushEnabled") as? Bool == true
            && ActivityAuthorizationInfo().areActivitiesEnabled
    }
    var registrationIds: [String] {
        records.filter { $0.value.revokedAt == nil && $0.value.attributes.accountId == accountId && NativeServerOrigin.matches($0.value.attributes.serverOrigin, origin) }.map(\.key)
    }
    func attach(_ view: WKWebView) { webview = view; resume() }
    func configure(accountId: String?, enabled: Bool) async {
        self.accountId = accountId; self.enabled = enabled
        origin = NativeBridge.origin(webview?.url)
        for (id, record) in records where !enabled || !ActivityAuthorizationInfo().areActivitiesEnabled || record.attributes.accountId != accountId || !NativeServerOrigin.matches(record.attributes.serverOrigin, origin) {
            await dismiss(id)
        }
        resume()
    }
    func resume() {
        let live = Activity<SpindleActivityAttributes>.activities
        for (id, record) in records {
            if record.expiresAt < Date().timeIntervalSince1970 * 1000 || (record.revokedAt ?? .greatestFiniteMagnitude) < Date().timeIntervalSince1970 - 120 {
                records.removeValue(forKey: id); observers.removeValue(forKey: id)?.cancel(); states.removeValue(forKey: id)?.cancel()
                uploads.removeValue(forKey: id)?.cancel(); continue
            }
            if record.nativeId == nil { records.removeValue(forKey: id); continue }
            if let activity = live.first(where: { $0.id == record.nativeId }), !record.dismissed,
               activity.activityState != .ended && activity.activityState != .dismissed {
                observe(activity, id: id)
            } else if record.nativeId != nil { records[id]?.dismissed = true }
            upload(id)
        }
        for activity in live where records[activity.attributes.registrationId] == nil {
            Task { await activity.end(using: nil, dismissalPolicy: .immediate) }
        }
        save()
    }
    func synchronize(_ payload: [String: Any]) async throws {
        guard available, UIApplication.shared.applicationState == .active, NativeBridge.origin(webview?.url) == origin,
              let raw = payload["items"] as? [[String: Any]], raw.count <= 32 else { return }
        let data = try JSONSerialization.data(withJSONObject: raw)
        guard data.count <= 160000 else { throw NotificationSecurity.Failure.invalid }
        let items = try JSONDecoder().decode([Item].self, from: data)
        let incoming = Set(items.map(\.registrationId))
        for (id, record) in records where record.attributes.accountId == accountId && NativeServerOrigin.matches(record.attributes.serverOrigin, origin) && !incoming.contains(id) {
            await dismiss(id)
        }
        for item in items {
            guard item.attributes.renderKey == nil,
                  let credential = records[item.registrationId]?.credential ?? item.credential,
                  credential.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { continue }
            let attributes = item.attributes.forRendering(credential: credential)
            guard enabled, UIApplication.shared.applicationState == .active, item.attributes.accountId == accountId,
                  NativeServerOrigin.matches(item.attributes.serverOrigin, origin), UUID(uuidString: item.registrationId) != nil,
                  item.attributes.registrationId == item.registrationId, item.attributes.bundleId == IOSNotifications.shared.installation["bundleId"],
                  item.attributes.environment == IOSNotifications.shared.installation["environment"],
                  ["direct", "relay"].contains(item.delivery), item.attributes.extensionName.utf8.count <= 240,
                  item.expiresAt <= Date().timeIntervalSince1970 * 1000 + 8 * 3600000 + 60000,
                  let card = attributes.card(item.state), card.revision == item.revision else { continue }
            let id = item.registrationId
            if let record = records[id] {
                if record.dismissed { continue }
                guard attributes == record.attributes else { continue }
                if let activity = Activity<SpindleActivityAttributes>.activities.first(where: { $0.id == record.nativeId }) {
                    if item.ended {
                        records[id]?.dismissed = true; save()
                        await activity.end(using: item.state, dismissalPolicy: .after(Date().addingTimeInterval(60))); upload(id); continue
                    }
                    let currentRevision = activity.attributes.card(activity.contentState)?.revision ?? 0
                    if item.revision > currentRevision {
                        if #available(iOS 16.2, *) {
                            await activity.update(ActivityContent(state: item.state, staleDate: .now.addingTimeInterval(300)))
                        } else { await activity.update(using: item.state) }
                    }
                    records[id]?.state = item.state; records[id]?.revision = item.revision
                }
            } else if !item.ended && item.expiresAt > Date().timeIntervalSince1970 * 1000 {
                records[id] = Record(credential: credential, attributes: attributes, state: item.state,
                    expiresAt: item.expiresAt, delivery: item.delivery, revision: item.revision)
                // Save transport authority before asking ActivityKit to start.
                guard save() else { records.removeValue(forKey: id); continue }
                do {
                    let activity: Activity<SpindleActivityAttributes>
                    if #available(iOS 16.2, *) {
                        activity = try Activity.request(attributes: attributes,
                            content: ActivityContent(state: item.state, staleDate: .now.addingTimeInterval(300)), pushType: .token)
                    } else { activity = try Activity.request(attributes: attributes, contentState: item.state, pushType: .token) }
                    records[id]?.nativeId = activity.id
                    guard save() else { await activity.end(using: nil, dismissalPolicy: .immediate); records.removeValue(forKey: id); continue }
                    guard handoff.begin(id, onExpiration: { [weak self] in Task { @MainActor in await self?.abandon(id) } }) else { await dismiss(id); continue }
                    observe(activity, id: id)
                } catch { records.removeValue(forKey: id); save() }
            }
        }
        save()
    }
    private func observe(_ activity: Activity<SpindleActivityAttributes>, id: String) {
        if observers[id] == nil {
            observers[id] = Task { [weak self] in
                if let token = activity.pushToken { self?.token(token, id: id) }
                for await token in activity.pushTokenUpdates { if Task.isCancelled { break }; self?.token(token, id: id) }
            }
        }
        if states[id] == nil {
            states[id] = Task { [weak self] in
                for await state in activity.activityStateUpdates {
                    if Task.isCancelled { break }
                    if state == .dismissed || state == .ended { await self?.dismiss(id); break }
                }
            }
        }
    }
    private func token(_ token: Data, id: String) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        if records[id]?.token != value { uploads.removeValue(forKey: id)?.cancel() }
        records[id]?.token = value; save(); upload(id)
    }
    private func abandon(_ id: String) async {
        let nativeId = records[id]?.nativeId
        observers.removeValue(forKey: id)?.cancel(); states.removeValue(forKey: id)?.cancel()
        uploads.removeValue(forKey: id)?.cancel(); uploadAttempts.removeValue(forKey: id)
        handoff.end(id); records.removeValue(forKey: id); save()
        if let activity = Activity<SpindleActivityAttributes>.activities.first(where: { $0.id == nativeId }) {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
    }
    private func dismiss(_ id: String) async {
        guard let record = records[id] else { return }
        records[id]?.dismissed = true; save()
        observers.removeValue(forKey: id)?.cancel(); states.removeValue(forKey: id)?.cancel()
        handoff.end(id)
        if let activity = Activity<SpindleActivityAttributes>.activities.first(where: { $0.id == record.nativeId }), activity.activityState != .ended {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
        uploads.removeValue(forKey: id)?.cancel(); upload(id)
    }
    private func upload(_ id: String) {
        guard uploads[id] == nil, let record = records[id], record.revokedAt == nil, record.dismissed || record.token != nil else { return }
        let attempt = UUID(); uploadAttempts[id] = attempt
        uploads[id] = Task { [weak self] in
            defer { if self?.uploadAttempts[id] == attempt { self?.uploads.removeValue(forKey: id); self?.uploadAttempts.removeValue(forKey: id) } }
            var delay: UInt64 = 2
            while !Task.isCancelled, let self = self, let current = self.records[id], current.expiresAt > Date().timeIntervalSince1970 * 1000 {
                guard let url = URL(string: current.attributes.serverOrigin + "/api/spindle-activities/v1/" + id) else { break }
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = current.dismissed ? "DELETE" : "PUT"
                    request.setValue("Bearer " + current.credential, forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !current.dismissed {
                        guard let token = current.token, let nativeId = current.nativeId else { break }
                        var body = ["pushToken": token, "activityId": nativeId]
                        if current.delivery == "relay" { body["relayCredential"] = try await NotificationSecurity.activityCredential(token: token, origin: current.attributes.serverOrigin) }
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    }
                    let (bytes, response) = try await self.session.bytes(for: request)
                    var count = 0
                    for try await _ in bytes { count += 1; if count > 1024 { throw NotificationSecurity.Failure.network } }
                    guard !Task.isCancelled, let response = response as? HTTPURLResponse else { break }
                    if (200...299).contains(response.statusCode) {
                        self.handoff.end(id)
                        if current.dismissed { self.records[id]?.revokedAt = Date().timeIntervalSince1970; self.save() }
                        break
                    }
                    if response.statusCode == 401 || response.statusCode == 404 {
                        await self.dismiss(id); self.records.removeValue(forKey: id); self.save(); break
                    }
                } catch { if Task.isCancelled { break } }
                do { try await Task.sleep(nanoseconds: delay * 1000000000) } catch { break }
                delay = min(delay * 2, 60)
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
