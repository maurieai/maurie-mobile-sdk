/**
 * The Maurie SDK's logic, without React Native — so it can be tested in Node (test/core.test.mjs).
 * index.tsx wires it to a WebView (MaurieHost) and to Linking.
 *
 * How it works (design: https://claude.ai/code/artifact/a3fb0603-13a4-4dec-bdf1-05b27c65e9ff):
 *  1. setup(key) asks the server which agent the key belongs to (GET /api/mobile/verify).
 *  2. The host keeps ONE WebView with the agent's chat page alive, hidden, so the conversation survives
 *     closing and reopening the chat. show() / hide() only change whether it's on screen.
 *  3. The page and the app talk through a bridge: the page posts JSON strings (ready, close, openUrl, error);
 *     the app calls window.MaurieBridge.receive(...) (identify, reset).
 */

export const DEFAULT_BACKEND = 'https://api.maurieai.com';

export type MaurieEvent = 'ready' | 'open' | 'close' | 'error';
export interface MaurieError { code: string }
export interface MaurieUser {
  /** Your own id for the customer. */
  userId: string;
  name?: string;
  email?: string;
  phone?: string;
  /** HMAC-SHA256(userId, identity secret), made on YOUR server — never put the identity secret in the app. */
  userHash: string;
}
export interface SetupOptions {
  /** Your app's bundle ID / package name, when the agent limits which apps may use its key. */
  appId?: string;
  /** Only for testing against another Maurie server. */
  backendUrl?: string;
}
export interface VerifyResult { ok: boolean; agentId?: string; sdk?: boolean; reason?: string | null; chatUrl?: string }

/** What the host (the React Native component) lends the core. */
export interface Host {
  /** Re-draw: the chat URL or visibility changed. */
  render(): void;
  /** Run window.MaurieBridge.receive(json) in the page. */
  send(json: string): void;
  /** Open a link in the phone's browser. */
  openUrl(url: string): void;
}

type Listener = (payload?: any) => void;
type FetchLike = (url: string) => Promise<{ json(): Promise<any> }>;

export class MaurieCore {
  key = '';
  appId = '';
  backendUrl = DEFAULT_BACKEND;
  /** null until setup() succeeded. */
  chatUrl: string | null = null;
  /** false = the key works but the workspace is below Pro: the plain chat, without signed-in users or history. */
  sdk = false;
  visible = false;

  private pageReady = false;
  private user: MaurieUser | null = null;
  /** Messages for a page that isn't ready yet (only resets — identify is re-sent from `user` on every ready). */
  private pending: string[] = [];
  private listeners = new Map<MaurieEvent, Set<Listener>>();
  private host: Host | null = null;
  private setupRun: Promise<VerifyResult> | null = null;
  private lastReason: string | null = null;

  constructor(private fetchFn: FetchLike = (u) => (globalThis as any).fetch(u)) {}

  // ── Public API (Maurie.*) ──────────────────────────────────────────

  /** Once, when the app starts. Never throws: a problem fires the `error` event (invalid_key, app_not_allowed, network…). */
  setup(key: string, opts: SetupOptions = {}): Promise<VerifyResult> {
    this.key = String(key || '').trim();
    this.appId = String(opts.appId || '').trim();
    this.backendUrl = String(opts.backendUrl || DEFAULT_BACKEND).replace(/\/+$/, '');
    this.setupRun = this.verify().then((d) => { this.lastReason = d.ok ? null : (d.reason || 'invalid_key'); return d; });
    return this.setupRun;
  }

  /** The signed-in customer. Call again after a new sign-in; reset() on sign-out. */
  identify(user: MaurieUser) {
    if (!user || !user.userId || !user.userHash) { this.emit('error', { code: 'bad_user' }); return; }
    this.user = { ...user, userId: String(user.userId) };
    if (this.pageReady) this.sendNow({ type: 'identify', user: this.user });
  }

  /** Sign-out: forget the customer and their conversation (the next chat starts fresh). */
  reset() {
    this.user = null;
    const msg = JSON.stringify({ type: 'reset' });
    if (this.pageReady && this.host) this.host.send(msg);
    else this.pending.push(msg);   // also when the page loads later: it may hold the old conversation
  }

  /** Open the chat full screen. Before setup() finished, it waits for it. */
  async show(): Promise<boolean> {
    if (!this.chatUrl) {
      if (this.setupRun) await this.setupRun;
      // Offline when the app started: try once more now. A wrong key isn't asked about again.
      if (!this.chatUrl && this.key && this.lastReason === 'network') await this.setup(this.key, { appId: this.appId, backendUrl: this.backendUrl });
      if (!this.chatUrl) { this.emit('error', { code: this.key ? 'not_ready' : 'no_setup' }); return false; }
    }
    if (!this.visible) {
      this.visible = true;
      this.host?.render();
      this.emit('open');
    }
    return true;
  }

  hide() {
    if (!this.visible) return;
    this.visible = false;
    this.host?.render();
    this.emit('close');
  }

  /** Listen to ready / open / close / error. @returns a function that stops listening. */
  on(event: MaurieEvent, fn: Listener): () => void {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(fn);
    return () => { this.listeners.get(event)?.delete(fn); };
  }

  // ── For the host ───────────────────────────────────────────────────

  attach(host: Host) { this.host = host; host.render(); }
  detach(host: Host) { if (this.host === host) { this.host = null; this.pageReady = false; } }

  /** The page the WebView loads: SDK mode with the key on Pro, else the plain chat link. */
  url(): string | null {
    if (!this.chatUrl) return null;
    if (!this.sdk) return this.chatUrl;
    const q = `sdk=1&key=${encodeURIComponent(this.key)}` + (this.appId ? `&appId=${encodeURIComponent(this.appId)}` : '');
    return this.chatUrl + (this.chatUrl.includes('?') ? '&' : '?') + q;
  }

  /** Links inside the chat's own site stay in the WebView; everything else goes to the phone's browser. */
  isChatUrl(url: string): boolean {
    if (!this.chatUrl) return false;
    const origin = originOf(this.chatUrl);
    return !!origin && String(url || '').startsWith(origin + '/');
  }

  /** The WebView started loading a page (also a reload): wait for its `ready` again. */
  pageLoadStarted() { this.pageReady = false; }

  /** A message from the page (the bridge). */
  handlePageMessage(data: string) {
    let m: any;
    try { m = JSON.parse(String(data)); } catch (_) { return; }
    if (!m || typeof m !== 'object') return;
    switch (m.type) {
      case 'ready':
        this.pageReady = true;
        for (const msg of this.pending.splice(0)) this.host?.send(msg);
        if (this.user) this.sendNow({ type: 'identify', user: this.user });
        this.emit('ready');
        break;
      case 'close':
        this.hide();
        break;
      case 'openUrl':
        if (typeof m.url === 'string' && /^(https?:|mailto:|tel:)/i.test(m.url)) this.host?.openUrl(m.url);
        break;
      case 'error':
        this.emit('error', { code: String(m.code || 'unknown') });
        break;
    }
  }

  // ── Inside ─────────────────────────────────────────────────────────

  private async verify(): Promise<VerifyResult> {
    if (!/^mpk_live_[A-Za-z0-9]{32}$/.test(this.key)) {
      this.chatUrl = null;
      this.emit('error', { code: 'invalid_key' });
      return { ok: false, reason: 'invalid_key' };
    }
    let d: VerifyResult;
    try {
      const qs = `key=${encodeURIComponent(this.key)}` + (this.appId ? `&appId=${encodeURIComponent(this.appId)}` : '');
      const r = await this.fetchFn(`${this.backendUrl}/api/mobile/verify?${qs}`);
      d = await r.json();
    } catch (_) {
      this.emit('error', { code: 'network' });
      return { ok: false, reason: 'network' };
    }
    if (!d || !d.ok || typeof d.chatUrl !== 'string' || !/^https?:\/\//i.test(d.chatUrl)) {
      this.chatUrl = null;
      this.host?.render();
      this.emit('error', { code: (d && d.reason) || 'invalid_key' });
      return d || { ok: false, reason: 'invalid_key' };
    }
    this.sdk = !!d.sdk;
    this.chatUrl = d.chatUrl;
    this.host?.render();
    // Below Pro the chat still works, as the plain chat link — the app is told why the extras are off.
    if (!this.sdk) this.emit('error', { code: d.reason || 'not_pro' });
    return d;
  }

  private sendNow(msg: object) { this.host?.send(JSON.stringify(msg)); }

  private emit(event: MaurieEvent, payload?: any) {
    for (const fn of this.listeners.get(event) || []) {
      try { fn(payload); } catch (_) { /* a listener's bug must not break the chat */ }
    }
  }
}

function originOf(url: string): string | null {
  const m = /^(https?:\/\/[^/?#]+)/i.exec(url);
  return m ? m[1].toLowerCase() : null;
}
