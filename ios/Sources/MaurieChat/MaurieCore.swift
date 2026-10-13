// The Maurie SDK's logic without UIKit — testable on its own (Tests/MaurieChatTests).
// Same behaviour as react-native/src/core.ts and flutter/lib/src/core.dart; keep them in step.
import Foundation

public let maurieDefaultBackend = "https://api.maurieai.com"

/// The customer signed in to your app.
public struct MaurieUser: Equatable {
    /// Your own id for the customer.
    public let userId: String
    public let name: String?
    public let email: String?
    public let phone: String?
    /// HMAC-SHA256(userId, identity secret), made on YOUR server — never put the identity secret in the app.
    public let userHash: String

    public init(userId: String, name: String? = nil, email: String? = nil, phone: String? = nil, userHash: String) {
        self.userId = userId; self.name = name; self.email = email; self.phone = phone; self.userHash = userHash
    }

    var json: [String: Any] {
        var d: [String: Any] = ["userId": userId, "userHash": userHash]
        if let name = name { d["name"] = name }
        if let email = email { d["email"] = email }
        if let phone = phone { d["phone"] = phone }
        return d
    }
}

/// invalid_key, app_not_allowed, not_pro, network, not_ready, no_setup, limit_reached, bad_user_hash, bad_user…
public struct MaurieError: Error, Equatable {
    public let code: String
}

public enum MaurieEvent: String, CaseIterable {
    case ready, open, close, error
}

public struct MaurieVerifyResult {
    public let ok: Bool
    public let sdk: Bool
    public let reason: String?
    public let chatURL: String?
}

/// What the UIKit side lends the core.
@MainActor
protocol MaurieHostHooks: AnyObject {
    /// The chat URL or visibility changed.
    func render()
    /// Run window.MaurieBridge.receive(json) in the page.
    func send(_ json: String)
    /// Open a link in the phone's browser.
    func openURL(_ url: String)
}

@MainActor
final class MaurieCore {
    typealias Fetch = (URL) async throws -> [String: Any]
    typealias Listener = (MaurieError?) -> Void

    private let fetch: Fetch
    init(fetch: @escaping Fetch) { self.fetch = fetch }

    private(set) var key = ""
    private(set) var appId = ""
    private(set) var backendURL = maurieDefaultBackend
    /// nil until setup() succeeded.
    private(set) var chatURL: String?
    /// false = the key works but the workspace is below Pro: the plain chat, without signed-in users or history.
    private(set) var sdk = false
    private(set) var visible = false

    private var pageReady = false
    private var user: MaurieUser?
    private var pending: [String] = []   // resets for a page that isn't ready yet
    private var listeners: [MaurieEvent: [UUID: Listener]] = [:]
    weak var host: MaurieHostHooks?
    private var setupTask: Task<MaurieVerifyResult, Never>?
    private var lastReason: String?

    // ── Public API ────────────────────────────────────────────────────

    @discardableResult
    func setup(key: String, appId: String?, backendURL: String?) async -> MaurieVerifyResult {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appId = (appId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var b = backendURL ?? maurieDefaultBackend
        while b.hasSuffix("/") { b.removeLast() }
        self.backendURL = b
        let task = Task { await self.verify() }
        setupTask = task
        let d = await task.value
        lastReason = d.ok ? nil : (d.reason ?? "invalid_key")
        return d
    }

    func identify(_ user: MaurieUser) {
        guard !user.userId.isEmpty, !user.userHash.isEmpty else { emit(.error, MaurieError(code: "bad_user")); return }
        self.user = user
        if pageReady { sendNow(["type": "identify", "user": user.json]) }
    }

    func reset() {
        user = nil
        let msg = Self.encode(["type": "reset"])
        if pageReady, let host = host { host.send(msg) } else { pending.append(msg) }   // the page may hold the old conversation
    }

    func show() async -> Bool {
        if chatURL == nil {
            if let t = setupTask { _ = await t.value }
            // Offline when the app started: try once more now. A wrong key isn't asked about again.
            if chatURL == nil, !key.isEmpty, lastReason == "network" {
                await setup(key: key, appId: appId, backendURL: backendURL)
            }
            if chatURL == nil {
                emit(.error, MaurieError(code: key.isEmpty ? "no_setup" : "not_ready"))
                return false
            }
        }
        if !visible {
            visible = true
            host?.render()
            emit(.open)
        }
        return true
    }

    func hide() {
        guard visible else { return }
        visible = false
        host?.render()
        emit(.close)
    }

    @discardableResult
    func on(_ event: MaurieEvent, _ fn: @escaping Listener) -> () -> Void {
        let id = UUID()
        listeners[event, default: [:]][id] = fn
        return { [weak self] in self?.listeners[event]?[id] = nil }
    }

    // ── For the UIKit side ────────────────────────────────────────────

    /// The page the WebView loads: SDK mode with the key on Pro, else the plain chat link.
    func url() -> String? {
        guard let c = chatURL else { return nil }
        guard sdk else { return c }
        var q = "sdk=1&key=\(Self.queryEscape(key))"
        if !appId.isEmpty { q += "&appId=\(Self.queryEscape(appId))" }
        return c + (c.contains("?") ? "&" : "?") + q
    }

    /// Links inside the chat's own site stay in the WebView; everything else goes to the phone's browser.
    func isChatURL(_ url: String) -> Bool {
        guard let c = chatURL, let origin = Self.origin(of: c) else { return false }
        return url.hasPrefix(origin + "/")
    }

    /// The WebView started loading a page (also a reload): wait for its `ready` again.
    func pageLoadStarted() { pageReady = false }

    /// A message from the page (the bridge).
    func handlePageMessage(_ data: String) {
        guard let raw = data.data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let type = m["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            let queued = pending
            pending.removeAll()
            queued.forEach { host?.send($0) }
            if let u = user { sendNow(["type": "identify", "user": u.json]) }
            emit(.ready)
        case "close":
            hide()
        case "openUrl":
            if let u = m["url"] as? String, u.range(of: "^(https?:|mailto:|tel:)", options: [.regularExpression, .caseInsensitive]) != nil {
                host?.openURL(u)
            }
        case "error":
            emit(.error, MaurieError(code: (m["code"] as? String) ?? "unknown"))
        default:
            break
        }
    }

    // ── Inside ────────────────────────────────────────────────────────

    private func verify() async -> MaurieVerifyResult {
        guard key.range(of: "^mpk_live_[A-Za-z0-9]{32}$", options: .regularExpression) != nil else {
            chatURL = nil
            emit(.error, MaurieError(code: "invalid_key"))
            return MaurieVerifyResult(ok: false, sdk: false, reason: "invalid_key", chatURL: nil)
        }
        var q = "key=\(Self.queryEscape(key))"
        if !appId.isEmpty { q += "&appId=\(Self.queryEscape(appId))" }
        let d: [String: Any]
        do {
            guard let url = URL(string: "\(backendURL)/api/mobile/verify?\(q)") else { throw URLError(.badURL) }
            d = try await fetch(url)
        } catch {
            emit(.error, MaurieError(code: "network"))
            return MaurieVerifyResult(ok: false, sdk: false, reason: "network", chatURL: nil)
        }
        guard d["ok"] as? Bool == true, let c = d["chatUrl"] as? String,
              c.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil else {
            chatURL = nil
            host?.render()
            let reason = (d["reason"] as? String) ?? "invalid_key"
            emit(.error, MaurieError(code: reason))
            return MaurieVerifyResult(ok: false, sdk: false, reason: reason, chatURL: nil)
        }
        sdk = d["sdk"] as? Bool == true
        chatURL = c
        host?.render()
        // Below Pro the chat still works, as the plain chat link — the app is told why the extras are off.
        if !sdk { emit(.error, MaurieError(code: (d["reason"] as? String) ?? "not_pro")) }
        return MaurieVerifyResult(ok: true, sdk: sdk, reason: d["reason"] as? String, chatURL: c)
    }

    private func sendNow(_ msg: [String: Any]) { host?.send(Self.encode(msg)) }

    private func emit(_ event: MaurieEvent, _ error: MaurieError? = nil) {
        for fn in (listeners[event] ?? [:]).values { fn(error) }
    }

    static func encode(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func queryEscape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func origin(of url: String) -> String? {
        guard let r = url.range(of: "^https?://[^/?#]+", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(url[r]).lowercased()
    }
}
