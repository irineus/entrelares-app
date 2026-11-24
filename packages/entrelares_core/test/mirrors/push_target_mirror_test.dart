/// T-109 — the two kinds of push target are declared in THREE places that
/// cannot import one another: `PushTargetKind` / `PushTargetRules` here, the
/// migration's CHECKs on `push_subscriptions`, and `_shared/fcm.ts`, which
/// picks the FCM v1 message field (`fid` or `token`) by the row's kind.
///
/// Why a drift here is the silent kind: nothing breaks a build. An FID sent
/// through the wrong field is refused by FCM, `isDeadTarget` retires the row,
/// and the phone simply stops ringing while the function answers 200. So this
/// suite reads the server's own text and refuses any difference — including in
/// the retire rule, which must judge both kinds by the same statuses.
library;

import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

/// The newest migration that mentions [needle] — what production runs.
String _latestMigrationWith(String needle) {
  final files = migrationsDirectory()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final hits = files.where((f) => f.readAsStringSync().contains(needle));
  expect(hits, isNotEmpty,
      reason: 'No migration mentions `$needle`. If it was renamed, rename it '
          'here too.');
  return hits.last.readAsStringSync();
}

Set<String> _quoted(String source) =>
    RegExp("['\"]([^'\"]+)['\"]").allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  final wires = PushTargetKind.values.map((k) => k.wire).toSet();
  final fcm = repoFile('supabase/functions/_shared/fcm.ts');

  test('the table CHECK accepts exactly the kinds the client can store', () {
    final sql = _latestMigrationWith('push_subscriptions_kind_check');
    final check = RegExp(r'CHECK\s*\(\s*kind\s+IN\s*\(([^)]*)\)\s*\)')
        .firstMatch(sql);
    expect(check, isNotNull, reason: '`CHECK (kind IN (...))` not found.');
    expect(_quoted(check!.group(1)!), wires);
  });

  test('the column DEFAULT is the token, so builds before T-109 stay right',
      () {
    final sql = _latestMigrationWith('ADD COLUMN IF NOT EXISTS kind');
    expect(sql, contains("kind text NOT NULL DEFAULT '${PushTargetKind.token.wire}'"));
  });

  test('the FID shape the database enforces is the one the client checks', () {
    final sql = _latestMigrationWith('push_subscriptions_fid_shape');
    final shape = RegExp(r"token\s*~\s*'([^']+)'").firstMatch(sql);
    expect(shape, isNotNull, reason: "`token ~ '<regex>'` not found.");
    expect(shape!.group(1), PushTargetRules.fidShape.pattern);
  });

  test('fcm.ts declares exactly the same kinds', () {
    final union =
        RegExp(r'export type PushTargetKind\s*=\s*([^;]+);').firstMatch(fcm);
    expect(union, isNotNull, reason: '`export type PushTargetKind` not found.');
    expect(_quoted(union!.group(1)!), wires);
  });

  test('fcm.ts sends an FID through `fid` and a token through `token`', () {
    final body = RegExp(r'export function fcmTarget\([^)]*\)[^{]*\{([\s\S]*?)\n\}')
        .firstMatch(fcm);
    expect(body, isNotNull, reason: '`export function fcmTarget` not found.');
    final compact = body!.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
    expect(
        compact,
        contains('target.kind === "${PushTargetKind.fid.wire}" '
            '? { fid: target.token } : { token: target.token }'));
    // …and the message spreads that target instead of naming `token` itself.
    expect(fcm, contains('...fcmTarget(target),'));
    expect(RegExp(r'message:\s*\{\s*token\b').hasMatch(fcm), isFalse,
        reason: 'A message built with a literal `token` field sends every FID '
            'through the deprecated field.');
  });

  test('the retire rule judges both kinds by the same statuses', () {
    final body =
        RegExp(r'export function isDeadTarget\(status: string\)[^{]*\{([\s\S]*?)\n\}')
            .firstMatch(fcm);
    expect(body, isNotNull, reason: '`export function isDeadTarget` not found.');
    final rule = body!.group(1)!;
    expect(_quoted(rule), {'UNREGISTERED', 'NOT_FOUND', 'INVALID_ARGUMENT'});
    expect(rule, isNot(contains('kind')),
        reason: 'A kind-specific retire rule could delete one kind for the '
            "other's error.");
    expect(fcm, contains('const retire = isDeadTarget(status);'));
  });

  test('a duplicate delivery collapses on both channels', () {
    // During the move a device can still hold its pre-T-109 token beside its
    // new installation ID; the tag makes the second copy REPLACE the first
    // instead of stacking (Android since F-09, the web since T-109).
    final compact = fcm.replaceAll(RegExp(r'\s+'), ' ');
    expect(compact, contains('tag: data.notificationId, }, }, apns:'),
        reason: '`android.notification.tag` is gone');
    expect(compact, contains('icon: "/icons/Icon-192.png", tag: data.notificationId,'),
        reason: '`webpush.notification.tag` is gone');
  });

  group('PushTargetRules.looksLikeFid', () {
    test('accepts the shape the Firebase SDK generates', () {
      expect(PushTargetRules.looksLikeFid('cAbCdEfGhIjKlMnOpQrS_-'), isTrue);
      expect(PushTargetRules.looksLikeFid('fxxxxxxxxxxxxxxxxxxxx1'), isTrue);
    });

    test('refuses a registration token and near misses', () {
      const token = 'dGVzdA:APA91bH-registration-token-with-a-colon-and-'
          'a-length-far-beyond-twenty-two-symbols-like-every-production-row';
      expect(PushTargetRules.looksLikeFid(token), isFalse);
      expect(PushTargetRules.looksLikeFid('aAbCdEfGhIjKlMnOpQrS_-'), isFalse,
          reason: 'first symbol outside c–f');
      expect(PushTargetRules.looksLikeFid('cAbCdEfGhIjKlMnOpQrS_'), isFalse,
          reason: '21 symbols');
      expect(PushTargetRules.looksLikeFid('cAbCdEfGhIjKlMnOpQrS:-'), isFalse,
          reason: 'a colon');
    });
  });
}
