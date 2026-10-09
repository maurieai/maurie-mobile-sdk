// ./gradlew :maurie-chat:testDebugUnitTest — the SDK's logic without Android views. Mirrors react-native/test/core.test.mjs.
package com.maurieai.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val KEY = "mpk_live_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
private const val CHAT = "https://maurieai.com/chat/agent-1"

private class FakeHost : MaurieHostHooks {
    val sent = mutableListOf<JSONObject>()
    val opened = mutableListOf<String>()
    var renders = 0
    override fun render() { renders++ }
    override fun send(json: String) { sent.add(JSONObject(json)) }
    override fun openUrl(url: String) { opened.add(url) }
}

class MaurieCoreTest {
    private fun core(body: String?, calls: MutableList<String>? = null) =
        MaurieCore { url, done -> calls?.add(url); done(body?.let { JSONObject(it) }) }

    private fun events(c: MaurieCore): List<String> {
        val got = mutableListOf<String>()
        for (e in MaurieEvent.values()) c.on(e) { err -> got.add(if (err == null) e.name.lowercase() else "${e.name.lowercase()}:${err.code}") }
        return got
    }

    @Test fun setupOnPro() {
        val calls = mutableListOf<String>()
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""", calls)
        val ev = events(c)
        c.setup(KEY, "com.acme.app", "https://api.example.com/")
        assertEquals("https://api.example.com/api/mobile/verify?key=$KEY&appId=com.acme.app", calls.single())
        assertEquals("$CHAT?sdk=1&key=$KEY&appId=com.acme.app", c.url())
        assertTrue(ev.isEmpty())
    }

    @Test fun belowProFallsBackToPlainChat() {
        val c = core("""{"ok":true,"sdk":false,"reason":"not_pro","chatUrl":"$CHAT"}""")
        val ev = events(c)
        c.setup(KEY, null, null)
        assertEquals(CHAT, c.url())
        var shown = false
        c.show { shown = it }
        assertTrue(shown)
        assertEquals(listOf("error:not_pro", "open"), ev)
    }

    @Test fun malformedKey() {
        val calls = mutableListOf<String>()
        val c = core("{}", calls)
        val ev = events(c)
        c.setup("mk_live_secret", null, null)
        var shown = true
        c.show { shown = it }
        assertFalse(shown)
        assertTrue(calls.isEmpty())
        assertEquals(listOf("error:invalid_key", "error:not_ready"), ev)
    }

    @Test fun nullReasonIsNotTheTextNull() {
        val c = core("""{"ok":false,"reason":null}""")
        val ev = events(c)
        c.setup(KEY, null, null)
        assertEquals(listOf("error:invalid_key"), ev)
    }

    @Test fun offlineAtSetupRetriesOnShow() {
        var online = false
        var calls = 0
        val c = MaurieCore { _, done -> calls++; done(if (online) JSONObject("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""") else null) }
        c.setup(KEY, null, null)
        online = true
        var shown = false
        c.show { shown = it }
        assertTrue(shown)
        assertEquals(2, calls)
    }

    @Test fun resetThenIdentifyBeforeReady() {
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""")
        val h = FakeHost()
        c.host = h
        c.setup(KEY, null, null)
        c.reset()
        c.identify(MaurieUser(userId = "7", userHash = "ff"))
        assertTrue(h.sent.isEmpty())
        c.handlePageMessage("""{"type":"ready"}""")
        assertEquals(listOf("reset", "identify"), h.sent.map { it.getString("type") })
    }

    @Test fun reloadResendsIdentify() {
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""")
        val h = FakeHost()
        c.host = h
        c.setup(KEY, null, null)
        c.handlePageMessage("""{"type":"ready"}""")
        c.identify(MaurieUser(userId = "u1", userHash = "aa"))
        c.pageLoadStarted()
        c.handlePageMessage("""{"type":"ready"}""")
        assertEquals(listOf("identify", "identify"), h.sent.map { it.getString("type") })
    }

    @Test fun closeAndLinks() {
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""")
        val h = FakeHost()
        c.host = h
        val ev = events(c)
        c.setup(KEY, null, null)
        c.show()
        c.handlePageMessage("""{"type":"close"}""")
        c.handlePageMessage("""{"type":"openUrl","url":"https://example.com"}""")
        c.handlePageMessage("""{"type":"openUrl","url":"javascript:alert(1)"}""")
        c.handlePageMessage("not json")
        assertFalse(c.visible)
        assertEquals(listOf("https://example.com"), h.opened)
        assertEquals(listOf("open", "close"), ev)
    }

    @Test fun lookAlikeHost() {
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"$CHAT"}""")
        c.setup(KEY, null, null)
        assertTrue(c.isChatUrl("https://maurieai.com/chat/agent-1?sdk=1"))
        assertFalse(c.isChatUrl("https://maurieai.com.evil.net/x"))
    }

    @Test fun nonHttpChatUrlRefused() {
        val c = core("""{"ok":true,"sdk":true,"chatUrl":"javascript:alert(1)"}""")
        c.setup(KEY, null, null)
        assertNull(c.url())
    }
}
