# Maurie Mobile SDK

The Maurie AI chat inside a business's own app (Maurie Pro plan). One folder per platform:

| Folder | Package | Status |
| --- | --- | --- |
| `react-native/` | `@maurie/react-native` (npm) | Built, core logic tested (`npm test`); not yet run in a real app |
| `flutter/` | `maurie_chat` (pub.dev) | Written with tests (`flutter test`); not yet compiled — no Flutter SDK on the dev machine |
| `ios/` | MaurieChat (Swift Package Manager) | Written with XCTest tests; not compiled — needs a Mac with Xcode |
| `android/` | `com.maurieai:chat` (Maven Central) | Written with JUnit tests; not compiled — needs Android Studio / the Android SDK |

Every SDK opens the agent's hosted chat page (`/chat/<agent>?sdk=1&key=…&appId=…`) in a WebView it keeps alive,
and talks to it through a bridge. Design: https://claude.ai/code/artifact/a3fb0603-13a4-4dec-bdf1-05b27c65e9ff
Server side: maurie-backend `lib/mobile-keys.js`, `/api/mobile/*`, `public/widget.js` (SDK mode).
