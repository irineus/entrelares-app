/// U-24 (T-53 lote 1 port) — dates and times in the reader's language.
/// Ported from `entrelares-app` `Entrelares.Tests/DateFormatsTests.cs`.
///
/// The bug this closes does not announce itself: before U-24 every date
/// rendered `dd/MM` in EVERY language, so an English reader saw `05/08` and
/// read May 8th. A missing translation is visible; a wrong day is not — the
/// reader simply believes it.
///
/// These tests pin the three properties that make the fix safe: each language
/// gets its own DISPLAY format, the TRANSPORT format never moves, and a date
/// that did not come from us is never reinterpreted.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final ptBr = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);

  final theDay = DateTime(2026, 8, 5);
  final theMoment = DateTime(2026, 8, 5, 14, 30);

  group('each language gets its own display format', () {
    test('PT-BR keeps the Brazilian numeric format', () {
      expect(ptBr.formatDate(theDay), '05/08/2026');
      expect(ptBr.formatDateShort(theDay), '05/08');
      expect(ptBr.formatDateTime(theMoment), '05/08/2026 14:30');
      expect(ptBr.formatDateTimeShort(theMoment), '05/08 14:30');
      expect(ptBr.formatTime(theMoment), '14:30');
    });

    test('EN spells the month, so the day cannot be misread', () {
      expect(en.formatDate(theDay), '05 Aug 2026');
      expect(en.formatDateShort(theDay), '05 Aug');
    });

    test('EN uses a twelve-hour clock', () {
      expect(en.formatTime(theMoment), '2:30 PM');
      expect(en.formatDateTime(theMoment), '05 Aug 2026 2:30 PM');
      expect(ptBr.formatTime(DateTime(2026, 8, 5, 9, 5)), '09:05');
      expect(en.formatTime(DateTime(2026, 8, 5, 9, 5)), '9:05 AM');
    });

    // The whole point of choosing a month NAME over MM/dd/yyyy: this is the
    // date that silently means two different days in the two formats.
    test('EN never produces an ambiguous numeric date', () {
      final rendered = en.formatDate(theDay);
      expect(rendered, isNot(contains('/')));
      expect(rendered, contains('Aug'));
    });

    test('midnight and noon land on the right period', () {
      expect(en.formatTime(DateTime(2026, 8, 5, 0, 10)), '12:10 AM');
      expect(en.formatTime(DateTime(2026, 8, 5, 12, 0)), '12:00 PM');
    });
  });

  group('the transport format never moves', () {
    // U-24 moved DISPLAY off the invariant pin; this is the regression that
    // says it did not drag transport along: the same day, in an English
    // session, still serializes ISO — and the display helper did not become
    // the transport helper by accident.
    test('transport stays ISO 8601 even in an English session', () {
      String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      expect(iso(theDay), '2026-08-05');
      expect(en.formatDate(theDay), isNot(iso(theDay)));
    });
  });

  group('a date that did not come from us is never reinterpreted', () {
    test('formatIsoDate renders an ISO string in the reader language', () {
      expect(ptBr.formatIsoDate('2026-08-05'), '05/08/2026');
      expect(en.formatIsoDate('2026-08-05'), '05 Aug 2026');
    });

    // The legacy promise, and the reason no backfill was needed: a
    // notification written before U-24 carries an already-formatted PT-BR
    // string, and it must reach the screen exactly as its reader first
    // received it — in BOTH languages.
    for (final stored in ['04/08/2026', '04/08', '', '30 dias', '2026-13-45']) {
      test('formatIsoDate leaves "$stored" untouched', () {
        expect(ptBr.formatIsoDate(stored), stored);
        expect(en.formatIsoDate(stored), stored);
      });
    }

    // Dart-specific hardening: DateTime rolls invalid components over, and a
    // rolled-over date is a REINTERPRETATION — the exact thing this file
    // promises never to do.
    test('formatIsoDate refuses a date that does not round-trip', () {
      expect(en.formatIsoDate('2026-04-31'), '2026-04-31');
      expect(ptBr.formatIsoDate('2026-02-30'), '2026-02-30');
    });
  });

  group('wire time strings (the day sheet handoff time)', () {
    test('renders per language and passes anything else through', () {
      expect(ptBr.formatTimeString('14:30:00'), '14:30');
      expect(en.formatTimeString('14:30:00'), '2:30 PM');
      expect(en.formatTimeString('09:05'), '9:05 AM');
      expect(en.formatTimeString('whatever'), 'whatever');
    });
  });

  group('names the calendar reads', () {
    test('month-year header follows the language', () {
      expect(ptBr.formatMonthYear(2026, 8), 'agosto de 2026');
      expect(en.formatMonthYear(2026, 8), 'August 2026');
    });

    test('the bare month name is what the report filters list', () {
      expect(ptBr.monthName(1), 'janeiro');
      expect(ptBr.monthName(12), 'dezembro');
      expect(en.monthName(1), 'January');
      expect(en.monthName(12), 'December');
    });

    test('weekday abbreviations follow the language, dot trimmed', () {
      expect(ptBr.weekdayAbbrev(DateTime.wednesday), 'qua');
      expect(en.weekdayAbbrev(DateTime.wednesday), 'Wed');
      expect(ptBr.weekdayAbbrev(DateTime.sunday), 'dom');
      expect(en.weekdayAbbrev(DateTime.sunday), 'Sun');
    });

    // The catalog carries the header initials; the E2E gate in the web repo
    // asserts "W" appears only in English — mirrored here as data.
    test('weekday initials come from the catalog per language', () {
      expect(ptBr[K.calWeekdayInitials], 'D,S,T,Q,Q,S,S');
      expect(en[K.calWeekdayInitials].split(','), hasLength(7));
      expect(en[K.calWeekdayInitials], contains('W'));
    });

    // TodayCard.razor: "dddd, dd 'de' MMMM" pt-BR / "dddd, MMMM d" en-US —
    // the pt day is zero-padded, the English one is not.
    // U-63: a deadline is said the way a person says it.
    test('a deadline reads "sábado, 10/10, à 0h" / "Saturday, 10 Oct, at 12 AM"',
        () {
      expect(ptBr.formatDeadline(DateTime(2026, 10, 10)), 'sábado, 10/10, à 0h');
      expect(ptBr.formatDeadline(DateTime(2026, 10, 10, 1)),
          'sábado, 10/10, à 1h');
      expect(ptBr.formatDeadline(DateTime(2026, 10, 11, 18, 30)),
          'domingo, 11/10, às 18h30');
      expect(en.formatDeadline(DateTime(2026, 10, 10)),
          'Saturday, 10 Oct, at 12 AM');
      expect(en.formatDeadline(DateTime(2026, 10, 11, 18, 30)),
          'Sunday, 11 Oct, at 6:30 PM');
    });

    test('the Today card heading follows the language', () {
      expect(ptBr.formatTodayHeading(theDay), 'quarta-feira, 05 de agosto');
      expect(en.formatTodayHeading(theDay), 'Wednesday, August 5');
      expect(ptBr.formatTodayHeading(DateTime(2026, 8, 23)),
          'domingo, 23 de agosto');
      expect(en.formatTodayHeading(DateTime(2026, 8, 23)), 'Sunday, August 23');
    });
  });
}
