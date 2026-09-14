/// T-65 — "does this device already have the Play app?", asked of the device.
///
/// The Closed Alpha report the item came from could not be settled by looking
/// at the screenshot: a nudge to INSTALL and a handoff to an INSTALLED app are
/// different products, and nothing on our side knew which one the tester
/// needed. The browser knows. `navigator.getInstalledRelatedApps()` answers it
/// on Chrome for Android, and it needs BOTH halves of a Digital Asset Links
/// pair to do so, plus the two pointers that let the page reach them:
///
///   * site → app: `web/.well-known/assetlinks.json`, which has named the
///     store package since F-54;
///   * app → site: the `asset_statements` resource named by a `<meta-data>` in
///     `AndroidManifest.xml`, added by this item;
///   * `related_applications` in `web/manifest.json`, which already named
///     `com.entrelares.app`;
///   * and the `<link rel="manifest">` in `web/index.html`, which is how the
///     browser finds that manifest at all.
///
/// **None of the four fails loudly.** With one missing the call resolves to an
/// EMPTY LIST, which is indistinguishable from "the app is not installed" — so
/// the banner would simply never appear and nothing anywhere would say why.
/// That is the T-62 `getToken` lesson in another API: read what the platform
/// DOES, and pin the pieces it depends on as sources. `web_channel_test` reads
/// all four.
///
/// Measured on a real device on 13/09/2026: with all four in place the API
/// answered `[{platform: "play", id: "com.entrelares.app", version: "2.6.17"}]`
/// on `https://web.entrelares.app` — the detection was never the defect; the
/// shell not repainting on the late answer was (see `HomeShell.appHandoff`).
///
/// Everywhere else — every non-web build, and on the web every browser that
/// does not expose the API (Firefox, Samsung Internet, iOS, desktop) — the
/// answer is `false`. Fail-closed is the T-38 shape: a service that cannot
/// answer never becomes a broken offer. The accepted price is that some
/// Android readers who DO have the app will not be shown the shortcut.
///
/// The choice is made at COMPILE time by the conditional export below, so
/// neither implementation's imports ever reach the other platform — the same
/// split `boot_handoff.dart` and `file_delivery.dart` use.
library;

export 'installed_app_io.dart'
    if (dart.library.js_interop) 'installed_app_web.dart';
