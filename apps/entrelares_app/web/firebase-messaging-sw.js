// T-62 — the web channel's push worker.
//
// **This is the THIRD service worker on this origin, and the only one that is
// new.** The other two are `service-worker.js`, the tombstone of the Blazor
// PWA's worker (scope `/`, clears the old caches, unregisters ITSELF, reloads
// the windows — it must keep doing exactly that for as long as any device may
// carry the old install, and it never touches another registration), and
// Flutter's own `flutter_service_worker.js`, the app shell, also at scope `/`.
// This file is registered by the Firebase JS SDK at ITS scope,
// `/firebase-cloud-messaging-push-scope`, which is why `push_messaging_web.dart`
// deliberately does not pass `serviceWorkerScriptPath`: the FlutterFire layer
// would register it with no `{scope}`, take scope `/`, and REPLACE the app
// shell's registration. Three workers, three scopes, no contention.
//
// **Why compat and not the ES modules.** `importScripts` is a classic-script
// loader; the SDK is registered without `{type: 'module'}`, so the worker
// cannot `import`. The compat bundles are the same SDK with a global-object
// façade. Both are VENDORED (`tool/vendor_firebase_js.py`) and served from
// this origin: the CSP allows executable code from `'self'` only, and the
// gstatic copies the plugin would otherwise reach for are blocked.
//
// **This file is copied verbatim into the build** (everything under `web/` is),
// so it carries the PRODUCTION config below — a worker starts with no page to
// ask, and the web channel only ever publishes production. It is compared,
// string by string, against `Env.prod.webPush` by `web_channel_test`; arming
// one side without the other is a red gate, not a silent half-push.

importScripts('/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('/firebasejs/12.18.0/firebase-messaging-compat.js');

// The PUBLIC Firebase Web config — the mirror of `Env.prod.webPush` (minus the
// VAPID key, which only the page needs). Empty while the channel ships DARK:
// filling this and `env.dart` in one delivery is the go-live
// (`supabase/README.md` §11-bis). Nothing here is a secret.
const FIREBASE_CONFIG = {
  apiKey: '',
  appId: '',
  messagingSenderId: '',
  projectId: '',
};

// The MIRROR of `PushRouting` (packages/entrelares_core) — the types that leave
// the recipient with something to DO, and therefore land on "Para você" instead
// of "Histórico". It is duplicated here for the same reason `_shared/push.ts`
// duplicates the copy catalog: a click on a notification is handled by a
// service worker, which cannot call Dart. `push_routing_worker_mirror_test`
// reads THIS file and compares it against `PushRouting.landingFor` for every
// pushable type, so the two cannot drift.
const ACTIONABLE_TYPES = ['swap_requested', 'revert_requested', 'auto_reminder'];

/// Where a tapped notification lands — the same URL `main.dart` builds for the
/// Android tap, which is what makes the two channels agree: the Notificações
/// screen reads `tab` and `n` from the query string either way.
function landingUrl(data) {
  const tab = ACTIONABLE_TYPES.includes(data.type) ? 'incoming' : 'history';
  const id = data.notificationId || '';
  const query = id ? `?tab=${tab}&n=${encodeURIComponent(id)}` : `?tab=${tab}`;
  return new URL(`/notifications${query}`, self.location.origin).href;
}

// Registered BEFORE `firebase.messaging()` on purpose, and the order is load
// bearing: the SDK installs its own `notificationclick` listener when messaging
// is initialized, and that listener calls `stopImmediatePropagation()`. Second
// in line, this handler would never run — the tap would close the notification
// and go nowhere, because the SDK only opens something when the payload carries
// `fcm_options.link`, and ours deliberately does not (the destination is a
// product rule, and it belongs next to the rule it mirrors).
self.addEventListener('notificationclick', (event) => {
  const payload = event.notification && event.notification.data
    ? event.notification.data['FCM_MSG']
    : null;
  // Not one of ours — leave it to whoever put it there.
  if (!payload) return;
  // An action BUTTON, not the notification body. This product ships none, and
  // guessing that a future one means "open the list" would be wrong.
  if (event.action) return;

  event.stopImmediatePropagation();
  event.notification.close();

  const target = landingUrl(payload.data || {});
  event.waitUntil((async () => {
    // FCM only SHOWS a notification when no tab is visible (it forwards the
    // message to the page otherwise), so there is usually nothing to reuse.
    // A hidden tab already sitting on the destination is the one case where
    // opening a second one would be worse than focusing the first.
    const clients = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    const existing = clients.find((client) => client.url === target);
    if (existing) return existing.focus();
    return self.clients.openWindow(target);
  })());
});

// Fails CLOSED. On an unarmed build the config above is empty, and
// `initializeApp` would throw on every push event — a worker that logs an
// exception nobody reads. It cannot receive anything either way (no VAPID key
// means the page never subscribes), so staying inert is the honest state.
if (FIREBASE_CONFIG.apiKey) {
  firebase.initializeApp(FIREBASE_CONFIG);
  // Installs the SDK's push handler: a message carrying a `notification` block
  // is displayed by the SDK itself, with the title and body the server already
  // rendered per recipient and the icon the `webpush` block names. There is no
  // `onBackgroundMessage` here on purpose — it fires for DATA-ONLY messages,
  // and this product sends a `notification` block precisely so the OS renders
  // it with the app closed.
  firebase.messaging();
}
