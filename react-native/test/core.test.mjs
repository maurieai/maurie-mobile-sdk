// node --test — the SDK's logic without React Native (lib/core.js, built by `npm run build`).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { MaurieCore } = createRequire(import.meta.url)('../lib/core.js');

const KEY = 'mpk_live_' + 'A'.repeat(32);
const CHAT = 'https://maurieai.com/chat/agent-1';

function fetchReturning(body, calls = []) {
  return async (url) => { calls.push(url); if (body instanceof Error) throw body; return { json: async () => body }; };
}
function fakeHost() {
  const h = { sent: [], opened: [], renders: 0 };
  h.render = () => { h.renders++; };
  h.send = (json) => h.sent.push(JSON.parse(json));
  h.openUrl = (u) => h.opened.push(u);
  return h;
}
function events(core) {
  const got = [];
  for (const e of ['ready', 'open', 'close', 'error']) core.on(e, (p) => got.push(p ? `${e}:${p.code}` : e));
  return got;
}

test('setup on Pro: SDK url with key and appId, no error', async () => {
  const calls = [];
  const c = new MaurieCore(fetchReturning({ ok: true, agentId: 'agent-1', sdk: true, chatUrl: CHAT }, calls));
  const ev = events(c);
  await c.setup(KEY, { appId: 'com.acme.app', backendUrl: 'https://api.example.com/' });
  assert.equal(calls[0], `https://api.example.com/api/mobile/verify?key=${KEY}&appId=com.acme.app`);
  assert.equal(c.url(), `${CHAT}?sdk=1&key=${KEY}&appId=com.acme.app`);
  assert.deepEqual(ev, []);
});

test('setup below Pro: plain chat link still works, error not_pro', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, agentId: 'agent-1', sdk: false, reason: 'not_pro', chatUrl: CHAT }));
  const ev = events(c);
  await c.setup(KEY);
  assert.equal(c.url(), CHAT);
  assert.deepEqual(ev, ['error:not_pro']);
  assert.equal(await c.show(), true);
});

test('malformed key: no request, error invalid_key, show refuses', async () => {
  const calls = [];
  const c = new MaurieCore(fetchReturning({}, calls));
  const ev = events(c);
  await c.setup('mk_live_secret');
  assert.equal(calls.length, 0);
  assert.equal(c.url(), null);
  assert.equal(await c.show(), false);
  assert.deepEqual(ev, ['error:invalid_key', 'error:not_ready']);
});

test('server refuses (app_not_allowed): error with the server reason, not asked again on show', async () => {
  const calls = [];
  const c = new MaurieCore(fetchReturning({ ok: false, reason: 'app_not_allowed' }, calls));
  const ev = events(c);
  await c.setup(KEY, { appId: 'com.other' });
  assert.equal(await c.show(), false);
  assert.equal(calls.length, 1);
  assert.deepEqual(ev, ['error:app_not_allowed', 'error:not_ready']);
});

test('offline at setup: show() tries once more', async () => {
  const calls = [];
  let online = false;
  const c = new MaurieCore(async (u) => { calls.push(u); if (!online) throw new Error('offline'); return { json: async () => ({ ok: true, sdk: true, chatUrl: CHAT }) }; });
  await c.setup(KEY);
  online = true;
  assert.equal(await c.show(), true);
  assert.equal(calls.length, 2);
});

test('identify before the page is ready waits; reset before ready goes first', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const h = fakeHost();
  c.attach(h);
  await c.setup(KEY);
  c.reset();
  c.identify({ userId: 7, name: 'Sara', email: 's@example.com', userHash: 'f'.repeat(64) });
  assert.deepEqual(h.sent, []);
  c.handlePageMessage(JSON.stringify({ type: 'ready' }));
  assert.deepEqual(h.sent.map((m) => m.type), ['reset', 'identify']);
  assert.equal(h.sent[1].user.userId, '7');
});

test('identify on a ready page goes at once; a reload re-sends it', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const h = fakeHost();
  c.attach(h);
  await c.setup(KEY);
  c.handlePageMessage('{"type":"ready"}');
  c.identify({ userId: 'u1', userHash: 'a'.repeat(64) });
  assert.equal(h.sent.length, 1);
  c.pageLoadStarted();
  c.handlePageMessage('{"type":"ready"}');
  assert.deepEqual(h.sent.map((m) => m.type), ['identify', 'identify']);
});

test('identify without userHash is refused', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const ev = events(c);
  c.identify({ userId: 'u1' });
  assert.deepEqual(ev, ['error:bad_user']);
});

test('show / close from the page / hide: events and renders', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const h = fakeHost();
  c.attach(h);
  const ev = events(c);
  await c.setup(KEY);
  await c.show();
  assert.equal(c.visible, true);
  c.handlePageMessage('{"type":"close"}');
  assert.equal(c.visible, false);
  c.hide();   // already hidden: no second close
  assert.deepEqual(ev, ['open', 'close']);
});

test('page links go to the phone browser; only http(s) / mailto / tel', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const h = fakeHost();
  c.attach(h);
  await c.setup(KEY);
  c.handlePageMessage(JSON.stringify({ type: 'openUrl', url: 'https://example.com/hours' }));
  c.handlePageMessage(JSON.stringify({ type: 'openUrl', url: 'javascript:alert(1)' }));
  c.handlePageMessage(JSON.stringify({ type: 'openUrl', url: 'tel:+15551234' }));
  assert.deepEqual(h.opened, ['https://example.com/hours', 'tel:+15551234']);
});

test('page errors become error events; junk messages are ignored', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  const ev = events(c);
  c.handlePageMessage('{"type":"error","code":"limit_reached"}');
  c.handlePageMessage('not json');
  c.handlePageMessage('42');
  assert.deepEqual(ev, ['error:limit_reached']);
});

test('isChatUrl: own site stays in the app, look-alike hosts do not', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  await c.setup(KEY);
  assert.equal(c.isChatUrl('https://maurieai.com/chat/agent-1?sdk=1'), true);
  assert.equal(c.isChatUrl('https://maurieai.com.evil.net/x'), false);
  assert.equal(c.isChatUrl('https://evil.net/https://maurieai.com/'), false);
});

test('a listener that throws does not break the others', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: CHAT }));
  let seen = false;
  c.on('open', () => { throw new Error('app bug'); });
  c.on('open', () => { seen = true; });
  await c.setup(KEY);
  await c.show();
  assert.equal(seen, true);
});

test('a chatUrl that is not http(s) is refused', async () => {
  const c = new MaurieCore(fetchReturning({ ok: true, sdk: true, chatUrl: 'javascript:alert(1)' }));
  const ev = events(c);
  await c.setup(KEY);
  assert.equal(c.url(), null);
  assert.deepEqual(ev, ['error:invalid_key']);
});
