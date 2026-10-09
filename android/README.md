# com.maurieai:chat (Android)

The Maurie AI chat in your Android app. Requires the Maurie **Pro** plan and a mobile key from
**Maurie ▸ Agents ▸ Deploy ▸ Mobile app ▸ Mobile SDK**. Android 7.0 (API 24)+.

## Install

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.maurieai:chat:0.1.0")
}
```

## Use

```kotlin
// 1. Application.onCreate()
Maurie.setup(this, "mpk_live_…")

// 2. After your customer signs in (skip it for guests)
Maurie.identify(MaurieUser(userId = user.id, userHash = userHash, name = user.name, email = user.email))

// 3. From your Help or Chat button
Maurie.show(this)

// 4. When the customer signs out
Maurie.reset()

// Optional
Maurie.on(MaurieEvent.ERROR) { error -> Log.d("Maurie", error?.code ?: "") }
```

Your app's package name is sent with the key automatically; list it under **Apps allowed to use it** to stop other
apps from using your key. `userHash` is HMAC-SHA256 of the user id with your identity secret, made on **your server**.

The library adds the `INTERNET` permission and its own full-screen chat activity. Photo and PDF attachments, links
(opened in the phone's browser) and the back button are handled for you.

## Build and test this library

There is no Gradle wrapper in the repository yet: open `android/` in Android Studio (it creates one), then
`./gradlew :maurie-chat:testDebugUnitTest`.
