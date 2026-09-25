// Fulcrum 03.4 — the app talks to the Fulcrum gateway, never to a Supabase
// project directly. The gate the Fulcrum onboarding guide (§4) specifies for
// every client: PRODUCTION never points at `*.supabase.co`. Switching the
// backend behind the gateway is then a gateway variable, not an app release —
// and an app release is exactly what a build that still names the project
// would force on the day of the switch.
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/env.dart';

void main() {
  test('production points at the gateway, never at *.supabase.co', () {
    final url = Uri.parse(Env.prod.supabaseUrl);
    expect(url.host, isNot(endsWith('supabase.co')));
    expect(url.scheme, 'https');
    expect(url.host, 'api.entrelares.app');
    // The gateway routes by path prefix (`/rest/v1`, `/auth/v1`, …) from the
    // root; a base path would push every request off its prefix.
    expect(url.path, anyOf('', '/'));
  });

  test('dev points at the dev gateway, so QA exercises the same door', () {
    final url = Uri.parse(Env.dev.supabaseUrl);
    expect(url.host, isNot(endsWith('supabase.co')));
    expect(url.host, 'api-dev.entrelares.app');
  });

  test('each flavour ships its OWN tenant key, and no Supabase key', () {
    // One key per ENV (Fulcrum, 09/09/2026): a dev build must not be able to
    // open the production gateway with the key it ships.
    expect(Env.dev.supabaseKey, isNot(Env.prod.supabaseKey));
    for (final env in const [Env.dev, Env.prod]) {
      // The tenant key is generated (`openssl rand -hex 32`), never borrowed
      // from the target — a publishable key or a legacy anon JWT here would
      // couple the app to the project the gateway exists to hide.
      expect(env.supabaseKey, matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '${env.name}: the gateway\'s TENANT_PUBLIC_KEY');
      expect(env.supabaseKey, isNot(startsWith('sb_')));
      expect(env.supabaseKey, isNot(startsWith('eyJ')));
    }
  });

  test('the session keeps the storage name it already has on devices', () {
    // supabase_flutter names the saved session after the URL's first label.
    // Left to that default the move to `api.…` would sign every family out
    // on the update; the old per-project names are pinned instead.
    expect(Env.prod.sessionStorageKey, 'sb-jptqbwfziyzlhlmoekzu-auth-token');
    expect(Env.dev.sessionStorageKey, 'sb-buroanotfjcgvbfmacuh-auth-token');
  });
}
