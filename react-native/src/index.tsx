/**
 * @maurie/react-native — the Maurie chat in a React Native / Expo app (Pro plan).
 *
 *   import Maurie, { MaurieHost } from '@maurie/react-native';
 *
 *   Maurie.setup('mpk_live_…', { appId: 'com.yourcompany.app' });   // once, at start
 *   <MaurieHost />                                                    // once, at the root of the app (last child)
 *   Maurie.identify({ userId, name, email, userHash });               // after sign-in (userHash from your server)
 *   Maurie.show();                                                    // from a Help / Chat button
 *   Maurie.reset();                                                   // on sign-out
 *   Maurie.on('error', (e) => console.log(e.code));
 */
import React, { useEffect, useReducer, useRef } from 'react';
import { BackHandler, Linking, StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';
import type { WebViewProps, WebViewMessageEvent } from 'react-native-webview';
import { MaurieCore } from './core';

// react-native-webview types its class as WebView<P = undefined>, and `WebViewProps & undefined` is `never` in strict
// TypeScript — so JSX can't type its props. The same component, typed with its real props:
const Web = WebView as unknown as React.ComponentClass<WebViewProps>;
interface WebHandle { injectJavaScript(script: string): void }
import type { MaurieEvent, MaurieUser, SetupOptions, VerifyResult } from './core';

export type { MaurieEvent, MaurieError, MaurieUser, SetupOptions, VerifyResult } from './core';

const core = new MaurieCore();

export const Maurie = {
  setup: (key: string, opts?: SetupOptions): Promise<VerifyResult> => core.setup(key, opts),
  identify: (user: MaurieUser): void => core.identify(user),
  show: (): Promise<boolean> => core.show(),
  hide: (): void => core.hide(),
  reset: (): void => core.reset(),
  on: (event: MaurieEvent, handler: (payload?: any) => void): (() => void) => core.on(event, handler),
  /** Is the chat on screen? */
  isVisible: (): boolean => core.visible,
};
export default Maurie;

/**
 * Holds the chat. Put it once at the root of your app, after your navigation, so it can cover the screen.
 * The WebView stays alive while hidden, so closing and reopening the chat keeps the conversation.
 */
export function MaurieHost(): React.ReactElement | null {
  const [, render] = useReducer((n: number) => n + 1, 0);
  const web = useRef<WebHandle | null>(null);

  useEffect(() => {
    const host = {
      render: () => render(),
      // The page's bridge: window.MaurieBridge.receive(json). JSON.stringify makes the json a safe JS string literal.
      send: (json: string) => web.current?.injectJavaScript(`window.MaurieBridge && window.MaurieBridge.receive(${JSON.stringify(json)}); true;`),
      openUrl: (url: string) => { Linking.openURL(url).catch(() => {}); },
    };
    core.attach(host);
    // Android back button closes the chat first.
    const back = BackHandler.addEventListener('hardwareBackPress', () => {
      if (!core.visible) return false;
      core.hide();
      return true;
    });
    return () => { back.remove(); core.detach(host); };
  }, []);

  const url = core.url();
  if (!url) return null;
  return (
    <View style={core.visible ? styles.shown : styles.hidden} pointerEvents={core.visible ? 'auto' : 'none'}>
      <Web
        ref={web as any}
        source={{ uri: url }}
        javaScriptEnabled
        domStorageEnabled
        setSupportMultipleWindows={false}
        allowsBackForwardNavigationGestures={false}
        onLoadStart={() => core.pageLoadStarted()}
        onMessage={(e: WebViewMessageEvent) => core.handlePageMessage(e.nativeEvent.data)}
        onShouldStartLoadWithRequest={(req: { url: string }) => {
          if (core.isChatUrl(req.url) || req.url === 'about:blank') return true;
          Linking.openURL(req.url).catch(() => {});
          return false;
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  shown: { ...StyleSheet.absoluteFillObject, zIndex: 10000, elevation: 10000, backgroundColor: '#ffffff' },
  // Kept alive off screen, not unmounted: a 1×1 view outside the visible area.
  hidden: { position: 'absolute', left: -10, top: -10, width: 1, height: 1, opacity: 0 },
});
