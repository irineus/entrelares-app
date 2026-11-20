import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-08 — the RFC 5545 subset the calendar export writes. Each rule here is a
/// place where a calendar app drops an event without saying anything.
void main() {
  final stamp = DateTime.utc(2026, 11, 20, 15, 30);

  group('IcsWriter.write', () {
    test('a calendar with CRLF line ends, a stamp and a sequence', () {
      final text = IcsWriter.write(const [],
          calendarName: 'Entrelares — Silva', stampUtc: stamp);
      expect(text, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
      expect(text, endsWith('END:VCALENDAR\r\n'));
      expect(text, contains('X-WR-CALNAME:Entrelares — Silva\r\n'));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')),
          reason: 'every line ends in CRLF');
    });

    test('an all-day event ends the NEXT day (DTEND is exclusive)', () {
      final text = IcsWriter.write([
        IcsEvent.allDay(
          uid: 'u1@entrelares.app',
          summary: 'Com Ana',
          start: DateTime(2026, 12, 31),
          endExclusive: DateTime(2027, 1, 1),
          transparent: true,
        ),
      ], calendarName: 'X', stampUtc: stamp);
      expect(text, contains('DTSTART;VALUE=DATE:20261231\r\n'));
      expect(text, contains('DTEND;VALUE=DATE:20270101\r\n'));
      expect(text, contains('TRANSP:TRANSPARENT\r\n'));
      expect(text, contains('DTSTAMP:20261120T153000Z\r\n'));
    });

    test('a timed event is written in UTC, with its alarm', () {
      final text = IcsWriter.write([
        IcsEvent.timed(
          uid: 'u2@entrelares.app',
          summary: 'Entrega: Ana → Bruno',
          startUtc: DateTime.utc(2026, 12, 1, 21),
          endUtc: DateTime.utc(2026, 12, 1, 21, 30),
          alarm: const IcsAlarm.before(60),
        ),
      ], calendarName: 'X', stampUtc: stamp);
      expect(text, contains('DTSTART:20261201T210000Z\r\n'));
      expect(text, contains('DTEND:20261201T213000Z\r\n'));
      expect(text, contains('BEGIN:VALARM\r\nACTION:DISPLAY\r\n'));
      expect(text, contains('TRIGGER:-PT60M\r\n'));
      expect(text, contains('STATUS:CONFIRMED\r\n'));
    });

    test('an absolute alarm and a cancelled event (which carries none)', () {
      final eve = IcsWriter.write([
        IcsEvent.timed(
          uid: 'u3',
          summary: 'Saúde',
          startUtc: DateTime.utc(2026, 12, 2, 12),
          endUtc: DateTime.utc(2026, 12, 2, 13),
          alarm: IcsAlarm.at(DateTime.utc(2026, 12, 1, 22)),
        ),
      ], calendarName: 'X', stampUtc: stamp);
      expect(eve, contains('TRIGGER;VALUE=DATE-TIME:20261201T220000Z\r\n'));

      final cancelled = IcsWriter.write([
        IcsEvent.timed(
          uid: 'u4',
          summary: 'Saúde',
          startUtc: DateTime.utc(2026, 12, 2, 12),
          endUtc: DateTime.utc(2026, 12, 2, 13),
          cancelled: true,
          alarm: const IcsAlarm.before(15),
        ),
      ], calendarName: 'X', stampUtc: stamp);
      expect(cancelled, contains('STATUS:CANCELLED\r\n'));
      expect(cancelled, isNot(contains('VALARM')));
    });

    test('a later export is a newer SEQUENCE of the same UID', () {
      int sequenceOf(DateTime at) {
        final text = IcsWriter.write([
          IcsEvent.allDay(
              uid: 'same',
              summary: 'x',
              start: DateTime(2026, 12, 1),
              endExclusive: DateTime(2026, 12, 2)),
        ], calendarName: 'X', stampUtc: at);
        return int.parse(
            RegExp(r'SEQUENCE:(\d+)').firstMatch(text)!.group(1)!);
      }

      expect(sequenceOf(stamp.add(const Duration(minutes: 5))),
          greaterThan(sequenceOf(stamp)));
    });
  });

  group('IcsWriter.escapeText', () {
    test('backslash, semicolon, comma and newlines', () {
      expect(IcsWriter.escapeText(r'a\b; c, d' '\n' 'e'),
          r'a\\b\; c\, d\ne');
      expect(IcsWriter.escapeText('x\r\ny'), r'x\ny');
    });
  });

  group('IcsWriter.fold', () {
    test('a short line is untouched', () {
      expect(IcsWriter.fold('SUMMARY:Com Ana'), 'SUMMARY:Com Ana');
    });

    test('no physical line passes 75 OCTETS, and no UTF-8 sequence is split',
        () {
      final line = 'SUMMARY:${'Conceição → João · ' * 12}';
      final folded = IcsWriter.fold(line);
      final parts = folded.split('\r\n');
      expect(parts.length, greaterThan(1));
      for (final part in parts) {
        expect(utf8.encode(part).length, lessThanOrEqualTo(75));
      }
      for (final part in parts.skip(1)) {
        expect(part, startsWith(' '));
      }
      // Unfolding gives the line back.
      expect(folded.replaceAll('\r\n ', ''), line);
    });
  });
}
