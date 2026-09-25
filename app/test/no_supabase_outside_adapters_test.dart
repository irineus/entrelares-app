// Fulcrum 04.1 — the definition of the PORT. The app talks to its backend
// through a handful of adapter files, and only those; every screen, widget and
// service above them speaks the app's own types. That is what made Fulcrum
// 03.4 (moving the whole app behind `api.entrelares.app`) a change to
// `env.dart` and nothing else — and what will let a later backend swap stay
// a change to these files. Without a gate the client leaks back, one
// convenient `Supabase.instance.client.from(…)` in a screen at a time.
//
// Three doors are watched, because an import gate alone misses the other two
// (the lesson Desmalha paid for with a raw REST call):
//   1. importing the Supabase client packages;
//   2. calling a backend path (`/auth/v1`, `/rest/v1`, …) by hand;
//   3. reading the backend's base URL or key from `Env`.
//
// Shrinking a list below is progress. Growing one needs a reason in the PR —
// and the file named here, so the reviewer sees the port get wider.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that may import the Supabase client (door 1). Measured 25/09/2026.
const _clientAdapters = {
  'main.dart', // Supabase.initialize, the auth listener, the sign-in doors
  'services/session_gate.dart', // the session lifecycle
  'services/supabase_custody_data_source.dart', // the data port
  'services/support_service.dart', // the anonymous support form (F-68)
};

/// Files that may call a backend path by hand (door 2).
const _rawPathAdapters = {
  // GoTrue's public settings: whether the Google button exists (F-57).
  'services/auth_providers.dart',
};

/// Files that may read the backend's base URL or key (door 3).
const _endpointReaders = {
  'env.dart', // where they are defined
  'main.dart', // Supabase.initialize
  'services/auth_providers.dart', // the raw settings call above
};

final _clientImport = RegExp(
    r"""^\s*(import|export)\s+['"]package:(supabase_flutter|supabase|gotrue|postgrest|realtime_client|functions_client|storage_client)/""");
final _backendPath = RegExp(r'/(auth|rest|functions|storage|realtime)/v1\b');
final _endpoint = RegExp(r'\bsupabase(Url|Key)\b');

/// `lib/`-relative path with forward slashes.
String _rel(File f) =>
    f.path.replaceAll('\\', '/').split('lib/').skip(1).join('lib/');

/// The line without its comment. A `//` preceded by whitespace (or opening
/// the line) starts a comment; the `//` inside `https://` does not.
String _code(String line) {
  if (line.trimLeft().startsWith('//')) return '';
  return line.replaceFirst(RegExp(r'\s//.*$'), '');
}

Map<String, List<String>> _scan(RegExp pattern) {
  final hits = <String, List<String>>{};
  for (final file in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(_code(lines[i]))) {
        hits.putIfAbsent(_rel(file), () => []).add('${i + 1}');
      }
    }
  }
  return hits;
}

void _gate(String door, RegExp pattern, Set<String> allowed) {
  final hits = _scan(pattern);
  final outside = {
    for (final e in hits.entries)
      if (!allowed.contains(e.key)) e.key: e.value,
  };
  expect(outside, isEmpty,
      reason: '$door outside the adapters: $outside. Go through an adapter '
          '(or, if this file IS a new adapter, add it to the list with the '
          'reason in the PR).');
  // The list is the TRUE minimum: an entry that no longer needs the door
  // must leave, or the port stays wider than the code.
  final unused = allowed.difference(hits.keys.toSet());
  expect(unused, isEmpty,
      reason: '$door: these files are listed but no longer need it — shrink '
          'the list: $unused');
}

void main() {
  test('only the adapters import the Supabase client', () {
    _gate('Supabase client import', _clientImport, _clientAdapters);
  });

  test('only the adapters call a backend path by hand', () {
    _gate('raw backend path', _backendPath, _rawPathAdapters);
  });

  test("only the adapters read the backend's base URL or key", () {
    _gate('Env.supabaseUrl / supabaseKey', _endpoint, _endpointReaders);
  });

  test('the scanner sees what it gates (it must not pass on empty)', () {
    expect(_clientImport.hasMatch("import 'package:supabase_flutter/supabase_flutter.dart';"), isTrue);
    expect(_backendPath.hasMatch("'\$base/rest/v1/profiles'"), isTrue);
    expect(_code("final u = 'https://x/rest/v1'; // /auth/v1 note"),
        "final u = 'https://x/rest/v1';");
    expect(_code('  /// GET /auth/v1/authorize answers 410'), isEmpty);
    expect(_scan(_clientImport).keys, contains('main.dart'));
  });
}
