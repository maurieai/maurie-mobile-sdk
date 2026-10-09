# @maurie/react-native

The Maurie AI chat in your React Native or Expo app. Requires the Maurie **Pro** plan and a mobile key from
**Maurie ▸ Agents ▸ Deploy ▸ Mobile app ▸ Mobile SDK**.

## Install

```bash
npm install @maurie/react-native react-native-webview
# Expo
npx expo install @maurie/react-native react-native-webview
```

## Use

```jsx
import Maurie, { MaurieHost } from '@maurie/react-native';

// 1. Once, when the app starts
Maurie.setup('mpk_live_…', { appId: 'com.yourcompany.app' });

// 2. Once, at the root of the app, after your navigation
export default function App() {
  return (
    <>
      <YourNavigation />
      <MaurieHost />
    </>
  );
}

// 3. After your customer signs in (skip it for guests)
Maurie.identify({ userId: user.id, name: user.name, email: user.email, userHash });

// 4. From your Help or Chat button
<Button title="Chat with us" onPress={() => Maurie.show()} />

// 5. When the customer signs out
Maurie.reset();
```

`userHash` proves your server vouches for the customer. Make it on **your server**, never in the app:

```js
const userHash = crypto.createHmac('sha256', process.env.MAURIE_IDENTITY_SECRET).update(String(user.id)).digest('hex');
```

## Events

```js
const stop = Maurie.on('error', (e) => console.log(e.code));
```

| Event | When |
| --- | --- |
| `ready` | The chat page has loaded |
| `open` / `close` | The chat was shown / closed (by the visitor, `hide()` or the Android back button) |
| `error` | `invalid_key`, `app_not_allowed`, `not_pro` (the chat still works, without signed-in customers or earlier messages), `network`, `not_ready`, `limit_reached`, `bad_user_hash`, `bad_user` |

## How it works

`setup` checks the key with Maurie. `MaurieHost` keeps one WebView with your agent's chat alive, off screen, so
closing and reopening the chat keeps the conversation, and it carries on after the app restarts. Links in answers
open in the phone's browser. Your agent's settings, branding and message limits come from Maurie.
