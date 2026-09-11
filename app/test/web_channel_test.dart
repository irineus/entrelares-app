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

import 'package:entrelares_app/deep_link_urls.dart';
import 'package:entrelares_app/env.dart';
import 'package:flutter_test/flutter_test.dart';

File _web(String name) => File('web/$name');
File _workflow() => File('../.github/workflows/verify.yml');
File _androidManifest() =>
    File('android/app/src/main/AndroidManifest.xml');

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
      // What the app talks to — Supabase (REST + Realtime) and the collector.
      expect(csp, contains('https://*.supabase.co'));
      expect(csp, contains('wss://*.supabase.co'));
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
    // gate instead of a silent outage. Asserted against `Env.prod` because
    // that is the build `deploy-web` publishes.
    test('connect-src covers the Supabase host the prod build names', () {
      final host = Uri.parse(Env.prod.supabaseUrl).host;
      final sources = _sources(_csp(headers)!, 'connect-src');

      for (final scheme in const ['https', 'wss']) {
        expect(
          sources.any((s) => _covers(s, scheme, host)),
          isTrue,
          reason: 'the CSP must allow $scheme://$host — `Env.prod.supabaseUrl` '
              'names it, so a build that cannot reach it is a dead app. '
              'Move the host and `_headers` moves with it.',
        );
      }
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
