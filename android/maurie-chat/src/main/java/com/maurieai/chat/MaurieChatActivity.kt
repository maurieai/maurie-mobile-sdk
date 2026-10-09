package com.maurieai.chat

import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.ValueCallback
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts

/** The full-screen chat. Borrows Maurie's WebView while on screen; closing it only hides the chat. */
class MaurieChatActivity : ComponentActivity() {
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private val picker = registerForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        fileCallback?.onReceiveValue(uris.toTypedArray())
        fileCallback = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val web = Maurie.attachTo(this)
        if (web == null) { finish(); return }
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.WHITE)
            fitsSystemWindows = true   // stay clear of the status / navigation bars (edge-to-edge on Android 15)
        }
        root.addView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
        onBackPressedDispatcher.addCallback(this) { Maurie.hide() }
    }

    /** Photo / PDF attachments from the chat. */
    internal fun pickFiles(callback: ValueCallback<Array<Uri>>) {
        fileCallback?.onReceiveValue(null)
        fileCallback = callback
        picker.launch("*/*")
    }

    override fun onDestroy() {
        fileCallback?.onReceiveValue(null)
        fileCallback = null
        Maurie.detachFrom(this)
        super.onDestroy()
    }
}
