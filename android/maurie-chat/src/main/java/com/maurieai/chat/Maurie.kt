// The Android side: one WebView with the agent's chat page, kept alive between shows (so the conversation stays),
// shown in MaurieChatActivity, and the bridge (JavascriptInterface "MaurieAndroid" ↔ window.MaurieBridge).
package com.maurieai.chat

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * The Maurie chat (Maurie Pro plan).
 *
 *     Maurie.setup(applicationContext, "mpk_live_…")          // once, in Application.onCreate()
 *     Maurie.identify(MaurieUser(userId = id, userHash = hash, name = name, email = email))   // after sign-in
 *     Maurie.show(activity)                                    // from a Help / Chat button
 *     Maurie.reset()                                           // on sign-out
 *
 * Call it from the main thread.
 */
object Maurie {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val core = MaurieCore { url, done ->
        io.execute {
            val result = try { httpGetJson(url) } catch (_: Exception) { null }
            main.post { done(result) }
        }
    }

    private var appContext: Context? = null
    private var launchContext: Context? = null
    private var webView: WebView? = null
    private var loadedUrl: String? = null
    private var screen: MaurieChatActivity? = null

    /** Once, when the app starts. The app's package name is sent with the key (Deploy ▸ Mobile SDK ▸ Apps allowed). */
    @JvmStatic
    @JvmOverloads
    fun setup(context: Context, key: String, backendUrl: String? = null) {
        appContext = context.applicationContext
        core.host = hooks
        core.setup(key, context.packageName, backendUrl)
    }

    /** The signed-in customer (userHash from your server). Call again after a new sign-in. */
    @JvmStatic
    fun identify(user: MaurieUser) = core.identify(user)

    /** Sign-out: forget the customer and their conversation. */
    @JvmStatic
    fun reset() = core.reset()

    /** Open the chat full screen. */
    @JvmStatic
    fun show(context: Context) {
        launchContext = context
        core.show()
    }

    @JvmStatic
    fun hide() = core.hide()

    @JvmStatic
    val isVisible: Boolean get() = core.visible

    /** Listen to an event. Returns a function that stops listening. */
    @JvmStatic
    fun on(event: MaurieEvent, handler: (MaurieError?) -> Unit): () -> Unit = core.on(event, handler)

    // ── For MaurieChatActivity ────────────────────────────────────────

    /** The activity borrows the WebView while it's on screen. */
    internal fun attachTo(activity: MaurieChatActivity): WebView? {
        val w = webView ?: return null
        screen = activity
        (w.context as? MutableContextWrapper)?.baseContext = activity   // dialogs / pickers need an activity
        (w.parent as? ViewGroup)?.removeView(w)
        return w
    }

    internal fun detachFrom(activity: MaurieChatActivity) {
        if (screen !== activity) return
        screen = null
        webView?.let { w ->
            (w.parent as? ViewGroup)?.removeView(w)
            appContext?.let { (w.context as? MutableContextWrapper)?.baseContext = it }
        }
        if (core.visible) core.hide()   // closed by the system or the back button
    }

    // ── Inside ────────────────────────────────────────────────────────

    private val hooks = object : MaurieHostHooks {
        override fun render() {
            val url = core.url()
            if (url != null && url != loadedUrl) {
                loadedUrl = url
                (webView ?: createWebView())?.loadUrl(url)
            }
            if (core.visible && screen == null && webView != null) {
                val ctx = launchContext ?: appContext ?: return
                val intent = Intent(ctx, MaurieChatActivity::class.java)
                if (ctx !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(intent)
            } else if (!core.visible) {
                screen?.finish()
            }
        }

        override fun send(json: String) {
            // JSONObject.quote makes the json a safe JS string literal.
            webView?.evaluateJavascript("window.MaurieBridge && window.MaurieBridge.receive(${JSONObject.quote(json)});", null)
        }

        override fun openUrl(url: String) {
            val ctx = screen ?: appContext ?: return
            try {
                val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                if (ctx !is android.app.Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(i)
            } catch (_: ActivityNotFoundException) { /* no app for that link */ }
        }
    }

    /** The page posts here; Android calls it on a background thread. */
    private object Bridge {
        @JavascriptInterface
        fun post(json: String) { main.post { core.handlePageMessage(json) } }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView? {
        val app = appContext ?: return null
        // A MutableContextWrapper lets the same WebView live without an activity and be shown in one later.
        val w = WebView(MutableContextWrapper(app))
        w.setBackgroundColor(Color.WHITE)
        w.settings.javaScriptEnabled = true
        w.settings.domStorageEnabled = true   // localStorage: the conversation carries on after the app restarts
        w.settings.setSupportMultipleWindows(false)
        // The bridge is only for our chat page: other pages never load in this WebView (shouldOverrideUrlLoading).
        w.addJavascriptInterface(Bridge, "MaurieAndroid")
        w.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val u = request.url.toString()
                if (core.isChatUrl(u) || u == "about:blank") return false
                hooks.openUrl(u)
                return true
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                core.pageLoadStarted()
            }
        }
        w.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView?, callback: ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean {
                val a = screen
                if (a == null || callback == null) { callback?.onReceiveValue(null); return true }
                a.pickFiles(callback)
                return true
            }
        }
        webView = w
        return w
    }

    private fun httpGetJson(url: String): JSONObject {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 15_000
        c.readTimeout = 15_000
        try {
            val stream = if (c.responseCode in 200..299) c.inputStream else c.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            return JSONObject(body.ifEmpty { "{}" })
        } finally {
            c.disconnect()
        }
    }
}
