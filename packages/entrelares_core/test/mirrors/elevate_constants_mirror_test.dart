/// S-21 — the sudo gate's numbers are declared ONCE, in
/// `supabase/functions/elevate/index.ts`, and copied here so the prompt can
/// talk about them without a round-trip. This suite reads that file and fails
/// when the copies drift.
///
/// Why it earns its place, in the same terms as the other five mirrors: Deno
/// cannot call into Dart, so the duplication is deliberate — and every way it
/// can rot is SILENT. Change the code to eight digits on the server and the
/// client keeps refusing at six, so the field never accepts what the e-mail
/// says; stretch the TTL and the sheet keeps promising ten minutes; shorten the
/// resend interval and the prompt keeps a button disabled that the server would
/// have answered. In each case both halves compile, both deploy, and the person
/// who cannot get past the gate is someone who had no password to begin with —
/// the exact audience this item exists for, and the one least able to work
/// around it.
///
/// It also pins the one number that was already duplicated before this item and
/// had nothing watching it: the elevation window itself.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

const _elevatePath = 'supabase/functions/elevate/index.ts';

/// The value of a `const NAME = <number>` declaration in the function.
int _readTsNumber(String name) {
  final match =
      RegExp('const\\s+${RegExp.escape(name)}\\s*=\\s*(\\d+)\\s*;')
          .firstMatch(repoFile(_elevatePath));

  expect(match, isNotNull,
      reason: '`const $name = <number>` not found in $_elevatePath. If it was '
          'renamed, rename it here too — these numbers have exactly one home.');
  return int.parse(match!.group(1)!);
}

void main() {
  test('the code length is the same on both sides', () {
    expect(SudoRules.codeLength, _readTsNumber('CODE_LENGTH'));
  });

  test('the code TTL is the same on both sides', () {
    expect(SudoRules.codeTtl.inMinutes, _readTsNumber('CODE_TTL_MINUTES'));
  });

  test('the resend interval is the same on both sides', () {
    expect(SudoRules.codeResendInterval.inSeconds,
        _readTsNumber('CODE_MIN_INTERVAL_SECONDS'));
  });

  test('the elevation window is the same on both sides', () {
    // Older than S-21 and never checked: `SudoRules.serverWindow` is the
    // fallback used when a response carries no `elevated_until`, so a drift
    // here would only show up as a window the client believes in for longer
    // than the server honours it — an elevation that "expires" mid-action.
    expect(SudoRules.serverWindow.inMinutes, _readTsNumber('ELEVATION_MINUTES'));
  });

  test('the reader actually finds numbers, not zero-by-default', () {
    // Without this the four assertions above would all pass against a file that
    // no longer declares anything, if `_readTsNumber` ever learned to shrug.
    expect(_readTsNumber('CODE_LENGTH'), greaterThan(0));
    expect(_readTsNumber('ELEVATION_MINUTES'), greaterThan(0));
  });

  test('the function still passes these numbers to the RPCs', () {
    // The constants agreeing is worth nothing if the function stopped using
    // them — a literal typed into the `rpc(...)` call would leave these four
    // tests green while the database enforced something else entirely.
    final source = repoFile(_elevatePath);
    expect(source, contains('p_ttl_seconds: CODE_TTL_MINUTES * 60'));
    expect(source, contains('p_min_interval_seconds: CODE_MIN_INTERVAL_SECONDS'));
    expect(source, contains('expiresInMinutes: CODE_TTL_MINUTES'));
  });
}
