import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 9, 21);
  final pt = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);

  group('the window: D-1 … D-30, never today', () {
    test('yesterday and the 30th day back are inside', () {
      expect(isDayAccountDate(DateTime(2026, 9, 20), today, 30), isTrue);
      expect(isDayAccountDate(DateTime(2026, 8, 22), today, 30), isTrue);
    });

    test('today, the future and the 31st day back are outside', () {
      expect(isDayAccountDate(today, today, 30), isFalse);
      expect(isDayAccountDate(DateTime(2026, 9, 22), today, 30), isFalse);
      expect(isDayAccountDate(DateTime(2026, 8, 21), today, 30), isFalse);
    });

    test('the time of day never moves the answer', () {
      expect(
          isDayAccountDate(DateTime(2026, 9, 20, 23, 59), today, 30), isTrue);
      expect(isDayAccountDate(DateTime(2026, 8, 22, 0, 1),
          DateTime(2026, 9, 21, 23, 0), 30), isTrue);
    });

    test('the oldest date follows the parameter', () {
      expect(dayAccountOldestDate(today, 30), DateTime(2026, 8, 22));
      expect(dayAccountOldestDate(today, 7), DateTime(2026, 9, 14));
    });
  });

  group('who writes', () {
    bool can({bool account = true, bool left = false}) => canWriteDayAccount(
        hasAccount: account,
        hasLeft: left,
        date: DateTime(2026, 9, 20),
        today: today,
        maxDaysBack: 30);

    test('an active member with an account', () => expect(can(), isTrue));
    test('never a pending member (no account)',
        () => expect(can(account: false), isFalse));
    test('never a departed member', () => expect(can(left: true), isFalse));
  });

  group('the body', () {
    test('is trimmed before it is judged', () {
      expect(normalizeDayAccountBody('  buscou às 17h  '), 'buscou às 17h');
      expect(dayAccountBodyErrorKey('   ', 1000), KApp.dayAccountErrEmpty);
    });

    test('the limit counts the trimmed text, the edge included', () {
      expect(dayAccountBodyErrorKey(' ${'a' * 1000} ', 1000), isNull);
      expect(dayAccountBodyErrorKey('a' * 1001, 1000),
          KApp.dayAccountErrTooLong);
    });
  });

  group('corrections', () {
    final first = (
      id: 1,
      authorId: 10,
      correctsId: null,
      createdAt: DateTime.utc(2026, 9, 21, 12),
    );
    final fix = (
      id: 2,
      authorId: 10,
      correctsId: 1,
      createdAt: DateTime.utc(2026, 9, 21, 13),
    );
    final other = (
      id: 3,
      authorId: 20,
      correctsId: null,
      createdAt: DateTime.utc(2026, 9, 21, 11),
    );
    final day = [first, fix, other];

    test('the corrected relato is superseded, and knows by which', () {
      expect(supersededDayAccountIds(day), {1});
      expect(correctionOf(1, day), fix);
      expect(correctionOf(2, day), isNull);
    });

    test('only the author corrects, only the newest link, only in window',
        () {
      bool can(DayAccountEntry e, {int me = 10, bool write = true}) =>
          canCorrectDayAccount(
              entry: e, sameDay: day, myProfileId: me, canWrite: write);
      expect(can(fix), isTrue);
      expect(can(first), isFalse, reason: 'already corrected');
      expect(can(other), isFalse, reason: 'somebody else wrote it');
      expect(can(fix, write: false), isFalse, reason: 'out of the window');
    });

    test('the day reads in the order it was written', () {
      expect(dayAccountsInOrder(day, (e) => e.createdAt).map((e) => e.id),
          [3, 1, 2]);
    });
  });

  group('sentences are dated facts', () {
    final at = DateTime(2026, 9, 21, 10, 32);
    test('the byline names the author and the instant written', () {
      expect(dayAccountByline(pt, authorName: 'Ana', writtenAt: at),
          'Registrado por Ana em ${pt.formatDate(at)} às ${pt.formatTime(at)}');
      expect(dayAccountByline(en, authorName: 'Ana', writtenAt: at),
          'Recorded by Ana on ${en.formatDate(at)} at ${en.formatTime(at)}');
    });

    test('the superseded line names the instant of the correction', () {
      expect(dayAccountCorrectedLine(pt, correctedAt: at),
          'Corrigido em ${pt.formatDate(at)} às ${pt.formatTime(at)}');
    });
  });

  group('the notification renders per reader', () {
    const params = '{"kind":"new","name":"Ana","date":"2026-09-20"}';
    test('a first relato', () {
      expect(
          NotificationRenderer.message(
              'day_account', params, 'stored', pt),
          'Ana registrou um relato sobre ${pt.formatIsoDate('2026-09-20')}.');
      expect(
          NotificationRenderer.message(
              'day_account', params, 'stored', en),
          'Ana recorded a day account about '
          '${en.formatIsoDate('2026-09-20')}.');
    });

    test('a correction', () {
      expect(
          NotificationRenderer.message('day_account',
              '{"kind":"correction","name":"Ana","date":"2026-09-20"}',
              'stored', pt),
          'Ana corrigiu um relato sobre ${pt.formatIsoDate('2026-09-20')}.');
    });

    test('an unknown kind falls back to the stored text, title included', () {
      const odd = '{"kind":"other","name":"Ana","date":"2026-09-20"}';
      expect(
          NotificationRenderer.message('day_account', odd, 'stored', en),
          'stored');
      expect(
          NotificationRenderer.title('day_account', odd, 'Stored', en),
          'Stored');
      expect(
          NotificationRenderer.title(
              'day_account', params, 'Stored', en),
          'Day account');
    });
  });
}
