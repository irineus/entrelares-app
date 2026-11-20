/// F-08 — an iCalendar file (RFC 5545), written by hand.
///
/// No package: the subset a calendar export needs is small, and every rule of
/// it is a place where a calendar app silently drops an event — so each one is
/// here, in pure Dart, under test:
///   * lines end in CRLF, and a line longer than 75 OCTETS is folded (CRLF +
///     one space) on a UTF-8 boundary — "Entrega: João → Conceição" counts
///     bytes, not characters;
///   * text escapes `\`, `;`, `,` and newlines (`\n`);
///   * an all-day event is `VALUE=DATE` with an EXCLUSIVE end (a one-day event
///     ends the next day);
///   * a timed event is written in UTC (`Z`), so no VTIMEZONE block is needed
///     and a phone in another zone shows the right hour.
library;

/// An alarm: [minutesBefore] the start, or at an absolute UTC instant.
class IcsAlarm {
  const IcsAlarm.before(int this.minutesBefore) : atUtc = null;
  const IcsAlarm.at(DateTime this.atUtc) : minutesBefore = null;

  final int? minutesBefore;
  final DateTime? atUtc;
}

/// One VEVENT. Either all-day ([allDayStart] .. [allDayEndExclusive], dates)
/// or timed ([startUtc] .. [endUtc]).
class IcsEvent {
  const IcsEvent.allDay({
    required this.uid,
    required this.summary,
    required DateTime start,
    required DateTime endExclusive,
    this.description,
    this.url,
    this.transparent = false,
    this.cancelled = false,
    this.alarm,
  })  : allDayStart = start,
        allDayEndExclusive = endExclusive,
        startUtc = null,
        endUtc = null;

  const IcsEvent.timed({
    required this.uid,
    required this.summary,
    required DateTime this.startUtc,
    required DateTime this.endUtc,
    this.description,
    this.url,
    this.transparent = false,
    this.cancelled = false,
    this.alarm,
  })  : allDayStart = null,
        allDayEndExclusive = null;

  final String uid;
  final String summary;
  final String? description;
  final String? url;
  final DateTime? allDayStart;
  final DateTime? allDayEndExclusive;
  final DateTime? startUtc;
  final DateTime? endUtc;

  /// Shown as "free" — a carer's days must not block the reader's agenda.
  final bool transparent;

  /// STATUS:CANCELLED — an agenda event deleted in the app, so a re-import
  /// removes it where the calendar app honours the status.
  final bool cancelled;
  final IcsAlarm? alarm;

  bool get isAllDay => allDayStart != null;

  /// The sort key: the instant the event starts (an all-day one at midnight
  /// UTC of its date — close enough to order a day's list).
  DateTime get sortKey => startUtc ??
      DateTime.utc(allDayStart!.year, allDayStart!.month, allDayStart!.day);
}

abstract final class IcsWriter {
  static const String _crlf = '\r\n';

  /// The calendar's file contents. [stampUtc] is DTSTAMP and the base of
  /// SEQUENCE — minutes since 2026-01-01 UTC, so every later export is a
  /// newer revision of the same UID and an app that compares them updates the
  /// event instead of keeping the old one.
  static String write(
    List<IcsEvent> events, {
    required String calendarName,
    required DateTime stampUtc,
  }) {
    final stamp = _utc(stampUtc);
    final sequence =
        stampUtc.toUtc().difference(DateTime.utc(2026)).inMinutes.clamp(0, 1 << 30);
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Entrelares//Calendar export//PT-BR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${escapeText(calendarName)}',
      'X-WR-TIMEZONE:America/Sao_Paulo',
    ];
    for (final e in events) {
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${e.uid}')
        ..add('DTSTAMP:$stamp')
        ..add('SEQUENCE:$sequence');
      if (e.isAllDay) {
        lines
          ..add('DTSTART;VALUE=DATE:${_date(e.allDayStart!)}')
          ..add('DTEND;VALUE=DATE:${_date(e.allDayEndExclusive!)}');
      } else {
        lines
          ..add('DTSTART:${_utc(e.startUtc!)}')
          ..add('DTEND:${_utc(e.endUtc!)}');
      }
      lines.add('SUMMARY:${escapeText(e.summary)}');
      final description = e.description;
      if (description != null && description.isNotEmpty) {
        lines.add('DESCRIPTION:${escapeText(description)}');
      }
      final url = e.url;
      if (url != null) lines.add('URL:$url');
      if (e.transparent) lines.add('TRANSP:TRANSPARENT');
      lines.add(e.cancelled ? 'STATUS:CANCELLED' : 'STATUS:CONFIRMED');
      final alarm = e.alarm;
      if (alarm != null && !e.cancelled) {
        lines
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add('DESCRIPTION:${escapeText(e.summary)}')
          ..add(alarm.atUtc != null
              ? 'TRIGGER;VALUE=DATE-TIME:${_utc(alarm.atUtc!)}'
              : 'TRIGGER:-PT${alarm.minutesBefore}M')
          ..add('END:VALARM');
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');
    return lines.map(fold).join(_crlf) + _crlf;
  }

  /// RFC 5545 §3.3.11: backslash first, then `;`, `,` and newlines.
  static String escapeText(String text) => text
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\n');

  /// RFC 5545 §3.1: at most 75 octets per line, continuation lines start with
  /// one space (which counts toward their 75). Never splits a UTF-8 sequence.
  static String fold(String line) {
    final out = StringBuffer();
    var octets = 0;
    var limit = 75;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final size = _utf8Length(rune);
      if (octets + size > limit) {
        out.write('$_crlf ');
        octets = 1;
        limit = 75;
      }
      out.write(char);
      octets += size;
    }
    return out.toString();
  }

  static int _utf8Length(int rune) => rune < 0x80
      ? 1
      : rune < 0x800
          ? 2
          : rune < 0x10000
              ? 3
              : 4;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _utc(DateTime t) {
    final u = t.toUtc();
    return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }
}
