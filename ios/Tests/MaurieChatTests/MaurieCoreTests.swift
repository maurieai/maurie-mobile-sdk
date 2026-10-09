// swift test / Xcode ▸ Test — the SDK's logic without UIKit. Mirrors react-native/test/core.test.mjs.
import XCTest
@testable import MaurieChat

private let key = "mpk_live_" + String(repeating: "A", count: 32)
private let chat = "https://maurieai.com/chat/agent-1"

@MainActor
private final class FakeHost: MaurieHostHooks {
    var sent: [[String: Any]] = []
    var opened: [String] = []
    var renders = 0
    func render() { renders += 1 }
    func send(_ json: String) {
        sent.append((try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:])
    }
    func openURL(_ url: String) { opened.append(url) }
}

@MainActor
final class MaurieCoreTests: XCTestCase {
    private final class Calls { var urls: [URL] = [] }
    private func core(_ body: [String: Any], calls: Calls? = nil) -> MaurieCore {
        MaurieCore(fetch: { url in calls?.urls.append(url); return body })
    }
    private func events(_ c: MaurieCore) -> () -> [String] {
        var got: [String] = []
        for e in MaurieEvent.allCases { c.on(e) { err in got.append(err.map { "\(e.rawValue):\($0.code)" } ?? e.rawValue) } }
        return { got }
    }

    func testSetupOnPro() async {
        let calls = Calls()
        let c = core(["ok": true, "sdk": true, "chatUrl": chat], calls: calls)
        let ev = events(c)
        await c.setup(key: key, appId: "com.acme.app", backendURL: "https://api.example.com/")
        XCTAssertEqual(calls.urls.first?.absoluteString, "https://api.example.com/api/mobile/verify?key=\(key)&appId=com.acme.app")
        XCTAssertEqual(c.url(), "\(chat)?sdk=1&key=\(key)&appId=com.acme.app")
        XCTAssertEqual(ev(), [])
    }

    func testBelowProFallsBackToPlainChat() async {
        let c = core(["ok": true, "sdk": false, "reason": "not_pro", "chatUrl": chat])
        let ev = events(c)
        await c.setup(key: key, appId: nil, backendURL: nil)
        XCTAssertEqual(c.url(), chat)
        let shown = await c.show()
        XCTAssertTrue(shown)
        XCTAssertEqual(ev(), ["error:not_pro", "open"])
    }

    func testMalformedKey() async {
        let calls = Calls()
        let c = core([:], calls: calls)
        let ev = events(c)
        await c.setup(key: "mk_live_secret", appId: nil, backendURL: nil)
        let shown = await c.show()
        XCTAssertFalse(shown)
        XCTAssertTrue(calls.urls.isEmpty)
        XCTAssertEqual(ev(), ["error:invalid_key", "error:not_ready"])
    }

    func testResetThenIdentifyBeforeReady() async {
        let c = core(["ok": true, "sdk": true, "chatUrl": chat])
        let h = FakeHost()
        c.host = h
        await c.setup(key: key, appId: nil, backendURL: nil)
        c.reset()
        c.identify(MaurieUser(userId: "7", userHash: "ff"))
        XCTAssertTrue(h.sent.isEmpty)
        c.handlePageMessage("{\"type\":\"ready\"}")
        XCTAssertEqual(h.sent.compactMap { $0["type"] as? String }, ["reset", "identify"])
    }

    func testReloadResendsIdentify() async {
        let c = core(["ok": true, "sdk": true, "chatUrl": chat])
        let h = FakeHost()
        c.host = h
        await c.setup(key: key, appId: nil, backendURL: nil)
        c.handlePageMessage("{\"type\":\"ready\"}")
        c.identify(MaurieUser(userId: "u1", userHash: "aa"))
        c.pageLoadStarted()
        c.handlePageMessage("{\"type\":\"ready\"}")
        XCTAssertEqual(h.sent.compactMap { $0["type"] as? String }, ["identify", "identify"])
    }

    func testCloseAndLinks() async {
        let c = core(["ok": true, "sdk": true, "chatUrl": chat])
        let h = FakeHost()
        c.host = h
        let ev = events(c)
        await c.setup(key: key, appId: nil, backendURL: nil)
        _ = await c.show()
        c.handlePageMessage("{\"type\":\"close\"}")
        c.handlePageMessage("{\"type\":\"openUrl\",\"url\":\"https://example.com\"}")
        c.handlePageMessage("{\"type\":\"openUrl\",\"url\":\"javascript:alert(1)\"}")
        XCTAssertFalse(c.visible)
        XCTAssertEqual(h.opened, ["https://example.com"])
        XCTAssertEqual(ev(), ["open", "close"])
    }

    func testLookAlikeHost() async {
        let c = core(["ok": true, "sdk": true, "chatUrl": chat])
        await c.setup(key: key, appId: nil, backendURL: nil)
        XCTAssertTrue(c.isChatURL("https://maurieai.com/chat/agent-1?sdk=1"))
        XCTAssertFalse(c.isChatURL("https://maurieai.com.evil.net/x"))
    }
}
