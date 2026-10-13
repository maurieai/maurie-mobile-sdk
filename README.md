# Maurie Mobile SDK

Put your [Maurie AI](https://maurieai.com) chat inside your own mobile app. Your customers talk to the same agent
they meet on your website, without leaving the app.

You need the Maurie **Pro** plan and a mobile key from **Maurie ▸ Agents ▸ Deploy ▸ Mobile app ▸ Mobile SDK**.

| Platform | Folder | Requires |
| --- | --- | --- |
| iOS (Swift) | [`ios/`](ios/README.md) | iOS 15+ |
| Android (Kotlin) | [`android/`](android/README.md) | Android 7.0 (API 24)+ |
| React Native / Expo | [`react-native/`](react-native/README.md) | React Native 0.72+, `react-native-webview` 13+ |
| Flutter | [`flutter/`](flutter/README.md) | Flutter 3.x |

Each folder's README has the install step and the four calls you need: `setup` when the app starts, `identify`
after your customer signs in, `show` from your Help or Chat button, `reset` when they sign out.

## Install

**iOS** — Xcode ▸ File ▸ Add Package Dependencies… ▸ `https://github.com/maurieai/maurie-mobile-sdk` ▸ add **MaurieChat** to your app.

**Android**

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories { google(); mavenCentral(); maven("https://jitpack.io") }
}

// build.gradle.kts (app)
dependencies {
    implementation("com.github.maurieai:maurie-mobile-sdk:0.1.0")
}
```

**React Native / Expo**

```bash
npm install @maurie/react-native react-native-webview
```

**Flutter**

```yaml
# pubspec.yaml
dependencies:
  maurie_chat:
    git:
      url: https://github.com/maurieai/maurie-mobile-sdk.git
      path: flutter
      ref: 0.1.0
```

## How it works

Every SDK opens your agent's hosted chat page in a web view it keeps alive, and talks to it through a small bridge. New
chat features reach your app without an app update. A signed-in customer is recognised with a `userHash` your server
makes from the identity secret on the Deploy page — the secret itself never goes into the app.

## License

[MIT](LICENSE)
