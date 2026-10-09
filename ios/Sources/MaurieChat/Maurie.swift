// The UIKit side: one WKWebView with the agent's chat page, kept alive between shows (so the conversation stays),
// presented full screen, and the bridge (script message handler "maurie" ↔ window.MaurieBridge).
import UIKit
import WebKit

/// The Maurie chat (Maurie Pro plan).
///
///     Maurie.setup(key: "mpk_live_…")                       // once, at start (App init / AppDelegate)
///     Maurie.identify(MaurieUser(userId: id, name: name, email: email, userHash: hash))   // after sign-in
///     Maurie.show()                                          // from a Help / Chat button
///     Maurie.reset()                                         // on sign-out
@MainActor
public enum Maurie {
    private static let core = MaurieCore(fetch: { url in
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    })
    private static let host = MaurieWebHost()

    /// Once, when the app starts. The app's bundle ID is sent with the key (Deploy ▸ Mobile SDK ▸ Apps allowed).
    /// Never throws: a problem fires `.error`.
    public static func setup(key: String, backendURL: String? = nil) {
        core.host = host
        host.core = core
        Task { await core.setup(key: key, appId: Bundle.main.bundleIdentifier, backendURL: backendURL) }
    }

    /// The signed-in customer (userHash from your server). Call again after a new sign-in.
    public static func identify(_ user: MaurieUser) { core.identify(user) }

    /// Sign-out: forget the customer and their conversation.
    public static func reset() { core.reset() }

    /// Open the chat full screen, over `viewController` (default: the top one).
    public static func show(from viewController: UIViewController? = nil) {
        host.presenter = viewController
        Task { _ = await core.show() }
    }

    public static func hide() { core.hide() }

    public static var isVisible: Bool { core.visible }

    /// Listen to ready / open / close / error. Returns a function that stops listening.
    @discardableResult
    public static func on(_ event: MaurieEvent, _ handler: @escaping (MaurieError?) -> Void) -> () -> Void {
        core.on(event, handler)
    }
}

@MainActor
final class MaurieWebHost: NSObject, MaurieHostHooks, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var core: MaurieCore?
    weak var presenter: UIViewController?
    private var webView: WKWebView?
    private var loadedURL: String?
    private weak var screen: MaurieChatViewController?

    // ── MaurieHostHooks ───────────────────────────────────────────────

    func render() {
        guard let core = core else { return }
        if let url = core.url(), url != loadedURL, let u = URL(string: url) {
            loadedURL = url
            webView(creatingIfNeeded: true)?.load(URLRequest(url: u))
        }
        if core.visible, screen == nil, let web = webView {
            guard let top = presenter ?? Self.topViewController() else { core.hide(); return }
            let vc = MaurieChatViewController(webView: web) { [weak self] in self?.core?.hide() }
            vc.modalPresentationStyle = .fullScreen
            screen = vc
            top.present(vc, animated: true)
        } else if !core.visible, let vc = screen {
            screen = nil
            vc.dismiss(animated: true)
        }
    }

    func send(_ json: String) {
        // JSONSerialization of [json] gives ["…"]: the string as a safe JS literal.
        guard let d = try? JSONSerialization.data(withJSONObject: [json]), var lit = String(data: d, encoding: .utf8) else { return }
        lit = String(lit.dropFirst().dropLast())
        webView?.evaluateJavaScript("window.MaurieBridge && window.MaurieBridge.receive(\(lit));", completionHandler: nil)
    }

    func openURL(_ url: String) {
        if let u = URL(string: url) { UIApplication.shared.open(u) }
    }

    // ── The WebView ───────────────────────────────────────────────────

    private func webView(creatingIfNeeded: Bool) -> WKWebView? {
        if let w = webView { return w }
        guard creatingIfNeeded else { return nil }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // localStorage survives app restarts: the conversation carries on
        config.userContentController.add(WeakMessageHandler(self), name: "maurie")
        let w = WKWebView(frame: .zero, configuration: config)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.backgroundColor = .white
        w.allowsBackForwardNavigationGestures = false
        webView = w
        return w
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let s = message.body as? String { core?.handlePageMessage(s) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        core?.pageLoadStarted()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url?.absoluteString ?? ""
        if navigationAction.targetFrame?.isMainFrame == true, url != "about:blank", core?.isChatURL(url) != true {
            openURL(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // target=_blank links: the phone's browser, never a second WebView.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url?.absoluteString { openURL(u) }
        return nil
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
}

/// WKUserContentController keeps its handlers strongly; this breaks the cycle with the host.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

/// The full-screen chat. Borrows the shared WebView while on screen.
final class MaurieChatViewController: UIViewController {
    private let webView: WKWebView
    private let onGone: () -> Void

    init(webView: WKWebView, onGone: @escaping () -> Void) {
        self.webView = webView
        self.onGone = onGone
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onGone() }
    }
}
