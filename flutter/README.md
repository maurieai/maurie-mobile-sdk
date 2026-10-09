# maurie_chat

The Maurie AI chat in your Flutter app. Requires the Maurie **Pro** plan and a mobile key from
**Maurie ▸ Agents ▸ Deploy ▸ Mobile app ▸ Mobile SDK**.

## Install

```bash
flutter pub add maurie_chat
```

## Use

```dart
import 'package:maurie_chat/maurie_chat.dart';

// 1. Once, when the app starts
await Maurie.setup('mpk_live_…', appId: 'com.yourcompany.app');

// 2. After your customer signs in (skip it for guests)
Maurie.identify(MaurieUser(userId: user.id, name: user.name, email: user.email, userHash: userHash));

// 3. From your Help or Chat button
ElevatedButton(onPressed: () => Maurie.show(context), child: const Text('Chat with us'));

// 4. When the customer signs out
Maurie.reset();
```

`userHash` proves your server vouches for the customer. Make it on **your server**, never in the app:

```js
const userHash = crypto.createHmac('sha256', process.env.MAURIE_IDENTITY_SECRET).update(String(user.id)).digest('hex');
```

## Events

```dart
final stop = Maurie.on(MaurieEvent.error, (e) => debugPrint(e?.code));
```

`ready`, `open`, `close`, and `error` with a code: `invalid_key`, `app_not_allowed`, `not_pro` (the chat still works,
without signed-in customers or earlier messages), `network`, `not_ready`, `limit_reached`, `bad_user_hash`, `bad_user`.

## How it works

`setup` checks the key with Maurie and loads your agent's chat page in a WebView that stays alive while the chat is
closed, so the conversation carries on, also after the app restarts. Links in answers open in the phone's browser;
photos and PDFs can be attached. Your agent's settings, branding and message limits come from Maurie.
