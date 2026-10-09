/// The Maurie AI chat in your Flutter app (Maurie Pro plan).
///
/// ```dart
/// await Maurie.setup('mpk_live_…', appId: 'com.yourcompany.app');   // once, at start
/// Maurie.identify(MaurieUser(userId: user.id, name: user.name, email: user.email, userHash: userHash));
/// Maurie.show(context);                                               // from a Help / Chat button
/// Maurie.reset();                                                     // on sign-out
/// ```
library maurie_chat;

export 'src/core.dart' show MaurieUser, MaurieError, MaurieEvent, VerifyResult;
export 'src/maurie.dart' show Maurie;
