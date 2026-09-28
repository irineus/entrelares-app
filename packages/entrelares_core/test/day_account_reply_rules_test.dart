// F-75 — the reply to a relato: the client mirror of add_day_account_reply.
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 9, 28, 12);
final written = now.subtract(const Duration(days: 3));

DayAccountReplyEntry reply(int id,
        {int account = 10, int author = 2, int? corrects, int daysAgo = 1}) =>
    (
      id: id,
      accountId: account,
      authorId: author,
      correctsId: corrects,
      createdAt: now.subtract(Duration(days: daysAgo)),
    );

bool can({
  bool enabled = true,
  bool viewer = false,
  bool account = true,
  bool left = false,
  int me = 2,
  int author = 1,
  DateTime? created,
  int window = 30,
  List<DayAccountReplyEntry> replies = const [],
}) =>
    canReplyToDayAccount(
      enabled: enabled,
      isViewer: viewer,
      hasAccount: account,
      hasLeft: left,
      myProfileId: me,
      accountId: 10,
      accountAuthorId: author,
      accountCreatedAt: created ?? written,
      now: now,
      windowDays: window,
      replies: replies,
    );

void main() {
  group('who may reply', () {
    test('another active caregiver with an account, inside the window',
        () => expect(can(), isTrue));
    test('never with the module off', () => expect(can(enabled: false), isFalse));
    test('never a Visualizador (F-50)', () => expect(can(viewer: true), isFalse));
    test('never without an account, never after leaving', () {
      expect(can(account: false), isFalse);
      expect(can(left: true), isFalse);
    });
    test('never the relato\'s own author', () => expect(can(me: 1), isFalse));
    test('once: the second text is a correction, not a second reply', () {
      expect(can(replies: [reply(50)]), isFalse);
      // Someone else's reply does not use up mine.
      expect(can(replies: [reply(50, author: 3)]), isTrue);
      // A reply to another relato does not either.
      expect(can(replies: [reply(50, account: 11)]), isTrue);
    });
  });

  group('the window counts from when the relato was WRITTEN', () {
    test('the last day is in, the next is out', () {
      expect(can(created: now.subtract(const Duration(days: 30))), isTrue);
      expect(
          can(created: now.subtract(const Duration(days: 30, minutes: 1))),
          isFalse);
    });
    test('the key moves it', () {
      expect(can(window: 7, created: now.subtract(const Duration(days: 8))),
          isFalse);
    });
  });

  group('corrections', () {
    final original = reply(50);
    test('my original reply, once', () {
      expect(
          canCorrectDayAccountReply(
              entry: original, replies: [original], myProfileId: 2, canWrite: true),
          isTrue);
      final fix = reply(51, corrects: 50);
      expect(
          canCorrectDayAccountReply(
              entry: original,
              replies: [original, fix],
              myProfileId: 2,
              canWrite: true),
          isFalse);
      expect(correctionOfReply(50, [original, fix])?.id, 51);
    });
    test('never someone else\'s, never a correction, never with the window '
        'closed', () {
      expect(
          canCorrectDayAccountReply(
              entry: original, replies: [original], myProfileId: 3, canWrite: true),
          isFalse);
      final fix = reply(51, corrects: 50);
      expect(
          canCorrectDayAccountReply(
              entry: fix, replies: [original, fix], myProfileId: 2, canWrite: true),
          isFalse);
      expect(
          canCorrectDayAccountReply(
              entry: original,
              replies: [original],
              myProfileId: 2,
              canWrite: false),
          isFalse);
    });
    test('the replies of one relato, in the order they were written', () {
      final list = repliesToDayAccount(10, [
        reply(3, daysAgo: 1),
        reply(1, daysAgo: 3),
        reply(9, account: 11),
        reply(2, daysAgo: 2),
      ]);
      expect(list.map((r) => r.id), [1, 2, 3]);
    });
  });

  group('the body', () {
    test('trimmed, never empty, capped by the key', () {
      expect(dayAccountReplyBodyErrorKey('   ', 1000),
          KApp.dayAccountReplyErrEmpty);
      expect(dayAccountReplyBodyErrorKey('x' * 101, 100),
          KApp.dayAccountReplyErrTooLong);
      expect(dayAccountReplyBodyErrorKey('  ok  ', 2), isNull);
    });
  });

  group('the notification, rendered per reader', () {
    final params = jsonEncode({'kind': 'new', 'name': 'Bruno', 'date': '2026-09-27'});
    test('PT and EN, new and correction', () {
      final pt = Localization(AppLanguage.ptBr);
      final en = Localization(AppLanguage.en);
      expect(NotificationRenderer.message('day_account_reply', params, 'x', pt),
          'Bruno respondeu ao seu relato sobre 27/09/2026.');
      expect(NotificationRenderer.message('day_account_reply', params, 'x', en),
          contains('Bruno replied to your day account'));
      final fix = jsonEncode(
          {'kind': 'correction', 'name': 'Bruno', 'date': '2026-09-27'});
      expect(NotificationRenderer.message('day_account_reply', fix, 'x', pt),
          'Bruno corrigiu a resposta ao seu relato sobre 27/09/2026.');
    });
    test('an unknown kind falls back to the stored text', () {
      final odd =
          jsonEncode({'kind': 'other', 'name': 'Bruno', 'date': '2026-09-27'});
      expect(
          NotificationRenderer.message(
              'day_account_reply', odd, 'guardado', Localization(AppLanguage.ptBr)),
          'guardado');
    });
    test('the byline names the author and the instant', () {
      final l = Localization(AppLanguage.ptBr);
      expect(
          dayAccountReplyByline(l,
              authorName: 'Bruno', writtenAt: DateTime(2026, 9, 27, 18, 5)),
          startsWith('Resposta de Bruno em 27/09/2026'));
    });
  });

  test('the keys default to the migration seeds', () {
    const s = PublicSettings.unloaded;
    expect(s.dayAccountRepliesEnabled, isFalse);
    expect(s.dayAccountReplyWindowDays, 30);
    expect(s.dayAccountReplyMaxChars, 1000);
  });
}
