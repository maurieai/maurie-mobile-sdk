# Maurie Mobile SDK

The Maurie AI chat inside a business's own app (Maurie Pro plan). One folder per platform:

| Folder | Package | Status |
| --- | --- | --- |
| `react-native/` | `@maurie/react-native` (npm) | Built, core logic tested (`npm test`); not yet run in a real app |
| `flutter/` | `maurie_chat` (pub.dev) | Written; not yet compiled (no Flutter SDK on the dev machine) |
| `ios/`, `android/` | MaurieChat (SPM), `com.maurieai:chat` (Maven Central) | Next |

Every SDK opens the agent's hosted chat page (`/chat/<agent>?sdk=1&key=…&appId=…`) in a WebView it keeps alive,
and talks to it through a bridge. Design: https://claude.ai/code/artifact/a3fb0603-13a4-4dec-bdf1-05b27c65e9ff
Server side: maurie-backend `lib/mobile-keys.js`, `/api/mobile/*`, `public/widget.js` (SDK mode).
