// flutter test — the SDK's logic without widgets. Mirrors react-native/test/core.test.mjs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maurie_chat/src/core.dart';

const key = 'mpk_live_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const chat = 'https://maurieai.com/chat/agent-1';

MaurieFetch returning(Map<String, dynamic> body, [List<Uri>? calls]) => (u) async {
      calls?.add(u);
      return body;
    };

class FakeHost implements MaurieHostHooks {
  final sent = <Map<String, dynamic>>[];
  final opened = <String>[];
  int renders = 0;
  @override
  void render() => renders++;
  @override
  void send(String json) => sent.add(jsonDecode(json) as Map<String, dynamic>);
  @override
  void openUrl(String url) => opened.add(url);
}

List<String> events(MaurieCore c) {
  final got = <String>[];
  for (final e in MaurieEvent.values) {
    c.on(e, (err) => got.add(err == null ? e.name : '${e.name}:${err.code}'));
  }
  return got;
}

void main() {
  test('setup on Pro: SDK url with key and appId, no error', () async {
    final calls = <Uri>[];
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': chat}, calls));
    final ev = events(c);
    await c.setup(key, appId: 'com.acme.app', backendUrl: 'https://api.example.com/');
    expect(calls.single.toString(), 'https://api.example.com/api/mobile/verify?key=$key&appId=com.acme.app');
    expect(c.url(), '$chat?sdk=1&key=$key&appId=com.acme.app');
    expect(ev, isEmpty);
  });

  test('below Pro: plain chat link, error not_pro, show still works', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': false, 'reason': 'not_pro', 'chatUrl': chat}));
    final ev = events(c);
    await c.setup(key);
    expect(c.url(), chat);
    expect(await c.show(), isTrue);
    expect(ev, ['error:not_pro', 'open']);
  });

  test('malformed key: no request, invalid_key, show refuses', () async {
    final calls = <Uri>[];
    final c = MaurieCore(fetch: returning({}, calls));
    final ev = events(c);
    await c.setup('mk_live_secret');
    expect(calls, isEmpty);
    expect(await c.show(), isFalse);
    expect(ev, ['error:invalid_key', 'error:not_ready']);
  });

  test('offline at setup: show tries once more', () async {
    var online = false;
    var calls = 0;
    final c = MaurieCore(fetch: (u) async {
      calls++;
      if (!online) throw Exception('offline');
      return {'ok': true, 'sdk': true, 'chatUrl': chat};
    });
    await c.setup(key);
    online = true;
    expect(await c.show(), isTrue);
    expect(calls, 2);
  });

  test('reset and identify before ready: reset first, then identify', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': chat}));
    final h = FakeHost();
    c.attach(h);
    await c.setup(key);
    c.reset();
    c.identify(const MaurieUser(userId: '7', userHash: 'ff'));
    expect(h.sent, isEmpty);
    c.handlePageMessage('{"type":"ready"}');
    expect(h.sent.map((m) => m['type']), ['reset', 'identify']);
  });

  test('a reload re-sends identify', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': chat}));
    final h = FakeHost();
    c.attach(h);
    await c.setup(key);
    c.handlePageMessage('{"type":"ready"}');
    c.identify(const MaurieUser(userId: 'u1', userHash: 'aa'));
    c.pageLoadStarted();
    c.handlePageMessage('{"type":"ready"}');
    expect(h.sent.map((m) => m['type']), ['identify', 'identify']);
  });

  test('close from the page hides; links only http(s) / mailto / tel', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': chat}));
    final h = FakeHost();
    c.attach(h);
    final ev = events(c);
    await c.setup(key);
    await c.show();
    c.handlePageMessage('{"type":"close"}');
    c.handlePageMessage(jsonEncode({'type': 'openUrl', 'url': 'https://example.com'}));
    c.handlePageMessage(jsonEncode({'type': 'openUrl', 'url': 'javascript:alert(1)'}));
    expect(c.visible, isFalse);
    expect(h.opened, ['https://example.com']);
    expect(ev, ['open', 'close']);
  });

  test('isChatUrl rejects look-alike hosts', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': chat}));
    await c.setup(key);
    expect(c.isChatUrl('https://maurieai.com/chat/agent-1?sdk=1'), isTrue);
    expect(c.isChatUrl('https://maurieai.com.evil.net/x'), isFalse);
  });

  test('a non-http chatUrl is refused', () async {
    final c = MaurieCore(fetch: returning({'ok': true, 'sdk': true, 'chatUrl': 'javascript:alert(1)'}));
    final ev = events(c);
    await c.setup(key);
    expect(c.url(), isNull);
    expect(ev, ['error:invalid_key']);
  });
}
