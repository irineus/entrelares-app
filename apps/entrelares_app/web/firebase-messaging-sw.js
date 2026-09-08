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

// Registered BEFORE `importScripts` on purpose, and the order is load bearing:
// the SDK installs its own `notificationclick` listener, and that listener calls
// `stopImmediatePropagation()`. Second in line, this handler would never run —
// the tap would close the notification and go nowhere, because the SDK only
// opens something when the payload carries `fcm_options.link`, and ours
// deliberately does not (the destination is a product rule, and it belongs next
// to the rule it mirrors).
//
// It sits ABOVE the imports rather than merely above `firebase.messaging()`
// because `addEventListener` needs nothing from the SDK, and being first is then
// true by construction instead of true by a reading of the SDK's instantiation
// mode — which is a detail an upgrade is free to change under us.
self.addEventListener('notificationclick', (event) => {
  const data = event.notification ? event.notification.data : null;
  const payload = data ? data['FCM_MSG'] : null;
  // One line per tap, on purpose and permanently — the Dart side logs the same
  // way (`[push] …` in `push_service.dart`). A tap that goes nowhere is
  // invisible from every other vantage point: nothing throws, the notification
  // closes either way, and the server has long since reported success. This log
  // is the only place the difference between "the handler never ran", "the
  // payload was not what we expect" and "the browser refused the window" is
  // legible at all.
  console.log('[push] notificationclick', {
    hasData: !!data,
    keys: data ? Object.keys(data) : [],
    type: payload && payload.data ? payload.data.type : null,
  });
  // Not one of ours — leave it to whoever put it there.
  if (!payload) return;
  // An action BUTTON, not the notification body. This product ships none, and
  // guessing that a future one means "open the list" would be wrong.
  if (event.action) return;

  event.stopImmediatePropagation();
  event.notification.close();

  // `openWindow` is called SYNCHRONOUSLY, and that is the whole shape of this
  // block. Two things were wrong with the first version (found on the first
  // real click, 08/09/2026, when the notification arrived correctly and the tap
  // went nowhere):
  //
  //   1. It `await`ed `clients.matchAll()` first. A service worker may only
  //      open a window while it still holds the transient activation the click
  //      granted, and awaiting anything first is how that gets spent. The call
  //      has to be the first thing the handler does with it.
  //   2. It tried to REUSE an open tab with `focus()`. This worker's scope is
  //      `/firebase-cloud-messaging-push-scope`, so it controls no page at all
  //      and `client.navigate()` would throw — `focus()` was the only thing
  //      left, and it brings a tab forward WITHOUT moving it to the notice that
  //      was tapped. That is precisely the "nothing happened" the person sees.
  //      Its match was `client.url === target` too, which a fresh `n=<id>` makes
  //      almost never true — so the branch was dead except when it was wrong.
  //
  // Always opening is therefore both simpler and correct. The cost is a second
  // tab when one was already open, and FCM only shows a notification when no
  // client is visible, so that is the uncommon case and the lesser evil.
  event.waitUntil(
    self.clients
        .openWindow(landingUrl(payload.data || {}))
        // Without this the failure is invisible: a rejected promise inside
        // `waitUntil` is swallowed, which is exactly how the first version hid.
        .catch((error) => console.error('[push] openWindow failed', error)),
  );
});

importScripts('/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('/firebasejs/12.18.0/firebase-messaging-compat.js');

// The PUBLIC Firebase Web config — the mirror of `Env.prod.webPush` (minus the
// VAPID key, which only the page needs). Armed 08/09/2026 together with
// `env.dart`, which is the go-live of `supabase/README.md` §11-bis;
// `web_channel_test` compares the two objects string by string, so neither side
// can be armed — or later moved — on its own. Nothing here is a secret: every
// one of these values is served to any browser that opens the app.
const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyCqZbahPltUMUuH_IjWJCPhrH45ob6H6tM',
  appId: '1:575356979434:web:b193af65d8185c02e72f93',
  messagingSenderId: '575356979434',
  projectId: 'entrelares-prod',
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
