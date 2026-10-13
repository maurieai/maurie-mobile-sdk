// The Maurie SDK's logic without Android views — testable on the JVM (src/test). Same behaviour as
// react-native/src/core.ts, flutter/lib/src/core.dart and ios/Sources/MaurieChat/MaurieCore.swift; keep them in step.
package com.maurieai.chat

import org.json.JSONObject
import java.net.URLEncoder

const val MAURIE_DEFAULT_BACKEND = "https://api.maurieai.com"

/** The customer signed in to your app. [userHash] = HMAC-SHA256(userId, identity secret), made on YOUR server. */
data class MaurieUser @JvmOverloads constructor(
    val userId: String,
    val userHash: String,
    val name: String? = null,
    val email: String? = null,
    val phone: String? = null,
) {
    internal fun toJson(): JSONObject = JSONObject().apply {
        put("userId", userId)
        put("userHash", userHash)
        name?.let { put("name", it) }
        email?.let { put("email", it) }
        phone?.let { put("phone", it) }
    }
}

/** invalid_key, app_not_allowed, not_pro, network, not_ready, no_setup, limit_reached, bad_user_hash, bad_user… */
data class MaurieError(val code: String)

enum class MaurieEvent { READY, OPEN, CLOSE, ERROR }

data class MaurieVerifyResult(val ok: Boolean, val sdk: Boolean = false, val reason: String? = null, val chatUrl: String? = null)

/** What the Android side lends the core. All calls on the main thread. */
internal interface MaurieHostHooks {
    /** The chat URL or visibility changed. */
    fun render()
    /** Run window.MaurieBridge.receive(json) in the page. */
    fun send(json: String)
    /** Open a link in the phone's browser. */
    fun openUrl(url: String)
}

/**
 * Not thread-safe: use it from the main thread. [fetch] calls back on the main thread with the parsed JSON,
 * or null when the request failed (no network).
 */
internal class MaurieCore(private val fetch: (url: String, done: (JSONObject?) -> Unit) -> Unit) {
    var key = ""; private set
    var appId = ""; private set
    var backendUrl = MAURIE_DEFAULT_BACKEND; private set
    /** null until setup() succeeded. */
    var chatUrl: String? = null; private set
    /** false = the key works but the workspace is below Pro: the plain chat, without signed-in users or history. */
    var sdk = false; private set
    var visible = false; private set
    var host: MaurieHostHooks? = null

    private var pageReady = false
    private var user: MaurieUser? = null
    private val pending = mutableListOf<String>()   // resets for a page that isn't ready yet
    private val listeners = mutableMapOf<MaurieEvent, MutableList<(MaurieError?) -> Unit>>()
    private var verifying = false
    private val afterSetup = mutableListOf<() -> Unit>()
    private var lastReason: String? = null

    // ── Public API ────────────────────────────────────────────────────

    fun setup(key: String, appId: String?, backendUrl: String?, done: ((MaurieVerifyResult) -> Unit)? = null) {
        this.key = key.trim()
        this.appId = appId?.trim().orEmpty()
        this.backendUrl = (backendUrl ?: MAURIE_DEFAULT_BACKEND).trimEnd('/')
        verifying = true
        verify { r ->
            verifying = false
            lastReason = if (r.ok) null else (r.reason ?: "invalid_key")
            done?.invoke(r)
            val waiting = afterSetup.toList()
            afterSetup.clear()
            waiting.forEach { it() }
        }
    }

    fun identify(user: MaurieUser) {
        if (user.userId.isEmpty() || user.userHash.isEmpty()) { emit(MaurieEvent.ERROR, MaurieError("bad_user")); return }
        this.user = user
        if (pageReady) sendNow(JSONObject().put("type", "identify").put("user", user.toJson()))
    }

    fun reset() {
        user = null
        val msg = JSONObject().put("type", "reset").toString()
        val h = host
        if (pageReady && h != null) h.send(msg) else pending.add(msg)   // the page may hold the old conversation
    }

    fun show(done: ((Boolean) -> Unit)? = null) {
        if (chatUrl == null) {
            if (verifying) { afterSetup.add { show(done) }; return }
            // Offline when the app started: try once more now. A wrong key isn't asked about again.
            if (key.isNotEmpty() && lastReason == "network") { setup(key, appId, backendUrl) { finishShow(done) }; return }
        }
        finishShow(done)
    }

    private fun finishShow(done: ((Boolean) -> Unit)?) {
        if (chatUrl == null) {
            emit(MaurieEvent.ERROR, MaurieError(if (key.isEmpty()) "no_setup" else "not_ready"))
            done?.invoke(false)
            return
        }
        if (!visible) {
            visible = true
            host?.render()
            emit(MaurieEvent.OPEN)
        }
        done?.invoke(true)
    }

    fun hide() {
        if (!visible) return
        visible = false
        host?.render()
        emit(MaurieEvent.CLOSE)
    }

    /** Listen to an event. Returns a function that stops listening. */
    fun on(event: MaurieEvent, fn: (MaurieError?) -> Unit): () -> Unit {
        listeners.getOrPut(event) { mutableListOf() }.add(fn)
        return { listeners[event]?.remove(fn) }
    }

    // ── For the Android side ──────────────────────────────────────────

    /** The page the WebView loads: SDK mode with the key on Pro, else the plain chat link. */
    fun url(): String? {
        val c = chatUrl ?: return null
        if (!sdk) return c
        val q = "sdk=1&key=${enc(key)}" + if (appId.isNotEmpty()) "&appId=${enc(appId)}" else ""
        return c + (if ('?' in c) "&" else "?") + q
    }

    /** Links inside the chat's own site stay in the WebView; everything else goes to the phone's browser. */
    fun isChatUrl(url: String): Boolean {
        val c = chatUrl ?: return false
        val origin = ORIGIN_RE.find(c)?.value?.lowercase() ?: return false
        return url.startsWith("$origin/")
    }

    /** The WebView started loading a page (also a reload): wait for its `ready` again. */
    fun pageLoadStarted() { pageReady = false }

    /** A message from the page (the bridge). */
    fun handlePageMessage(data: String) {
        val m = try { JSONObject(data) } catch (_: Exception) { return }
        when (m.str("type")) {
            "ready" -> {
                pageReady = true
                val queued = pending.toList()
                pending.clear()
                queued.forEach { host?.send(it) }
                user?.let { sendNow(JSONObject().put("type", "identify").put("user", it.toJson())) }
                emit(MaurieEvent.READY)
            }
            "close" -> hide()
            "openUrl" -> {
                val u = m.str("url")
                if (u != null && LINK_RE.containsMatchIn(u)) host?.openUrl(u)
            }
            "error" -> emit(MaurieEvent.ERROR, MaurieError(m.str("code") ?: "unknown"))
        }
    }

    // ── Inside ────────────────────────────────────────────────────────

    private fun verify(done: (MaurieVerifyResult) -> Unit) {
        if (!KEY_RE.matches(key)) {
            chatUrl = null
            emit(MaurieEvent.ERROR, MaurieError("invalid_key"))
            done(MaurieVerifyResult(false, reason = "invalid_key"))
            return
        }
        val qs = "key=${enc(key)}" + if (appId.isNotEmpty()) "&appId=${enc(appId)}" else ""
        fetch("$backendUrl/api/mobile/verify?$qs") { d ->
            if (d == null) {
                emit(MaurieEvent.ERROR, MaurieError("network"))
                done(MaurieVerifyResult(false, reason = "network"))
                return@fetch
            }
            val url = d.str("chatUrl")
            if (!d.optBoolean("ok") || url == null || !HTTP_RE.containsMatchIn(url)) {
                chatUrl = null
                host?.render()
                val reason = d.str("reason") ?: "invalid_key"
                emit(MaurieEvent.ERROR, MaurieError(reason))
                done(MaurieVerifyResult(false, reason = reason))
                return@fetch
            }
            sdk = d.optBoolean("sdk")
            chatUrl = url
            host?.render()
            // Below Pro the chat still works, as the plain chat link — the app is told why the extras are off.
            if (!sdk) emit(MaurieEvent.ERROR, MaurieError(d.str("reason") ?: "not_pro"))
            done(MaurieVerifyResult(true, sdk, d.str("reason"), url))
        }
    }

    private fun sendNow(msg: JSONObject) { host?.send(msg.toString()) }

    private fun emit(event: MaurieEvent, error: MaurieError? = null) {
        for (fn in listeners[event].orEmpty().toList()) {
            try { fn(error) } catch (_: Exception) { /* a listener's bug must not break the chat */ }
        }
    }

    private companion object {
        val KEY_RE = Regex("^mpk_live_[A-Za-z0-9]{32}$")
        val ORIGIN_RE = Regex("^https?://[^/?#]+", RegexOption.IGNORE_CASE)
        val HTTP_RE = Regex("^https?://", RegexOption.IGNORE_CASE)
        val LINK_RE = Regex("^(https?:|mailto:|tel:)", RegexOption.IGNORE_CASE)
        fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")
        /** optString turns a JSON null into the text "null" — this doesn't. */
        fun JSONObject.str(k: String): String? = if (has(k) && !isNull(k)) optString(k) else null
    }
}
