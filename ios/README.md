# MaurieChat (iOS)

The Maurie AI chat in your iPhone app. Requires the Maurie **Pro** plan and a mobile key from
**Maurie ▸ Agents ▸ Deploy ▸ Mobile app ▸ Mobile SDK**. iOS 15+.

## Install

Xcode ▸ File ▸ Add Package Dependencies… ▸ `https://github.com/maurieai/maurie-mobile-sdk` ▸ add **MaurieChat** to your app.

If visitors may attach photos, add `NSCameraUsageDescription` to your app's Info.plist (iOS asks before the camera opens).

## Use

```swift
import MaurieChat

// 1. Once, when the app starts (App init or AppDelegate)
Maurie.setup(key: "mpk_live_…")

// 2. After your customer signs in (skip it for guests)
Maurie.identify(MaurieUser(userId: user.id, name: user.name, email: user.email, userHash: userHash))

// 3. From your Help or Chat button
Maurie.show()

// 4. When the customer signs out
Maurie.reset()

// Optional
Maurie.on(.error) { error in print(error?.code ?? "") }
```

Your app's bundle ID is sent with the key automatically; list it under **Apps allowed to use it** to stop other apps
from using your key. `userHash` is HMAC-SHA256 of the user id with your identity secret, made on **your server**.
