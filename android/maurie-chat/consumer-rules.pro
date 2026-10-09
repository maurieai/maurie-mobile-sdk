# The page calls MaurieAndroid.post(json) — keep the bridge's @JavascriptInterface methods through R8 / ProGuard.
-keepclassmembers class com.maurieai.chat.** {
    @android.webkit.JavascriptInterface <methods>;
}
