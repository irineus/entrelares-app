// T-53, stage 4 — the TOMBSTONE of the Blazor PWA's service worker.
//
// Flutter Web takes over the hostname the Blazor PWA served, and a hostname
// with an installed PWA cannot simply be re-pointed: the old service worker
// answers every navigation from its own cache, so a browser that has it would
// keep serving the Blazor shell forever and never even download this app's
// index.html. What still reaches it is the browser's UPDATE CHECK, which
// re-fetches THIS url (`_headers` keeps it uncacheable, as the Blazor deploy
// always did). Serving a self-destructing worker here is therefore the one
// thing that frees the domain.
//
// It must stay at this exact path and keep working for as long as any device
// may still carry the old worker — deleting it would strand those installs.
// It registers no fetch handler on purpose: from activation on every request
// goes to the network, and Flutter's own `flutter_service_worker.js` takes
// over on the reload below.

self.addEventListener('install', () => {
  // Do not wait for the old worker's clients to close — they are exactly the
  // installs being rescued.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // 1. Drop every cache the old worker filled (the Blazor app shell and its
    //    asset manifest), so nothing of it can be served again.
    const names = await caches.keys();
    await Promise.all(names.map((name) => caches.delete(name)));

    // 2. Remove the registration itself. From here the scope is free for
    //    Flutter's worker.
    await self.registration.unregister();

    // 3. Reload the windows still showing the old shell — without this the
    //    user sits on a dead page until they navigate by hand.
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      client.navigate(client.url);
    }
  })());
});
