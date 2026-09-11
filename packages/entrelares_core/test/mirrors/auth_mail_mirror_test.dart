/// U-13 — the app WRITES the session's language into the password-reset
/// `redirect_to`, and the `send-auth-email` Edge Function READS it back out.
///
/// The two halves are a Dart constant and a Deno constant, in different
/// languages, in different deployment units, and nothing in either toolchain
/// connects them. Rename one and the other keeps compiling, keeps deploying,
/// keeps passing every other test — and every locked-out English reader
/// silently starts receiving a Portuguese password-reset e-mail. The failure is
/// invisible precisely because the fallback is a perfectly valid language.
///
/// Same reasoning as the role-catalog and date-format mirrors: where a value
/// must be duplicated across the Dart/Deno boundary, the duplication gets a
/// suite that reads BOTH files, so drift is a red gate rather than a slow leak.
///
/// Ported from `entrelares-app` `Entrelares.Tests/AuthMailMirrorTests.cs`
/// (T-56, 24/08/2026). One deliberate strengthening over the original, which
/// pinned a single named method: this reads EVERY `resetPasswordForEmail` call
/// site under `app/lib/` and requires each to go through
/// `DeepLinkUrls.updatePasswordFor`. The app has two of them — the anonymous
/// "I forgot mine" route and the profile screen's admin-assisted reset — and
/// the original's shape would have watched only one.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

/// Value of an exported string constant in the functions' shared i18n module —
/// the Deno side of the mirror.
String _readTsConstant(String name) {
  final match =
      RegExp('export\\s+const\\s+${RegExp.escape(name)}\\s*=\\s*"([^"]*)"')
          .firstMatch(i18nSource());

  expect(match, isNotNull,
      reason: '`export const $name` not found in _shared/i18n.ts.');
  return match!.group(1)!;
}

/// Every `.dart` file under the app's `lib/`, by `lib/`-relative path.
///
/// Keys are always slash-separated: `Directory.listSync` hands back the
/// platform's own separator, so on Windows the same file would arrive as
/// `services\custody.dart` and miss every assertion written against the paths
/// Linux CI produces.
Map<String, String> _appSources() {
  final root = '${repoRoot().path}/app/lib';
  final dir = Directory(root);
  expect(dir.existsSync(), isTrue, reason: 'App sources not found at $root.');

  return {
    for (final f in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      f.path.replaceAll(r'\', '/').substring(root.length + 1):
          f.readAsStringSync(),
  };
}

void main() {
  // The key the client writes is the key the function looks for.
  test('the language query param is the same on both sides', () {
    expect(AuthMail.languageQueryParam, _readTsConstant('LANGUAGE_QUERY_PARAM'));
  });

  // A reader that matched nothing would make the gate above vacuous.
  test('the TypeScript reader finds a known constant', () {
    expect(_readTsConstant('LANGUAGE_QUERY_PARAM'), 'lang');
  });

  // The constant agreeing is worth nothing if the redirect went back to a bare
  // `/update-password`: the function would read an absent key, fall through,
  // and be right about the language only by luck.
  test('the recovery redirect is built from the shared key and the code', () {
    final source = _appSources()['deep_link_urls.dart'];
    expect(source, isNotNull,
        reason: 'deep_link_urls.dart is gone — where does the redirect come '
            'from now?');

    final builder =
        RegExp(r'updatePasswordFor\([^)]*\)\s*=>(.*?);', dotAll: true)
            .firstMatch(source!);
    expect(builder, isNotNull,
        reason: 'DeepLinkUrls.updatePasswordFor no longer exists.');
    expect(builder!.group(1)!, contains('AuthMail.languageQueryParam'));
    expect(builder.group(1)!, contains('.code'));
  });

  // ...and every caller actually uses it. This is the half that rots first: a
  // new reset entry point written from the surrounding pattern would pass the
  // plain constant and lose the language with nothing failing.
  test('every reset call site sends the language-carrying redirect', () {
    final offenders = <String>[];

    _appSources().forEach((path, source) {
      for (final call
          in RegExp(r'resetPasswordForEmail\((.*?)\);', dotAll: true)
              .allMatches(source)) {
        if (!call.group(1)!.contains('updatePasswordFor')) {
          offenders.add('$path: resetPasswordForEmail(${call.group(1)})');
        }
      }
    });

    expect(offenders, isEmpty,
        reason: 'These reset call sites send a redirect with no language, so '
            'the e-mail falls back for anyone whose profile has not declared '
            'one:\n  ${offenders.join("\n  ")}');
  });

  // And the scanner is not passing by matching nothing: the app HAS reset call
  // sites, and if a refactor removed them all this suite would go quiet while
  // still green.
  test('the scanner actually finds the known reset call sites', () {
    final callers = _appSources().entries
        .where((e) => e.value.contains('resetPasswordForEmail('))
        .map((e) => e.key)
        .toList();

    expect(callers, contains('main.dart'));
    expect(callers, contains('services/supabase_custody_data_source.dart'));
  });
}
