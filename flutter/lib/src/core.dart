// The Maurie SDK's logic without Flutter widgets — testable on its own (test/core_test.dart).
// Same behaviour as the React Native SDK's core.ts; keep the two in step.
import 'dart:convert';

const String defaultBackend = 'https://api.maurieai.com';

/// The customer signed in to your app.
class MaurieUser {
  /// Your own id for the customer.
  final String userId;
  final String? name;
  final String? email;
  final String? phone;

  /// HMAC-SHA256(userId, identity secret), made on YOUR server — never put the identity secret in the app.
  final String userHash;

  const MaurieUser({required this.userId, required this.userHash, this.name, this.email, this.phone});

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'userHash': userHash,
      };
}

/// invalid_key, app_not_allowed, not_pro, network, not_ready, no_setup, limit_reached, bad_user_hash, bad_user…
class MaurieError {
  final String code;
  const MaurieError(this.code);
  @override
  String toString() => 'MaurieError($code)';
}

enum MaurieEvent { ready, open, close, error }

class VerifyResult {
  final bool ok;
  final bool sdk;
  final String? reason;
  final String? chatUrl;
  const VerifyResult({required this.ok, this.sdk = false, this.reason, this.chatUrl});
}

/// What the Flutter side lends the core.
abstract class MaurieHostHooks {
  /// The chat URL or visibility changed.
  void render();

  /// Run window.MaurieBridge.receive(json) in the page.
  void send(String json);

  /// Open a link in the phone's browser.
  void openUrl(String url);
}

typedef MaurieFetch = Future<Map<String, dynamic>> Function(Uri url);
typedef MaurieListener = void Function(MaurieError? error);

class MaurieCore {
  MaurieCore({required MaurieFetch fetch}) : _fetch = fetch;

  final MaurieFetch _fetch;
  String key = '';
  String appId = '';
  String backendUrl = defaultBackend;

  /// null until setup() succeeded.
  String? chatUrl;

  /// false = the key works but the workspace is below Pro: the plain chat, without signed-in users or history.
  bool sdk = false;
  bool visible = false;

  bool _pageReady = false;
  MaurieUser? _user;
  final List<String> _pending = []; // resets for a page that isn't ready yet
  final Map<MaurieEvent, List<MaurieListener>> _listeners = {};
  MaurieHostHooks? _host;
  Future<VerifyResult>? _setupRun;
  String? _lastReason;

  static final RegExp _keyRe = RegExp(r'^mpk_live_[A-Za-z0-9]{32}$');

  // ── Public API ─────────────────────────────────────────────────────

  Future<VerifyResult> setup(String key, {String? appId, String? backendUrl}) {
    this.key = key.trim();
    this.appId = (appId ?? '').trim();
    this.backendUrl = (backendUrl ?? defaultBackend).replaceAll(RegExp(r'/+$'), '');
    _setupRun = _verify().then((d) {
      _lastReason = d.ok ? null : (d.reason ?? 'invalid_key');
      return d;
    });
    return _setupRun!;
  }

  void identify(MaurieUser user) {
    if (user.userId.isEmpty || user.userHash.isEmpty) {
      _emit(MaurieEvent.error, const MaurieError('bad_user'));
      return;
    }
    _user = user;
    if (_pageReady) _sendNow({'type': 'identify', 'user': user.toJson()});
  }

  void reset() {
    _user = null;
    final msg = jsonEncode({'type': 'reset'});
    if (_pageReady && _host != null) {
      _host!.send(msg);
    } else {
      _pending.add(msg); // also when the page loads later: it may hold the old conversation
    }
  }

  Future<bool> show() async {
    if (chatUrl == null) {
      if (_setupRun != null) await _setupRun;
      // Offline when the app started: try once more now. A wrong key isn't asked about again.
      if (chatUrl == null && key.isNotEmpty && _lastReason == 'network') {
        await setup(key, appId: appId, backendUrl: backendUrl);
      }
      if (chatUrl == null) {
        _emit(MaurieEvent.error, MaurieError(key.isNotEmpty ? 'not_ready' : 'no_setup'));
        return false;
      }
    }
    if (!visible) {
      visible = true;
      _host?.render();
      _emit(MaurieEvent.open);
    }
    return true;
  }

  void hide() {
    if (!visible) return;
    visible = false;
    _host?.render();
    _emit(MaurieEvent.close);
  }

  /// Listen to ready / open / close / error. Returns a function that stops listening.
  void Function() on(MaurieEvent event, MaurieListener fn) {
    _listeners.putIfAbsent(event, () => []).add(fn);
    return () => _listeners[event]?.remove(fn);
  }

  // ── For the Flutter side ───────────────────────────────────────────

  void attach(MaurieHostHooks host) {
    _host = host;
    host.render();
  }

  /// The page the WebView loads: SDK mode with the key on Pro, else the plain chat link.
  String? url() {
    final c = chatUrl;
    if (c == null) return null;
    if (!sdk) return c;
    final q = 'sdk=1&key=${Uri.encodeQueryComponent(key)}${appId.isNotEmpty ? '&appId=${Uri.encodeQueryComponent(appId)}' : ''}';
    return c + (c.contains('?') ? '&' : '?') + q;
  }

  /// Links inside the chat's own site stay in the WebView; everything else goes to the phone's browser.
  bool isChatUrl(String url) {
    final c = chatUrl;
    if (c == null) return false;
    final m = RegExp(r'^(https?://[^/?#]+)', caseSensitive: false).firstMatch(c);
    if (m == null) return false;
    return url.startsWith('${m.group(1)!.toLowerCase()}/');
  }

  /// The WebView started loading a page (also a reload): wait for its `ready` again.
  void pageLoadStarted() => _pageReady = false;

  /// A message from the page (the bridge).
  void handlePageMessage(String data) {
    Object? m;
    try {
      m = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    switch (m['type']) {
      case 'ready':
        _pageReady = true;
        final queued = List<String>.from(_pending);
        _pending.clear();
        for (final msg in queued) {
          _host?.send(msg);
        }
        if (_user != null) _sendNow({'type': 'identify', 'user': _user!.toJson()});
        _emit(MaurieEvent.ready);
        break;
      case 'close':
        hide();
        break;
      case 'openUrl':
        final u = m['url'];
        if (u is String && RegExp(r'^(https?:|mailto:|tel:)', caseSensitive: false).hasMatch(u)) _host?.openUrl(u);
        break;
      case 'error':
        _emit(MaurieEvent.error, MaurieError('${m['code'] ?? 'unknown'}'));
        break;
    }
  }

  // ── Inside ─────────────────────────────────────────────────────────

  Future<VerifyResult> _verify() async {
    if (!_keyRe.hasMatch(key)) {
      chatUrl = null;
      _emit(MaurieEvent.error, const MaurieError('invalid_key'));
      return const VerifyResult(ok: false, reason: 'invalid_key');
    }
    Map<String, dynamic> d;
    try {
      final qs = 'key=${Uri.encodeQueryComponent(key)}${appId.isNotEmpty ? '&appId=${Uri.encodeQueryComponent(appId)}' : ''}';
      d = await _fetch(Uri.parse('$backendUrl/api/mobile/verify?$qs'));
    } catch (_) {
      _emit(MaurieEvent.error, const MaurieError('network'));
      return const VerifyResult(ok: false, reason: 'network');
    }
    final url = d['chatUrl'];
    if (d['ok'] != true || url is! String || !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      chatUrl = null;
      _host?.render();
      final reason = (d['reason'] as String?) ?? 'invalid_key';
      _emit(MaurieEvent.error, MaurieError(reason));
      return VerifyResult(ok: false, reason: reason);
    }
    sdk = d['sdk'] == true;
    chatUrl = url;
    _host?.render();
    // Below Pro the chat still works, as the plain chat link — the app is told why the extras are off.
    if (!sdk) _emit(MaurieEvent.error, MaurieError((d['reason'] as String?) ?? 'not_pro'));
    return VerifyResult(ok: true, sdk: sdk, reason: d['reason'] as String?, chatUrl: url);
  }

  void _sendNow(Map<String, dynamic> msg) => _host?.send(jsonEncode(msg));

  void _emit(MaurieEvent event, [MaurieError? error]) {
    for (final fn in List<MaurieListener>.from(_listeners[event] ?? const [])) {
      try {
        fn(error);
      } catch (_) {
        // a listener's bug must not break the chat
      }
    }
  }
}
