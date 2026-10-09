package com.maurieai.chat.example

import android.graphics.Typeface
import android.os.Bundle
import android.text.InputType
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import com.maurieai.chat.Maurie
import com.maurieai.chat.MaurieEvent
import com.maurieai.chat.MaurieUser
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Test app for the Maurie Android SDK. Not an example of how to make userHash: a real app gets it from its own
 * server — the identity secret must never be in an app. This one takes it on screen only so testers can try identify.
 */
class MainActivity : ComponentActivity() {
    private val prefs by lazy { getSharedPreferences("maurie-example", MODE_PRIVATE) }
    private lateinit var log: TextView
    private val stops = mutableListOf<() -> Unit>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(40, 48, 40, 40) }

        fun title(text: String) = TextView(this).apply { this.text = text; textSize = 13f; setPadding(0, 24, 0, 4) }
        fun field(label: String, pref: String, default: String = "", secret: Boolean = false): EditText {
            col.addView(title(label))
            return EditText(this).apply {
                setText(prefs.getString(pref, default))
                textSize = 14f
                isSingleLine = true
                if (secret) inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                col.addView(this, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }
        }
        fun button(text: String, onClick: () -> Unit) = Button(this).apply {
            this.text = text
            isAllCaps = false
            setOnClickListener { onClick() }
            col.addView(this, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        col.addView(TextView(this).apply { text = "Maurie SDK test"; textSize = 22f; setTypeface(typeface, Typeface.BOLD) })
        col.addView(TextView(this).apply { text = "App ID: $packageName"; textSize = 12f })

        val backend = field("Backend URL", "backend", "https://api.maurieai.com")
        val key = field("Mobile key (Deploy ▸ Mobile app ▸ Mobile SDK)", "key")
        button("1. Setup") {
            prefs.edit().putString("backend", backend.text.toString().trim()).putString("key", key.text.toString().trim()).apply()
            write("setup…")
            Maurie.setup(applicationContext, key.text.toString().trim(), backend.text.toString().trim().ifEmpty { null })
        }
        button("2. Show chat") { Maurie.show(this) }

        val userId = field("User ID", "userId", "test-user-1")
        val name = field("Name", "name", "Test Customer")
        val email = field("Email", "email", "test@example.com")
        val secret = field("Identity secret — TEST ONLY, a real app gets userHash from its server", "secret", secret = true)
        button("3. Identify") {
            prefs.edit().putString("userId", userId.text.toString()).putString("name", name.text.toString())
                .putString("email", email.text.toString()).putString("secret", secret.text.toString()).apply()
            val id = userId.text.toString().trim()
            val hash = hmacSha256Hex(secret.text.toString().trim(), id)
            Maurie.identify(MaurieUser(userId = id, userHash = hash, name = name.text.toString().trim().ifEmpty { null },
                email = email.text.toString().trim().ifEmpty { null }))
            write("identify $id (hash ${hash.take(8)}…)")
        }
        button("4. Reset (sign out)") { Maurie.reset(); write("reset") }

        col.addView(title("Events"))
        log = TextView(this).apply { textSize = 12f; typeface = Typeface.MONOSPACE }
        col.addView(log)

        setContentView(ScrollView(this).apply { addView(col) })

        for (e in MaurieEvent.values()) {
            stops.add(Maurie.on(e) { err -> write(if (err == null) e.name.lowercase() else "${e.name.lowercase()}: ${err.code}") })
        }
    }

    override fun onDestroy() {
        stops.forEach { it() }
        stops.clear()
        super.onDestroy()
    }

    private fun write(line: String) {
        val time = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        log.text = "$time  $line\n${log.text}"
    }

    private fun hmacSha256Hex(secret: String, message: String): String {
        if (secret.isEmpty()) return ""
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
        return mac.doFinal(message.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
