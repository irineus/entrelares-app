// T-53 stage 4 — the gate of the WEB CHANNEL, cut to the same pattern as
// `no_color_literal_test`: files that only matter when they are SERVED cannot
// be proven by running the app, so they are proven as sources.
//
// Everything asserted here is something whose absence is silent until it is
// expensive: a build that quietly targets the QA project, a deep link that
// 404s on reload, an App Link that stops verifying on every installed phone,
// or an installed PWA that keeps serving the app this one replaced.
import 'dart:convert';
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';

import 'package:entrelares_app/deep_link_urls.dart';
import 'package:entrelares_app/env.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_driver/e2e_proof.dart'
    show executedKey, expectedTestsVariable, failedKey, proofFile, setUpAllKey;

File _web(String name) => File('web/$name');
File _workflow() => File('../.github/workflows/verify.yml');
File _androidManifest() =>
    File('android/app/src/main/AndroidManifest.xml');
File _androidStrings() => File('android/app/src/main/res/values/strings.xml');

/// Every `autoVerify` filter in the manifest, as raw blocks. These are the
/// filters that claim an https ADDRESS — the ones with the power to take a URL
/// away from the web channel.
List<String> _appLinkFilters(String manifest) =>
    RegExp(r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
            dotAll: true)
        .allMatches(manifest)
        .map((m) => m.group(1)!)
        .toList();

/// The one CSP the web channel ships, as written in `_headers`.
String? _csp(String headers) =>
    RegExp(r'Content-Security-Policy: (.+)').firstMatch(headers)?.group(1);

/// The sources a directive lists, in source order.
List<String> _sources(String csp, String directive) =>
    RegExp('$directive ([^;]+)').firstMatch(csp)!.group(1)!.trim().split(' ');

/// T-62 — the Firebase JS SDK version this repo vendors. Named once here and
/// checked against the four places that spell it out, plus the plugin constant
/// below, which is the authority.
const _firebaseSdkVersion = '12.18.0';

/// The Firebase JS SDK version `firebase_core_web` was tested against, read out
/// of the resolved package rather than repeated here.
///
/// Throws rather than skipping when the package cannot be located: a gate that
/// quietly does nothing reads as coverage on every future review, which is the
/// vacuous green this file already guards against elsewhere.
String _pluginSdkVersion() {
  final config = jsonDecode(File('.dart_tool/package_config.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final package = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == 'firebase_core_web',
          orElse: () => throw StateError(
              'firebase_core_web is not in package_config.json — run '
              '`flutter pub get`'));
  // `rootUri` is relative to `.dart_tool/` when the package is a path
  // dependency, absolute (`file:///…`) out of the pub cache.
  final root = Uri.parse('.dart_tool/')
      .resolve('${package['rootUri']}/')
      .resolve('${package['packageUri']}');
  final source =
      File.fromUri(root.resolve('src/firebase_sdk_version.dart')).readAsStringSync();
  final version = RegExp("supportedFirebaseJsSdkVersion = '([^']+)'")
      .firstMatch(source)
      ?.group(1);
  if (version == null) {
    throw StateError('firebase_core_web no longer declares '
        'supportedFirebaseJsSdkVersion in the shape this test reads.');
  }
  return version;
}

/// A shell or YAML source with its comment lines dropped — what the file DOES,
/// without what it explains.
///
/// T-68 needed this three times in one sitting, and the third one was caught
/// only by watching the assertion FAIL: `ops_alert.sh` names the product rails
/// in its header precisely to say why it does not touch them, `smoke_web.sh`
/// names `curl -f` to say why it is not used, and the `ops-alert` job comments
/// its own `if:` condition. Every guard written as "this string is (not) in the
/// file" matches the prose that explains the rule — and a guard that trips on
/// its own explanation is an argument for deleting the explanation.
String _withoutComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

/// Does one CSP source cover `<scheme>://<host>`? A source matches exactly or
/// through a single leading `*.` on the host, and `*.example.com` does NOT
/// cover the bare `example.com` — nothing else in this CSP is dynamic, so a
/// hand-rolled matcher says what it means where a general parser would only
/// look like it does.
bool _covers(String source, String scheme, String host) {
  final parts = RegExp(r'^(\w+)://(\*\.)?(.+)$').firstMatch(source);
  if (parts == null || parts.group(1) != scheme) return false;
  final pattern = parts.group(3)!;
  if (parts.group(2) == null) return host == pattern;
  return host.endsWith('.$pattern');
}

/// Every image URL a web manifest names, wherever it sits — `icons`,
/// `screenshots`, a shortcut's own icons, and any member the spec adds later.
/// Walked rather than listed, so a new image-bearing member is covered the day
/// it is written instead of the day somebody remembers this test.
List<String> _manifestSources(Object? node) => switch (node) {
      Map<String, dynamic>() => [
          for (final MapEntry(:key, :value) in node.entries)
            if (key == 'src' && value is String)
              value
            else
              ..._manifestSources(value),
        ],
      List<dynamic>() => [for (final item in node) ..._manifestSources(item)],
      _ => const [],
    };

void main() {
  group('_redirects (SPA fallback)', () {
    test('every unmatched path falls back to index.html with a 200', () {
      final rules = _web('_redirects').readAsStringSync();

      expect(
        RegExp(r'^/\*\s+/index\.html\s+200\s*$', multiLine: true)
            .hasMatch(rules),
        isTrue,
        reason: 'without this rule a reload of /family — or an invitation '
            'deep link — is a CDN 404 before the app boots',
      );
    });
  });

  group('the legal pages, after the host changes hands', () {
    test('the app links to the landing, not to the host it is taking over', () {
      // This app has no `/privacy` route (lote 4: one copy of the text, opened
      // in the browser). Pointing the link at the address being handed over
      // would make the policy unreachable from inside the product the moment
      // the domain moved — and nothing would fail until then.
      expect(DeepLinkUrls.privacy, startsWith(DeepLinkUrls.landingOrigin));
      expect(DeepLinkUrls.terms, startsWith(DeepLinkUrls.landingOrigin));
      expect(DeepLinkUrls.landingOrigin, isNot(DeepLinkUrls.webOrigin));
    });

    test('and the old paths still lead somewhere', () {
      // Links already out there — an e-mail, a bookmark, the old client —
      // name these paths on the host this channel now answers for.
      final rules = _web('_redirects').readAsStringSync();
      for (final path in const ['/privacy', '/terms']) {
        final rule = RegExp(r'^' + RegExp.escape(path) + r'\s+(\S+)\s+301',
                multiLine: true)
            .firstMatch(rules);
        expect(rule, isNotNull,
            reason: '$path must redirect, not fall into the SPA catch-all');
        expect(rule!.group(1), startsWith(DeepLinkUrls.landingOrigin));
      }
      // Order is the whole trick: first match wins in `_redirects`.
      expect(rules.indexOf('/privacy'), lessThan(rules.indexOf('/*')));
    });
  });

  group('_headers', () {
    late String headers;

    setUp(() => headers = _web('_headers').readAsStringSync());

    test('the CSP allows what CanvasKit needs and nothing more', () {
      final csp = _csp(headers);
      expect(csp, isNotNull, reason: 'the web channel ships with a CSP');

      // WebAssembly and blob workers: the engine does not run without them.
      expect(csp, contains("'wasm-unsafe-eval'"));
      expect(csp, contains('worker-src'));
      // What the app talks to — the Fulcrum gateway (REST, Auth, Functions,
      // Realtime; Fulcrum 03.4) and the collector.
      expect(csp, contains('https://api.entrelares.app'));
      expect(csp, contains('wss://api.entrelares.app'));
      expect(csp, contains('https://cloud.umami.is'));
      expect(csp, contains("frame-ancestors 'none'"));

      // The font fallback the engine fetches when the embedded Inter has no
      // glyph. Without it the product's emoji vocabulary is tofu on the web.
      expect(csp, contains('https://fonts.gstatic.com'));

      // Blazor WASM needed `unsafe-eval`; CanvasKit does not, and inheriting
      // it would be a permission granted for a reason that no longer exists.
      expect(csp, isNot(contains("'unsafe-eval'")));
      // CanvasKit is served from THIS origin (`--no-web-resources-cdn`). Fonts
      // may come from a third party; EXECUTABLE code may not — a gstatic host
      // inside script-src would mean the build lost that flag.
      final scriptSrc = RegExp(r'script-src ([^;]+)').firstMatch(csp!)!.group(1);
      expect(scriptSrc, isNot(contains('gstatic')));
    });

    // T-61 — the mirror that makes the auth host movable. `connect-src` and
    // `Env.supabaseUrl` are two independent strings in two files, and this is
    // the ONE place on the web channel where letting them drift costs nothing
    // at build time and everything at runtime: a host the CSP does not cover
    // is not a degraded auth flow, it is an app that reaches no API at all —
    // REST, Realtime and Functions included — with the browser console as the
    // only witness. Today `https://*.supabase.co` happens to cover both
    // projects; the moment prod answers on `auth.entrelares.app` (T-61, so the
    // Google consent screen names Entrelares instead of the project ref) that
    // wildcard stops covering it, and this test is what turns that into a red
    // gate instead of a silent outage. Fulcrum 03.4 moved the host for real
    // (`api.entrelares.app`), and since the QA build `qa-web` publishes ships
    // this SAME file, BOTH flavours are asserted — `deploy-web` publishes prod.
    test('connect-src covers the API host each flavour names', () {
      final sources = _sources(_csp(headers)!, 'connect-src');

      for (final env in const [Env.prod, Env.dev]) {
        final host = Uri.parse(env.supabaseUrl).host;
        for (final scheme in const ['https', 'wss']) {
          expect(
            sources.any((s) => _covers(s, scheme, host)),
            isTrue,
            reason: 'the CSP must allow $scheme://$host — `${env.name}` '
                'names it, so a build that cannot reach it is a dead app. '
                'Move the host and `_headers` moves with it.',
          );
        }
      }
    });

    // Fulcrum 03.4 — the other half: with the app behind the gateway nothing
    // of it may reach a Supabase project directly, and the browser is the one
    // place that can refuse it at runtime. A `*.supabase.co` left in
    // connect-src would let a stray project URL work on the web while the
    // gateway was meant to be the only door.
    test('connect-src admits no Supabase project host', () {
      final sources = _sources(_csp(headers)!, 'connect-src');
      expect(sources.where((s) => s.contains('supabase.co')), isEmpty,
          reason: 'the web app talks to the Fulcrum gateway only');
    });

    // T-66 — the same mirror, for the crash sink. It is worth its own test for
    // a reason the Supabase one does not have: a Supabase host the CSP misses
    // is a dead app, which somebody notices in a minute. A SENTRY host the CSP
    // misses is an app that works perfectly and reports nothing — the browser
    // blocks the POST, the reporter swallows the failure by contract, and the
    // channel goes quiet with no symptom at all. That is the exact silence
    // T-66 exists to end, so it gets a red gate instead of trust.
    test('connect-src covers the Sentry host BOTH DSNs name', () {
      final sources = _sources(_csp(headers)!, 'connect-src');

      for (final dsn in [Env.dev.sentryDsn, Env.prod.sentryDsn]) {
        final host = Uri.parse(dsn).host;
        expect(
          sources.any((s) => _covers(s, 'https', host)),
          isTrue,
          reason: 'the CSP must allow https://$host — a DSN the CSP does not '
              'cover makes the web channel silent, not broken. Move the '
              'project and `_headers` moves with it.',
        );
      }
    });

    test('the files whose staleness breaks a deploy are uncacheable', () {
      for (final path in const [
        '/service-worker.js',
        '/flutter_service_worker.js',
        '/flutter_bootstrap.js',
        '/index.html',
      ]) {
        final block = RegExp('${RegExp.escape(path)}\\r?\\n(.*)')
            .firstMatch(headers)
            ?.group(1);
        expect(block, contains('no-store'),
            reason: '$path must never come from an HTTP cache');
      }
    });
  });

  // L-29 — the app is not a search result. `_redirects` makes every address on
  // this host a 200 with the same canvas page, and Bing had already indexed it
  // beside the landing. Two files say "drop it", and only together: the header
  // says noindex, and robots.txt has to let the crawler in to READ the header.
  // A well-meant `Disallow: /` would look stricter and do the opposite — the
  // page is never fetched, the header never read, and a URL the landing links
  // to (/register, sixteen times) gets indexed from the link alone.
  group('search engines (L-29)', () {
    test('every path is served with X-Robots-Tag: noindex', () {
      final headers = _web('_headers').readAsStringSync();
      final everyPath =
          RegExp(r'^/\*\r?\n((?:[ \t]+.*\r?\n?)+)', multiLine: true)
              .firstMatch(headers)
              ?.group(1);
      expect(everyPath, isNotNull, reason: '`_headers` has a `/*` block');
      expect(everyPath, contains('X-Robots-Tag: noindex'),
          reason: 'on the `/*` block, so the rewritten routes carry it too — '
              'a rule on /index.html alone misses /register, which is served '
              'by the SPA fallback, not by that path');
    });

    test('robots.txt is a real file, and it does not block the crawl', () {
      final robots = _web('robots.txt');
      expect(robots.existsSync(), isTrue,
          reason: 'without it /robots.txt is index.html — an HTML robots file');
      final rules = _withoutComments(robots.readAsStringSync());
      expect(
        RegExp(r'^\s*Disallow:\s*/\s*$', multiLine: true, caseSensitive: false)
            .hasMatch(rules),
        isFalse,
        reason: 'a disallowed page is never fetched, so its noindex header is '
            'never read — blocking the crawl un-hides the app from the index',
      );
    });
  });

  group('service-worker.js (the Blazor tombstone)', () {
    late String worker;

    setUp(() => worker = _web('service-worker.js').readAsStringSync());

    test('it clears the old caches, unregisters and reloads the windows', () {
      expect(worker, contains('caches.delete'));
      expect(worker, contains('registration.unregister'));
      expect(worker, contains('skipWaiting'));
      expect(worker, contains('client.navigate'));
    });

    test('it handles no fetch — it is a tombstone, not a cache', () {
      // A fetch handler here would make this worker the app's network layer,
      // which is precisely the job it exists to take AWAY from the old one.
      expect(worker, isNot(contains("addEventListener('fetch'")));
    });
  });

  // ── T-62 — web push, and the three things about it that fail silently ──────
  //
  // The transport itself cannot be unit-tested: `push_messaging_web.dart` is
  // compiled only for the web, and `flutter test` runs on the VM, where the
  // conditional export resolves to the native file. So the parts whose failure
  // is invisible are proven as SOURCES here, the same way the tombstone above
  // is — a worker at the wrong scope, an SDK reaching for a blocked origin and
  // a permission prompt on page load are each a thing no green suite would
  // otherwise notice.
  group('web push (T-62)', () {
    late String worker;
    late String transport;

    setUp(() {
      worker = _web('firebase-messaging-sw.js').readAsStringSync();
      transport =
          File('lib/services/push_messaging_web.dart').readAsStringSync();
    });

    test('the SDK is vendored, and no copy still points at gstatic', () {
      // The reason this item touches `web/` at all: `firebase_core_web` does
      // not bundle the Firebase JS SDK, it injects it with a dynamic
      // `import("https://www.gstatic.com/firebasejs/…")`. That is executable
      // third-party code, which the CSP above forbids by decision — so the SDK
      // is vendored and the plugin is told to inject nothing.
      final dir = Directory('web/firebasejs/$_firebaseSdkVersion');
      expect(dir.existsSync(), isTrue,
          reason: 'run `python tool/vendor_firebase_js.py`');

      for (final name in const [
        // The ESM pair the PAGE imports.
        'firebase-app.js',
        'firebase-messaging.js',
        // The compat pair the WORKER importScripts — a classic-script loader
        // cannot take an ES module, and the SDK registers the worker without
        // `{type: 'module'}`.
        'firebase-app-compat.js',
        'firebase-messaging-compat.js',
      ]) {
        final file = File('${dir.path}/$name');
        expect(file.existsSync(), isTrue, reason: '$name is not vendored');
        // The rewrite the vendoring script exists for: the gstatic ESM bundles
        // hard-code the absolute URL of their own dependency, so a verbatim
        // copy would still fetch half the SDK from a blocked origin — and
        // only at the moment somebody enables push.
        expect(file.readAsStringSync(), isNot(contains('gstatic.com/firebasejs')),
            reason: '$name still reaches for gstatic; re-run the vendoring '
                'script, which fails loudly on exactly this');
      }
    });

    test('the vendored version is the one the plugin expects', () {
      // A `flutter pub upgrade` that moves `firebase_core_web` moves the SDK
      // version with it, and the plugin only complains in a browser console
      // nobody reads. Four places name this version — the vendoring script,
      // the directory, the Dart transport and the worker's importScripts —
      // and the plugin is the fifth and the authority.
      expect(_pluginSdkVersion(), _firebaseSdkVersion,
          reason: 'firebase_core_web now expects a different Firebase JS SDK; '
              'bump VERSION in tool/vendor_firebase_js.py, re-run it, and '
              'move the paths in the worker and in push_messaging_web.dart');

      final pinned = 'firebasejs/$_firebaseSdkVersion';
      expect(File('tool/vendor_firebase_js.py').readAsStringSync(),
          contains('VERSION = "$_firebaseSdkVersion"'));
      expect(transport, contains(pinned));
      expect(worker, contains(pinned));
    });

    test('the CSP lets the SDK register, without letting it execute', () {
      final csp = _csp(_web('_headers').readAsStringSync())!;
      // What the SDK TALKS to: an installation id, then a registration token.
      // Both are `fetch`, from the page and from the worker alike.
      for (final host in const [
        'https://firebaseinstallations.googleapis.com',
        'https://fcmregistrations.googleapis.com',
      ]) {
        expect(_sources(csp, 'connect-src'), contains(host),
            reason: 'without $host the control turns on and no token is ever '
                'minted — the browser console is the only witness');
      }
      // And the other half of the trade, which is the whole shape of T-62:
      // two hosts gained in connect-src, NOTHING gained in script-src. The
      // group above asserts the absence of gstatic there; this asserts that
      // neither Firebase host was added to it by mistake.
      final scriptSrc = _sources(csp, 'script-src');
      expect(scriptSrc.where((s) => s.contains('googleapis')), isEmpty);
      expect(scriptSrc.where((s) => s.contains('firebase')), isEmpty);
    });

    test('F-71: the CSP admits the GIS button and nothing wider of Google',
        () {
      final csp = _csp(_web('_headers').readAsStringSync())!;
      // The one third-party SCRIPT this CSP allows, and only its exact path:
      // the GIS client cannot be vendored (Google forbids self-hosting it),
      // and the native Google door on the web is its button.
      final scriptSrc = _sources(csp, 'script-src');
      expect(scriptSrc, contains('https://accounts.google.com/gsi/client'),
          reason: 'without it the GIS button never renders on the web');
      expect(
          scriptSrc.where((s) =>
              s.contains('google.com') &&
              s != 'https://accounts.google.com/gsi/client'),
          isEmpty,
          reason: 'only the GIS client path, never the whole host');
      expect(_sources(csp, 'frame-src'),
          containsAll(["'self'", 'blob:', 'https://accounts.google.com/gsi/']),
          reason: 'frame-src replaces the child-src fallback for frames, so '
              'it has to restate the print iframe (blob) beside the button');
      expect(_sources(csp, 'style-src'),
          contains('https://accounts.google.com/gsi/style'));
      expect(_sources(csp, 'connect-src'),
          contains('https://accounts.google.com/gsi/'));
    });

    test('the worker is never registered over the app shell', () {
      // The FlutterFire layer registers `serviceWorkerScriptPath` with NO
      // `{scope}`, which takes scope `/` — where Flutter's own worker lives.
      // Passing it would replace the app shell's registration with the push
      // worker. Null leaves the JS SDK to register it under its own scope,
      // `/firebase-cloud-messaging-push-scope`, beside the shell and beside
      // the Blazor tombstone.
      expect(transport, contains('serviceWorkerScriptPath: null'),
          reason: 'the messaging worker must not claim scope `/`');
    });

    test('reading the token never opens the permission prompt', () {
      // THE assertion of this group. The Firebase JS SDK's `getToken` calls
      // `Notification.requestPermission()` on its own when the permission is
      // still `default` — and `PushService.start` reads the token on EVERY
      // authenticated session, whose documented contract is that it never
      // prompts. Without the guard, the web channel would ask every returning
      // visitor for notification permission at boot, with no gesture and no
      // context, spending on page load the one prompt the product means to
      // spend on a press.
      final token = transport.substring(
        transport.indexOf('Future<String?> token()'),
        transport.indexOf('Future<void> deleteToken()'),
      );
      final guard = token.indexOf('_current != PushPermission.granted');
      final getToken = token.indexOf('getToken(');
      expect(guard, greaterThan(-1),
          reason: 'token() must read the permission itself before asking the '
              'SDK for anything');
      expect(guard, lessThan(getToken),
          reason: 'the guard has to come BEFORE getToken, which is what '
              'raises the prompt');
    });

    test('the worker and env.dart are armed together or not at all', () {
      // A service worker starts with no page to ask, so the Firebase config is
      // written twice: once in `Env.prod.webPush` for the page, once in the
      // worker. Arming one side only is the failure this pins — the control
      // would turn on, mint a token, and every push would reach a worker that
      // cannot read it.
      String field(String name) =>
          RegExp("$name: '([^']*)'").firstMatch(worker)?.group(1) ?? '<missing>';

      final config = Env.prod.webPush;
      expect(field('apiKey'), config.apiKey);
      expect(field('appId'), config.appId);
      expect(field('messagingSenderId'), config.messagingSenderId);
      expect(field('projectId'), config.projectId);

      // And the worker must stay inert while the values are blank: an
      // `initializeApp({apiKey: ''})` throws on every push event.
      expect(worker, contains('if (FIREBASE_CONFIG.apiKey)'),
          reason: 'an unarmed environment must produce an inert worker, not a '
              'worker that throws');
    });

    test('the worker is served fresh, and the pinned SDK is not', () {
      final headers = _web('_headers').readAsStringSync();
      final sw = RegExp(r'/firebase-messaging-sw\.js\r?\n(.*)')
          .firstMatch(headers)
          ?.group(1);
      expect(sw, contains('no-store'),
          reason: 'a cached worker pins the routing to an old build');
      // The opposite rule, and safe only because the version is in the path.
      final sdk =
          RegExp(r'/firebasejs/\*\r?\n(.*)').firstMatch(headers)?.group(1);
      expect(sdk, contains('immutable'));
    });
  });

  group('.well-known/assetlinks.json', () {
    test('it authorizes the packages the Android build claims', () {
      final statements = jsonDecode(
        _web('.well-known/assetlinks.json').readAsStringSync(),
      ) as List<dynamic>;

      Map<String, dynamic> targetOf(String package) => statements
          .cast<Map<String, dynamic>>()
          .map((s) => s['target'] as Map<String, dynamic>)
          .firstWhere((t) => t['package_name'] == package,
              orElse: () => throw StateError('missing statement: $package'));

      // The store app. It carries TWO fingerprints — the upload key and the
      // one Play's app signing emits — and dropping either breaks App Link
      // verification on every installed phone.
      final store = targetOf('com.entrelares.app');
      expect((store['sha256_cert_fingerprints'] as List).length, 2);

      // The dev flavor, so QA can verify its own links (lote 1).
      targetOf('com.entrelares.flutter');

      // And the legacy TWA package is GONE (T-52, 09/09/2026). Its statement
      // was the bridge that kept a `com.guardacompartilhada.app` install
      // full-screen; the Play app was deleted, so the bridge came out with it.
      // Asserted as an ABSENCE on purpose — this guard used to demand the
      // statement, and the same file is edited whenever a fingerprint moves.
      expect(
        statements
            .cast<Map<String, dynamic>>()
            .map((s) => (s['target'] as Map<String, dynamic>)['package_name']),
        isNot(contains('com.guardacompartilhada.app')),
        reason: 'a statement naming a retired package delegates our URLs to '
            'something nobody builds any more',
      );
    });

    test('it is served from the host the Android build verifies against', () {
      // The file only does anything at the hostname `autoVerify` names, which
      // is the hostname this channel is taking over. If one moves without the
      // other, invitation and recovery links stop opening in the app.
      final manifest = _androidManifest().readAsStringSync();
      expect(manifest, contains('android:host="${Env.prod.webHostname}"'));
      expect(Env.prod.webHostname, 'web.entrelares.app');
    });
  });

  group('manifest.json', () {
    test('it installs at the root and points at the store app', () {
      final manifest =
          jsonDecode(_web('manifest.json').readAsStringSync())
              as Map<String, dynamic>;

      expect(manifest['start_url'], '/');
      expect(manifest['scope'], '/');
      expect(manifest['id'], '/');
      expect(manifest['lang'], 'pt-BR');
      final related = manifest['related_applications'] as List<dynamic>;
      expect(
        related.cast<Map<String, dynamic>>().map((a) => a['id']),
        contains(Env.prod.androidPackage),
      );
    });

    // T-72 \u2014 the T-66 defect in another directive. The manifest pointed its
    // six screenshots at the LANDING's origin while `img-src` allows only this
    // one, so Chrome fetched all six on every load, was refused by our own
    // policy, and showed none \u2014 found only because a device console happened
    // to be open for T-65. A same-origin URL is not safe by being same-origin
    // either: `_redirects` answers a missing file with a 200 `index.html`
    // (T-68), which the browser then fails to decode as an image, so a
    // relative `src` has to name a file that ships.
    test('every image it names is one the CSP lets the browser load', () {
      final manifest = jsonDecode(_web('manifest.json').readAsStringSync());
      final imgSrc =
          _sources(_csp(_web('_headers').readAsStringSync())!, 'img-src');
      final page = Uri.parse('https://${Env.prod.webHostname}/manifest.json');
      final sources = _manifestSources(manifest);

      // Not vacuous: the walk has to reach the members this manifest has.
      expect(sources.where((s) => s.contains('Icon-')), isNotEmpty);
      expect(sources.where((s) => s.contains('screenshots/')), isNotEmpty);

      for (final src in sources) {
        final url = page.resolve(src);
        if (url.scheme == 'data' || url.scheme == 'blob') {
          expect(imgSrc, contains('${url.scheme}:'),
              reason: 'manifest.json names a ${url.scheme}: image and img-src '
                  'does not allow ${url.scheme}:');
        } else if (url.origin == page.origin) {
          expect(imgSrc, contains("'self'"));
          expect(_web(url.path.substring(1)).existsSync(), isTrue,
              reason: 'manifest.json names $src, which is not in app/web/ \u2014 '
                  'served, `_redirects` answers it with index.html and a 200');
        } else {
          expect(
            imgSrc.any((s) => _covers(s, url.scheme, url.host)),
            isTrue,
            reason: 'manifest.json names $url, and img-src ($imgSrc) does not '
                'allow ${url.scheme}://${url.host}: the browser fetches it on '
                'every load and our own policy refuses it. Serve the file from '
                'app/web/ (T-72) rather than widening img-src.',
          );
        }
      }
    });
  });

  group('the iPhone install hint (U-51)', () {
    // The hint tells a Safari reader the app "opens like an app, with an icon
    // on your screen". That is a claim about what THIS channel serves (the
    // S-19/L-27 family): it is true only while the manifest asks for a
    // standalone window and the page carries the Apple tags Safari reads
    // when it adds a site to the Home Screen. Drop either and the hint keeps
    // showing over a bookmark that opens in a tab.
    test('the manifest opens standalone', () {
      final manifest =
          jsonDecode(_web('manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['display'], 'standalone');
    });

    test('index.html carries the Apple Home Screen tags, and the icon ships',
        () {
      final html = _web('index.html').readAsStringSync();
      expect(html,
          contains('<meta name="apple-mobile-web-app-title" content="Entrelares">'));
      expect(html, contains('name="apple-mobile-web-app-status-bar-style"'));
      final icon = RegExp(r'<link rel="apple-touch-icon" href="([^"]+)">')
          .firstMatch(html);
      expect(icon, isNotNull,
          reason: 'no apple-touch-icon: Safari would put a screenshot of the '
              'page on the Home Screen instead of the brand mark');
      // Same-origin is not enough (T-72): `_redirects` answers a missing
      // file with index.html and a 200, which Safari then fails to decode.
      expect(_web(icon!.group(1)!).existsSync(), isTrue,
          reason: 'apple-touch-icon names ${icon.group(1)}, which is not in '
              'app/web/');
    });
  });

  group('the web\u2192app handoff (T-65)', () {
    test('the app answers the host the web channel links to', () {
      // Two languages, one host. A rename on either side leaves the banner
      // pointing at a URI no activity answers — which Chrome renders as a
      // dead page and reports nowhere.
      final manifest = _androidManifest().readAsStringSync();
      expect(manifest,
          contains('android:host="${ChannelHandoffRules.host}"'));
      // And it is the app's OWN scheme, per flavor, never a literal package:
      // the two flavors coexist on the owner's device, and a shared scheme
      // would open a chooser or wake the wrong environment. Matched over the
      // `<data>` element rather than on exact indentation, so reformatting the
      // manifest cannot fail this for the wrong reason.
      final handoffData = RegExp(
              r'<data android:scheme="\$\{applicationId\}"\s+'
              'android:host="${ChannelHandoffRules.host}"\\s*/>')
          .hasMatch(manifest);
      expect(handoffData, isTrue,
          reason: 'the handoff filter must pair the applicationId placeholder '
              'with the host ${ChannelHandoffRules.host}');
    });

    test('all FOUR sources getInstalledRelatedApps needs are present', () {
      // The API resolves to an EMPTY LIST when any of them is missing, which
      // is indistinguishable from "the app is not installed": the banner
      // simply never appears and nothing anywhere says why. This is the only
      // place that can notice.
      final manifest = _androidManifest().readAsStringSync();
      final strings = _androidStrings().readAsStringSync();
      final webManifest =
          jsonDecode(_web('manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      final html = _web('index.html').readAsStringSync();

      // 1. app -> site, named by the manifest and declared in strings.xml.
      expect(manifest, contains('android:name="asset_statements"'));
      expect(manifest, contains('android:resource="@string/asset_statements"'));
      expect(strings, contains('name="asset_statements"'));
      expect(strings, contains('https://${Env.prod.webHostname}'));

      // 2. site -> app, the file Android also verifies App Links against.
      final statements = jsonDecode(
        _web('.well-known/assetlinks.json').readAsStringSync(),
      ) as List<dynamic>;
      expect(
        statements
            .cast<Map<String, dynamic>>()
            .map((s) => (s['target'] as Map<String, dynamic>)['package_name']),
        contains(Env.prod.androidPackage),
      );

      // 3. the web manifest's own pointer at the store app.
      expect(
        (webManifest['related_applications'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((a) => a['id']),
        contains(Env.prod.androidPackage),
      );

      // 4. and the page has to NAME that manifest: the browser reads
      // `related_applications` out of the document's own `<link rel="manifest">`,
      // so a manifest nobody links to is a manifest nobody reads. The first
      // delivery counted three sources and left this one unguarded (it was
      // present, so it never showed as a cause); it is the fourth.
      expect(
        RegExp(r'<link\s+rel="manifest"\s+href="manifest\.json"\s*>')
            .hasMatch(html),
        isTrue,
        reason: 'index.html must link web/manifest.json as the page manifest',
      );
    });

    test('no App Link claims the site itself', () {
      // THE invariant of this item, asserted as an absence. Covering `/` (or
      // prefixing it) does not repair the web channel, it ENDS it: every visit
      // to web.entrelares.app would open the app instead. The handoff is a
      // custom scheme precisely so no https address changes owner.
      for (final filter in _appLinkFilters(_androidManifest().readAsStringSync())) {
        expect(filter, isNot(contains('android:pathPrefix="/"')));
        expect(filter, isNot(contains('android:pathPattern=".*"')));
        expect(
          RegExp(r'android:path="/"').hasMatch(filter),
          isFalse,
          reason: 'an App Link on `/` hands the whole web channel to the app',
        );
      }
    });

    test('the App Links that DO exist are still the two that always did', () {
      // The list is short on purpose and each entry is a URL the app took
      // over from the browser. A new one is a product decision, not a detail.
      final filters =
          _appLinkFilters(_androidManifest().readAsStringSync()).join();
      final paths = RegExp(r'android:path="([^"]+)"')
          .allMatches(filters)
          .map((m) => m.group(1))
          .toSet();
      expect(paths, {'/update-password', '/register'});
    });
  });

  group('the URL strategy', () {
    test('the web channel serves real paths, not `/#/`', () {
      // A hash router would make `_redirects` pointless AND would drop the
      // token of an invitation link, which lives in the PATH — the failure
      // would only show up after the domain move, on a real invitation.
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('usePathUrlStrategy()'));
    });
  });

  group('the deploy workflow', () {
    late String workflow;

    setUp(() => workflow = _workflow().readAsStringSync());

    test('the published build says APP_ENV=prod', () {
      // THE assertion of this file. `flutter build web` has no `--flavor`, so
      // this define is the only thing standing between the production
      // hostname and the QA database.
      final build = RegExp(r'flutter build web --release[^\n]*APP_ENV=prod')
          .hasMatch(workflow);
      expect(build, isTrue,
          reason: 'the deploy must build with --dart-define=APP_ENV=prod');
    });

    test('the published build serves CanvasKit from its own origin', () {
      expect(workflow, contains('--no-web-resources-cdn'));
    });

    // ── T-66 (PR 3): source maps ─────────────────────────────────────────────
    //
    // Two failures live here and neither announces itself. Without the flag the
    // web channel reports crashes nobody can read. With the flag but WITHOUT
    // the strip, every `.map` is published from our own origin, which hands the
    // whole Dart source to anyone who asks — a deploy that looks perfect.

    test('the published build generates source maps', () {
      expect(workflow, contains('--source-maps'),
          reason: 'a dart2js stack without maps names `main.dart.js` offsets; '
              'the issue still groups, it just says nothing');
    });

    test('the maps are STRIPPED before the bundle is published', () {
      final strip = workflow.indexOf("find build/web -name '*.map' -delete");
      final publish = workflow.indexOf('wrangler pages deploy');
      expect(strip, greaterThan(-1),
          reason: 'Sentry has its copy; the CDN must not');
      expect(strip, lessThan(publish),
          reason: 'stripping AFTER the publish would publish the sources and '
              'then tidy the runner, which is the worst of both');
    });

    test('the release the CI names is the one the client sends', () {
      // `CrashReporter.release` builds `entrelares-app@<pubspec version>`. A
      // release that does not match is an upload nobody ever asks for — the
      // maps are there, the events are there, and they never meet.
      expect(workflow, contains(r'entrelares-app@$version'),
          reason: 'the workflow must name the release off the pubspec, the '
              'same way the client does');
      expect(workflow, contains("--url-prefix '~/'"),
          reason: 'the frames carry absolute URLs; `~/` is what makes an '
              'artifact match one');
    });

    test('the upload disarms itself when the token is absent', () {
      expect(workflow, contains("if: env.SENTRY_AUTH_TOKEN != ''"),
          reason: 'an absent secret must skip the step, never paint main red '
              'for ops that has not happened yet — the same shape the '
              'Cloudflare publish uses');
    });

    // ── T-68: a publish that succeeded loudly and delivered nothing ──────────
    //
    // Exit code 0 from `wrangler` is not proof — T-58 is on the board for a
    // gate that said "All tests passed." while running zero tests. These pin
    // the two halves that make the publish PROVABLE: a marker that changes on
    // every commit, and a check that reads it back from the served site.

    test('the bundle is stamped with the commit, BEFORE it is published', () {
      final stamp = workflow.indexOf('build/web/build-id.txt');
      final publish = workflow.indexOf('wrangler pages deploy');
      expect(stamp, greaterThan(-1),
          reason: 'without a per-commit marker there is nothing to read back');
      expect(stamp, lessThan(publish),
          reason: 'a marker written after the upload is not in the bundle');
      expect(workflow,
          contains(r"""printf '%s' "$GITHUB_SHA" > build/web/build-id.txt"""),
          reason: 'the marker is the COMMIT, not the app version: '
              '`version.json` only moves when the pubspec does, so a delivery '
              'that does not bump it (T-69 was a pure rename) would publish '
              'nothing and still match');
    });

    test('the publish is PROVED after the upload, not assumed', () {
      final publish = workflow.indexOf('run: wrangler pages deploy');
      // The `run:` line, not the first mention: the step above it explains the
      // marker and names this script in a comment, so a bare `indexOf` would
      // compare prose against execution and fail on a workflow that is right.
      final smoke = workflow.indexOf('run: bash .github/smoke_web.sh');
      expect(smoke, greaterThan(publish),
          reason: 'the check has to read the site AFTER it was published');
      expect(workflow, contains(r'"https://${{ env.WEB_HOSTNAME }}"'),
          reason: 'the check reads the host the app believes it is served '
              'from, not a string typed twice');
      expect(workflow, contains('WEB_HOSTNAME: ${Env.prod.webHostname}'),
          reason: 'the workflow and `Env.prod.webHostname` must name the same '
              'host — a smoke check pointed at the wrong one is green about '
              'somebody else');
    });

    test('the smoke check cannot pass on a file that is not there', () {
      // THE trap of this half, measured 11/09/2026: `_redirects` ends with the
      // SPA fallback, so a request for a file that does NOT exist comes back
      // 200 with the whole index.html. Any check that reads the status passes
      // over the void — which is the vacuous green in its purest form.
      final script = File('../.github/smoke_web.sh').readAsStringSync();
      expect(_web('_redirects').readAsStringSync(),
          contains('/*  /index.html  200'),
          reason: 'the fallback this test exists about');
      expect(script, contains(r'[ "$served" = "$expected" ]'),
          reason: 'the check compares the BODY to the expected sha');
      // Over the code, for the same reason as the ops-alert guard below: the
      // header of that script names `curl -f` to say why it is NOT used.
      final code = _withoutComments(script);
      expect(code, isNot(contains('curl -f')),
          reason: '`-f` reads the STATUS, and the status is 200 for a file '
              'that is not published at all');
      expect(code, isNot(contains('--fail')),
          reason: 'same as above, spelled the long way');
    });

    // ── T-73: what the EDGE adds after the build ─────────────────────────────
    //
    // Every CSP guard above reads a SOURCE reference. On 14/09/2026 Cloudflare
    // Web Analytics was appending a beacon to every served HTML page — a script
    // the CSP blocked on every load, and one no file in this repo names, so no
    // source guard could ever have seen it. Only the served page can.

    test('the served page is checked against the SERVED CSP, after the proof',
        () {
      final yaml = _withoutComments(workflow);
      final proof = yaml.indexOf('run: bash .github/smoke_web.sh');
      final guard = yaml.indexOf(
          r'run: bash .github/smoke_web_csp.sh "https://${{ env.WEB_HOSTNAME }}"');
      expect(guard, greaterThan(-1),
          reason: 'the guard reads the host the app believes it is served from');
      expect(guard, greaterThan(proof),
          reason: 'what the page carries only means something once THIS commit '
              'is what is being served');
      final step = yaml.substring(yaml.lastIndexOf('- name:', guard), guard);
      expect(step, contains("if: env.CLOUDFLARE_API_TOKEN != ''"),
          reason: 'self-disarming exactly like the publish it follows');
    });

    test('the guard asks as a browser does, and cannot pass over nothing', () {
      final code =
          _withoutComments(File('../.github/smoke_web_csp.sh').readAsStringSync());
      expect(code, contains("-H 'Accept: text/html"),
          reason: 'measured: the edge injects ONLY when the request asks for '
              'HTML — a plain curl came back clean over the same URL');
      expect(code.toLowerCase(), contains('content-security-policy:'),
          reason: 'the policy compared is the header on the wire, not '
              '`_headers` — a check against the source agrees with itself');
      expect(code, isNot(contains('_headers')), reason: 'same as above');
      expect(code, contains(r'flutter_bootstrap\.js'),
          reason: 'T-58: a page without even our own bootstrap script is a page '
              'nobody checked, and it must go red, not green');
      expect(code, contains('set -f'),
          reason: '`https://*.host` is a CSP source; unquoted, bash would glob '
              "it against the runner's disk");
      expect(_web('index.html').readAsStringSync(),
          contains('src="flutter_bootstrap.js"'),
          reason: 'the marker the guard requires must be in the page it reads');
    });
    // ── The docs-only skip, and the two assumptions holding it up ────────────
    //
    // Since 29/08/2026 a change touching ONLY markdown runs no jobs at all
    // (`paths-ignore`). The saving is `db-gate`'s repo-wide serialized queue and
    // `web-e2e`'s throwaway family on the shared dev project, neither of which
    // proves anything about a paragraph. Both tests below exist because the
    // filter is only safe while its premises hold, and a premise nobody checks
    // is how a gate quietly stops gating.

    test('a markdown-only change skips the run', () {
      // Pinned so the filter cannot be dropped by accident: without it, every
      // backlog edit takes a slot in a queue that evicts a third claimant.
      expect(workflow, contains("paths-ignore: ['**/*.md']"),
          reason: 'docs-only changes must not spend the gate');
    });

    test('no suite reads a markdown file', () {
      // The premise of the filter. The moment a test asserts something about a
      // `.md` — the runbook, a backlog record — that test silently stops running
      // for exactly the changes it exists to watch: a vacuous green, which is
      // what T-58 is about. If this fails, either drop the `.md` read or narrow
      // `paths-ignore` to exclude the file being read.
      final roots = [
        Directory('test'),
        Directory('../packages/entrelares_core/test'),
        Directory('../packages/entrelares_db_gate/test'),
        Directory('integration_test'),
      ];
      final offenders = <String>[];
      for (final root in roots) {
        if (!root.existsSync()) continue;
        for (final file in root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            // This file itself, which names the extension in order to LOOK for
            // it — it never reads a `.md`'s contents, and there are none under
            // `web/` for it to read.
            .where((f) => !f.path.endsWith('web_channel_test.dart'))) {
          // A `.md` inside a STRING LITERAL is the only way a suite can reach
          // one; mentions in prose are free and must not fail this, which is
          // why the comment lines come out first.
          final code = file
              .readAsLinesSync()
              .where((line) => !line.trimLeft().startsWith('//'))
              .join('\n');
          if (RegExp(r'''['"][^'"\n]*\.md['"]''').hasMatch(code)) {
            offenders.add(file.path);
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'these suites read a .md, which paths-ignore would stop '
              'running: ${offenders.join(', ')}');
    });

    test('nothing published on the web channel is markdown', () {
      // The other premise. Everything under `web/` is copied VERBATIM into the
      // build, so a `.md` there would be user-facing — and a change to it would
      // skip the deploy that should have published it.
      final web = Directory('web');
      final markdown = web
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .map((f) => f.path)
          .toList();
      expect(markdown, isEmpty,
          reason: 'a .md under web/ is published, so it cannot be treated as '
              'documentation by paths-ignore: ${markdown.join(', ')}');
    });

    test('publishing waits for EVERY gate, and only from main', () {
      final job = workflow.substring(workflow.indexOf('  deploy-web:'));
      // The gate stopped being a single job on 24/08/2026, when the database
      // suite moved into this repo: `verify` runs the Flutter lanes and
      // `db-gate` runs the 221 RLS/RPC/trigger tests. Publishing behind only one
      // of them would ship the web channel with the other half unchecked — so
      // this asserts each dependency BY NAME instead of matching the literal
      // `needs:` line, which is what broke when the second job arrived.
      final needs = RegExp(r'needs:\s*(\[[^\]]*\]|\S+)').firstMatch(job)?.group(1);
      expect(needs, isNotNull, reason: 'deploy-web must declare what it waits for');
      expect(needs, contains('verify'));
      expect(needs, contains('db-gate'));
      // T-29's order, which survived the database moving into this repo:
      // migrations → functions → app. Publishing before `db-prod` would let the
      // channel serve an app whose schema failed to apply.
      expect(needs, contains('db-prod'),
          reason: 'the web channel must publish AFTER the production schema');
      // The flow gate (24/08/2026) — the role Playwright played for the old
      // repo's promotion. Dropping this edge turns a gate back into a report.
      expect(needs, contains('web-e2e'),
          reason: 'a broken two-user flow must stop the channel, not reach users');
      expect(job, contains("github.ref_name == 'main'"));
      expect(job, contains('wrangler pages deploy build/web'));
    });

    // 15/09/2026 (F-63, PR #187): a squash-merge produced no run at all, and
    // with the publish gated on `push` alone nothing could republish `main`
    // short of another merge. The manual dispatch is the way back — for the
    // whole publish chain, or a dispatch would pass the gates, skip
    // `db-prod`, and leave `deploy-web` waiting on a job that never ran.
    test('a manual dispatch on main republishes through the same chain', () {
      // Line-ending agnostic: a Windows checkout reads the file with CRLF.
      final lines = workflow.split(RegExp(r'\r?\n'));
      String jobIf(String name) {
        final start = lines.indexOf('  $name:');
        expect(start, isNot(-1), reason: 'job $name exists');
        final ifLine =
            lines.indexWhere((line) => line.startsWith('    if:'), start);
        final condition = StringBuffer(lines[ifLine]);
        for (var i = ifLine + 1; lines[i].startsWith('      '); i++) {
          condition.write(' ${lines[i].trim()}');
        }
        return condition.toString();
      }

      for (final name in ['db-prod', 'deploy-web', 'play-internal', 'ops-alert']) {
        final condition = jobIf(name);
        expect(condition, contains("github.event_name == 'push'"),
            reason: name);
        expect(condition, contains("github.event_name == 'workflow_dispatch'"),
            reason: '$name must also run on a manual dispatch');
        expect(condition, contains("github.ref_name == 'main'"),
            reason: '$name must never publish from another ref');
      }
    });
  });

  // ── T-58 — the flow gate has to PROVE it ran ──────────────────────────────
  //
  // `flutter drive` on web prints "All tests passed." and exits 0 over a suite
  // whose `setUpAll` threw, because the binding completes `allTestsPassed`
  // with "no failure recorded" and an empty run records none. The gate blocked
  // the web publish for five days on that green (25/08/2026). What makes it
  // unable to lie now is three pieces that have to agree — the suites report,
  // the driver judges, the workflow demands a count — and these tests keep
  // them agreeing in the cheap lane, before the expensive one runs.
  group('the flow gate proves it ran (T-58)', () {
    late String workflow;
    late String driver;
    late List<File> suites;

    String code(File file) => file
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    setUp(() {
      workflow = _withoutComments(_workflow().readAsStringSync());
      driver = File('test_driver/integration_test.dart').readAsStringSync();
      suites = Directory('integration_test')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(suites, isNotEmpty, reason: 'the lane has suites to drive');
    });

    test('the driver is ours, and it judges before it exits', () {
      // The stock `integrationDriver()` is the one that says "All tests
      // passed." over nothing. Over the code, not the header that names it to
      // say why it is gone.
      final body = code(File('test_driver/integration_test.dart'));
      expect(body, isNot(contains('integrationDriver(')),
          reason: 'the stock driver cannot tell an empty run from a full one');
      expect(body, contains('judge('),
          reason: 'the verdict is what turns a report into an exit code');
      expect(body, contains('exit(verdict.passed ? 0 : 1)'),
          reason: 'the exit code IS the gate; a verdict that is only printed '
              'is a report, not a guard');
      expect(body, contains('File(proofFile)'),
          reason: 'the driver writes the proof where the workflow reads it — '
              'through the shared constant, so the two cannot drift');
      expect(proofFile, 'build/e2e_proof.json',
          reason: 'the workflow spells this path in its `rm -f` and its '
              '`jq`; the tests below match it there');
      expect(driver, contains("import 'e2e_proof.dart'"));
    });

    test('the suite and the driver spell the report keys the same way', () {
      // The suite cannot import the driver's constants: on the web
      // `flutter drive` compiles `integration_test/` as the application root
      // and `../test_driver/…` is not there (measured 12/09/2026). So the two
      // spellings are a mirror, and a mirror nobody checks rots quietly —
      // into a driver that reads `executed` from a suite that wrote
      // something else, which is the "report without the list" red.
      final suiteSide = File('integration_test/e2e_proof.dart').readAsStringSync();
      String spelled(String name) =>
          RegExp("const $name = '([^']+)';").firstMatch(suiteSide)?.group(1) ??
          '<missing>';
      expect(spelled('executedKey'), executedKey);
      expect(spelled('failedKey'), failedKey);
      expect(spelled('setUpAllKey'), setUpAllKey,
          reason: 'T-71: the setUpAll report rides the same mirror — a driver '
              'reading a key the suite never writes would name a "reported '
              'nothing" red as before, with the cause lost again');
    });

    test('every suite sets up through the reporting wrapper, never bare (T-71)',
        () {
      // A `setUpAll` that throws outside `provedSetUpAll` prints its exception
      // to the browser console and nowhere else — `-d web-server` has no
      // DWDS — so the driver can only say "reported nothing". Main run
      // 34731668538 attempt 1 (13/09/2026) is the red nobody could root-cause.
      // Over the code, not the comments that explain this.
      for (final suite in suites) {
        final body = code(suite);
        expect(body, isNot(matches(RegExp(r'(?<![A-Za-z_])setUpAll\('))),
            reason: '${suite.path} registers a bare setUpAll; use '
                'provedSetUpAll(binding, …) so its window and its error '
                'reach the proof');
        expect(body, contains('provedSetUpAll(binding,'),
            reason: '${suite.path} has no setUpAll at all — every suite '
                'creates its throwaway family there, and the lane reads the '
                'window from its report');
      }
    });

    test('every suite installs the proof, before any test is declared', () {
      for (final suite in suites) {
        final body = code(suite);
        final install = body.indexOf('proveExecution(');
        expect(install, greaterThan(-1),
            reason: '${suite.path} never reports what ran — the web driver '
                'would be red on "the suite reported nothing", which is '
                'right, but this lane says so for free');
        expect(install, lessThan(body.indexOf('testWidgets(')),
            reason: '${suite.path}: a tearDown registered after a test does '
                'not run for it');
      }
    });

    test('no suite skips a pack by returning early', () {
      // A body that returns on its first line reaches `runTest` and is counted
      // as executed — the vacuous green in miniature. `skip:` is the way.
      for (final suite in suites) {
        expect(code(suite), isNot(contains("pack == 'p0') return")),
            reason: '${suite.path} must skip full-pack tests with `skip:`, '
                'never with an early return');
      }
    });

    test('the workflow demands, per pack, exactly what each suite declares',
        () {
      // The spec line: `<target>:<p0>:<full>` for every suite. Read from the
      // code so the comment explaining it is not what gets matched.
      final job = workflow.substring(workflow.indexOf('  web-e2e:'));
      final specLine =
          RegExp(r'for spec in ([^;]+); do').firstMatch(job)?.group(1);
      expect(specLine, isNotNull,
          reason: 'the web-e2e step must loop over target:p0:full specs');
      final specs = <String, (int, int)>{};
      for (final spec in specLine!.trim().split(RegExp(r'\s+'))) {
        final parts = spec.split(':');
        expect(parts, hasLength(3), reason: 'malformed spec: $spec');
        specs[parts[0]] = (int.parse(parts[1]), int.parse(parts[2]));
      }

      final declared = <String, (int, int)>{};
      for (final suite in suites) {
        final body = code(suite);
        final total = 'testWidgets('.allMatches(body).length;
        final fullOnly = "skip: pack == 'p0'".allMatches(body).length;
        final name = suite.uri.pathSegments.last.replaceAll('.dart', '');
        declared[name] = (total - fullOnly, total);
      }

      expect(specs.keys.toSet(), declared.keys.toSet(),
          reason: 'every suite under integration_test/ is driven, and every '
              'driven target exists — a suite the workflow does not name is a '
              'suite nothing runs');
      for (final entry in declared.entries) {
        expect(specs[entry.key], entry.value,
            reason: '${entry.key}: the workflow demands ${specs[entry.key]} '
                '(p0, full) and the file declares ${entry.value}. A test '
                'added or removed changes verify.yml in the same delivery');
      }
      expect(declared.values.every((v) => v.$1 >= 1), isTrue,
          reason: 'a suite with no p0 test is not in the gate at all');
    });

    test('the expectation reaches the driver, and the proof is fresh', () {
      final job = workflow.substring(workflow.indexOf('  web-e2e:'));
      final drive = job.indexOf('flutter drive');
      expect(drive, greaterThan(-1));
      expect(job, contains('$expectedTestsVariable="\$expected" flutter drive'),
          reason: 'a drive without the variable accepts any positive count, '
              'which is fine at a keyboard and not in the gate');
      final removal = job.indexOf('rm -f $proofFile');
      expect(removal, greaterThan(-1),
          reason: 'a stale proof from the previous target must never stand in '
              'for a missing one');
      expect(removal, lessThan(drive));
      expect(job.indexOf(proofFile, drive), greaterThan(drive),
          reason: 'the workflow reads the proof AFTER the drive, for the '
              'summary — the names that ran are the evidence a human reads');
    });
  });

  // ── T-68 — a red `main` reaching a human ──────────────────────────────────
  //
  // The e-mail GitHub already sends arrives in 20 seconds (measured on the
  // 10/09/2026 incident); what it cannot do is stand out among the routine PR
  // failures. So the alert goes where "production is breaking" already means
  // something — and, above all, NOT through the product's own rails.
  group('the ops alert', () {
    late String workflow;
    late String script;

    setUp(() {
      workflow = _workflow().readAsStringSync();
      script = File('../.github/ops_alert.sh').readAsStringSync();
    });

    test('it alerts the PRODUCTION Sentry project, and the DSN cannot drift',
        () {
      expect(workflow, contains('SENTRY_DSN_PROD: ${Env.prod.sentryDsn}'),
          reason: 'the dev project\'s alert rule is DISABLED by decision '
              '(runbook §13.5), so an ops alert sent there wakes nobody');
      expect(workflow, isNot(contains(Env.dev.sentryDsn)),
          reason: 'the QA stream must never carry a production ops alert');
    });

    test('the alarm fires on a FAILED job, never on an evicted one', () {
      // Read the job's own condition, with the comments stripped: the comment
      // above it quotes the condition to explain it, and the first version of
      // this test matched THAT — it passed on a workflow whose `if:` had been
      // replaced, which is the vacuous green in miniature.
      final yaml = _withoutComments(workflow);
      final job = yaml.substring(yaml.indexOf('  ops-alert:'));
      final condition = job.substring(0, job.indexOf('needs:'));

      expect(condition, contains("contains(needs.*.result, 'failure')"),
          reason: 'the alarm names the result it fires on. A cancelled '
              '`db-gate` is usually an EVICTION from its depth-1 queue — a '
              'documented false alarm, and an alarm that cries wolf is how the '
              'next real one gets ignored');
      expect(condition, isNot(contains('cancelled')),
          reason: 'a cancelled job is not an incident');
      expect(condition, contains("github.ref_name == 'main'"),
          reason: 'a red PR is the normal working loop; only a red `main` '
              'means production stopped receiving what was merged');
    });

    test('the alert path touches none of the product rails', () {
      // The card's explicit trap. Resend is one shared account capped at
      // 100/day with `send-auth-email` behind it (§5), and push hangs off an
      // AFTER INSERT trigger on `notifications`, whose rows are family data
      // (F-09). An ops alert is neither.
      // Over the CODE, not the comments: the header of that file names both
      // rails precisely to say why they are absent, and a guard that trips on
      // its own explanation teaches people to delete the explanation.
      final code = _withoutComments(script).toLowerCase();
      for (final rail in ['resend', 'send-auth-email', 'send-push']) {
        expect(code, isNot(contains(rail)),
            reason: '`$rail` is a PRODUCT rail; ops signal must not share it');
      }
      expect(RegExp(r'\bnotifications\b').hasMatch(code), isFalse,
          reason: 'the `notifications` table is family data, not an ops log');
    });

    test('the alert groups per COMMIT, so a second incident still alerts', () {
      // Grouping by job alone would land the next failure inside an existing
      // issue, and an open-but-unresolved Sentry issue fires no new-issue
      // alert — a silent alarm, which is this item's own defect reintroduced.
      expect(script, contains(r'fingerprint: [ "ci", "verify", $jobs, $sha ]'),
          reason: 'the sha in the fingerprint is what keeps the alarm audible');
    });

    test('a red AFTER the proof is not reported as a publish that never landed',
        () {
      // T-73 put a check after `smoke_web.sh`. Its red fails `deploy-web` like
      // a broken publish does, and every message of this job used to say "não
      // publicou" — an alarm lying about its own incident sends the reader to
      // the wrong console.
      final yaml = _withoutComments(workflow);
      expect(yaml, contains(r'published: ${{ steps.proof.outputs.published }}'),
          reason: '`deploy-web` exports whether the proof passed');
      expect(yaml,
          contains(r'PUBLISHED: ${{ needs.deploy-web.outputs.published }}'),
          reason: '`ops-alert` reads it');
      expect(
          _withoutComments(File('../.github/smoke_web.sh').readAsStringSync()),
          contains(r'echo "published=true" >> "$GITHUB_OUTPUT"'),
          reason: 'only the proof itself may say the commit is served');
      expect(RegExp(r'"\$GITHUB_SHA" \\\r?\n\s+"\$PUBLISHED"').hasMatch(yaml),
          isTrue,
          reason: 'the Sentry alert gets the same answer the summary does');
      final code = _withoutComments(script);
      expect(code, contains(r'if [ "$published" = "true" ]; then'));
      expect(code, contains('publicou, mas serve script que a CSP recusa'));
      expect(code, contains('não publicou'),
          reason: 'the original message still stands for the original case');
    });

  });

  // T-66 (PR 2) — the EIGHTH mirror. `index.html` carries a boot watcher
  // written in JavaScript because nothing else is running yet, which makes it
  // the same kind of deliberate duplication as `firebase-messaging-sw.js`: the
  // values live in `env.dart` for Dart and are spelled again, by hand, for the
  // browser. Nothing at build time compares them — a wrong DSN here reports a
  // production boot failure into the QA project, and a renamed flag leaves the
  // script armed forever, doubling every Dart crash. Both fail with no error.
  group('the pre-Flutter boot watcher (T-66)', () {
    late String html;

    setUp(() => html = _web('index.html').readAsStringSync());

    test('carries BOTH DSNs, character for character with env.dart', () {
      expect(html, contains(Env.prod.sentryDsn),
          reason: 'the production DSN must be the one `Env.prod` names');
      expect(html, contains(Env.dev.sentryDsn),
          reason: 'anything that is not the production host reports to dev');
    });

    test('names the production host exactly as Env.prod does', () {
      expect(html, contains("var PROD_HOST = '${Env.prod.webHostname}';"),
          reason: 'this string is the ONLY thing deciding which project a boot '
              'failure lands in; drift sends production events to QA');
    });

    test('reads the same flag Dart writes', () {
      final dart = File('lib/services/boot_handoff_web.dart').readAsStringSync();
      final flag = RegExp(r"_bootedFlag = '([^']+)'").firstMatch(dart)?.group(1);
      expect(flag, isNotNull,
          reason: 'boot_handoff_web.dart no longer declares the flag in the '
              'shape this mirror reads');
      expect(html, contains('window.$flag === true'),
          reason: 'a renamed flag never stands the boot script down: every '
              'Dart crash would then be reported twice, in two shapes');
    });

    test('is armed ABOVE the loader it is there to watch', () {
      final watcher = html.indexOf('pre-flutter-boot');
      // The TAG, not the word: the comment above the watcher names the
      // loader too, and matching that would compare the watcher with its own
      // documentation.
      final loader = html.indexOf('<script src="flutter_bootstrap.js"');
      expect(watcher, greaterThan(-1));
      expect(watcher, lessThan(loader),
          reason: 'a watcher installed after the loader cannot see the loader '
              'fail, which is the only failure it exists for');
    });

    test('posts the same CORS-simple shape as the Dart transport', () {
      expect(html, contains('sentry_key='));
      expect(html, contains("'Content-Type': 'text/plain;charset=UTF-8'"));
      expect(html, isNot(contains('X-Sentry-Auth')),
          reason: 'a custom header turns the POST into a preflighted request, '
              'which is how this channel would go quiet without failing');
    });
  });

}
