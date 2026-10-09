// The Flutter side: one WebView with the agent's chat page, kept alive by its controller between shows,
// a full-screen route to show it, and the bridge (JavaScript channel "Maurie" ↔ window.MaurieBridge).
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'core.dart';

Future<Map<String, dynamic>> _httpFetch(Uri url) async {
  final r = await http.get(url).timeout(const Duration(seconds: 15));
  final d = jsonDecode(r.body);
  return d is Map<String, dynamic> ? d : <String, dynamic>{};
}

/// The Maurie chat. Call [setup] once at start, [identify] after sign-in, [show] from a button, [reset] on sign-out.
class Maurie {
  Maurie._();

  static final MaurieCore _core = MaurieCore(fetch: _httpFetch);
  static final _Hooks _hooks = _Hooks();
  static WebViewController? _controller;
  static String? _loadedUrl;
  static NavigatorState? _navigator;
  static Route<void>? _route;

  /// Once, when the app starts. Never throws: a problem fires [MaurieEvent.error].
  static Future<VerifyResult> setup(String key, {String? appId, String? backendUrl}) {
    _core.attach(_hooks);
    return _core.setup(key, appId: appId, backendUrl: backendUrl);
  }

  /// The signed-in customer (userHash from your server). Call again after a new sign-in.
  static void identify(MaurieUser user) => _core.identify(user);

  /// Sign-out: forget the customer and their conversation.
  static void reset() => _core.reset();

  /// Open the chat full screen, on top of [context]'s navigator.
  static Future<bool> show(BuildContext context) async {
    _navigator = Navigator.of(context);
    return _core.show();
  }

  static void hide() => _core.hide();

  static bool get isVisible => _core.visible;

  /// Listen to ready / open / close / error. Returns a function that stops listening.
  static void Function() on(MaurieEvent event, void Function(MaurieError? error) handler) => _core.on(event, handler);

  // ── Inside ─────────────────────────────────────────────────────────

  /// One controller per chat URL; it keeps the page (and the conversation) while the chat is closed.
  static void _sync() {
    final url = _core.url();
    if (url != null && url != _loadedUrl) {
      _loadedUrl = url;
      _controller = _newController(url);
    }
    final nav = _navigator;
    if (_core.visible && _route == null && nav != null && _controller != null) {
      final route = MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ChatScreen(controller: _controller!));
      _route = route;
      nav.push(route).then((_) => _routeGone(route));
    } else if (!_core.visible && _route != null) {
      final route = _route!;
      _route = null;
      if (route.isActive) route.navigator?.removeRoute(route);
    }
  }

  /// The route left the screen (close button, back button / gesture, or hide()).
  static void _routeGone(Route<void> route) {
    if (_route == route) _route = null;
    if (_core.visible) _core.hide();
  }

  static WebViewController _newController(String url) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel('Maurie', onMessageReceived: (m) => _core.handlePageMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => _core.pageLoadStarted(),
        onNavigationRequest: (req) {
          if (_core.isChatUrl(req.url) || req.url == 'about:blank') return NavigationDecision.navigate;
          _openExternal(req.url);
          return NavigationDecision.prevent;
        },
      ));
    // Photo / PDF attachments on Android (iOS shows its own picker).
    final p = c.platform;
    if (p is AndroidWebViewController) {
      p.setOnShowFileSelector((params) async {
        final res = await FilePicker.platform.pickFiles(allowMultiple: params.mode == FileSelectorMode.openMultiple);
        if (res == null) return <String>[];
        return res.files.where((f) => f.path != null).map((f) => Uri.file(f.path!).toString()).toList();
      });
    }
    c.loadRequest(Uri.parse(url));
    return c;
  }

  static void _openExternal(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Hooks implements MaurieHostHooks {
  @override
  void render() => Maurie._sync();

  @override
  void send(String json) {
    // jsonEncode makes the json a safe JS string literal.
    Maurie._controller?.runJavaScript('window.MaurieBridge && window.MaurieBridge.receive(${jsonEncode(json)});');
  }

  @override
  void openUrl(String url) => Maurie._openExternal(url);
}

class _ChatScreen extends StatelessWidget {
  const _ChatScreen({required this.controller});
  final WebViewController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: WebViewWidget(controller: controller)),
    );
  }
}
