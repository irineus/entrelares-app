/// U-24 — every date and time the USER READS, formatted in the session's
/// language. Nothing here ever touches what goes on the wire. Ported from
/// `entrelares-app` `Entrelares/Localization/DateFormats.cs`.
///
/// **The rule this file exists to make unbreakable.** There are two date
/// formats in this app and they are not the same thing:
///  - **Transport** — ISO 8601 (`yyyy-MM-dd`), what PostgREST filters and
///    `care_schedules` rows carry. Those call sites keep their literal
///    `CareSchedule.isoDate` and must never route through here.
///  - **Display** — this file, and only this file.
///
/// **Why English gets a month NAME and not `MM/dd/yyyy`.** `MM/dd/yyyy` only
/// moves the ambiguity: right for a US reader, wrong for a British, Irish,
/// Indian or Australian one — and this app's whole job is saying who has a
/// child on which day. `06 Aug 2026` cannot be misread in any variant of
/// English, and it saves us from modelling regional English at all.
///
/// **The name tables are hardcoded, deliberately.** The web repo's server
/// mirror (`functions/_shared/i18n.ts`) refuses `Intl` so a runtime upgrade
/// cannot restyle every e-mail with no commit to point at; `intl`'s ICU data
/// is the same trap here. Hardcoding keeps the two renderers (app, e-mail)
/// provably in step — `date_formats_test.dart` pins what this file renders and
/// `test/mirrors/email_date_format_mirror_test.dart` pins the Deno copy against
/// it. (Three renderers until 23/08/2026: the web one was the Blazor client's,
/// and it died with the cutover.)
library;

import '../family_time.dart';
import 'k_app.dart';
import 'localization.dart';

const _enMonthsAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _ptMonthsFull = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

const _enMonthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Index 0 = Monday, matching `DateTime.weekday - 1`. PT-BR follows the
/// pt-BR culture's "ddd" with the trailing dot trimmed, as the web renders.
const _ptWeekdaysAbbrev = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _enWeekdaysAbbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _ptWeekdaysFull = [
  'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
  'sexta-feira', 'sábado', 'domingo',
];
const _enWeekdaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String _two(int n) => n.toString().padLeft(2, '0');

extension DateFormats on Localization {
  /// A full date: `06/08/2026` · `06 Aug 2026`.
  String formatDate(DateTime date) => isEnglish
      ? '${_two(date.day)} ${_enMonthsAbbrev[date.month - 1]} ${date.year}'
      : '${_two(date.day)}/${_two(date.month)}/${date.year}';

  /// A date with no year, for lists where the year is implied:
  /// `06/08` · `06 Aug`.
  String formatDateShort(DateTime date) => isEnglish
      ? '${_two(date.day)} ${_enMonthsAbbrev[date.month - 1]}'
      : '${_two(date.day)}/${_two(date.month)}';

  /// A timestamp: `06/08/2026 14:30` · `06 Aug 2026 2:30 PM`.
  /// Pass an already-local [DateTime] — this does not convert.
  String formatDateTime(DateTime moment) =>
      '${formatDate(moment)} ${formatTime(moment)}';

  /// A timestamp with no year: `06/08 14:30` · `06 Aug 2:30 PM`.
  String formatDateTimeShort(DateTime moment) =>
      '${formatDateShort(moment)} ${formatTime(moment)}';

  /// A time of day: `14:30` · `2:30 PM`. English gets a 12-hour clock —
  /// `h:mm tt`, hour NOT zero-padded (`9:05 AM`), PT-BR keeps `HH:mm`.
  String formatTime(DateTime moment) {
    if (!isEnglish) return '${_two(moment.hour)}:${_two(moment.minute)}';
    final hour12 = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
    final period = moment.hour < 12 ? 'AM' : 'PM';
    return '$hour12:${_two(moment.minute)} $period';
  }

  /// A time that arrived as a STRING from the database — the `HH:mm:ss` (or
  /// `HH:mm`) PostgREST renders for a `time` column. Anything that does not
  /// parse comes back untouched, the same promise [formatIsoDate] makes.
  String formatTimeString(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(value);
    if (match == null) return value;
    return formatTime(DateTime(
        2000, 1, 1, int.parse(match.group(1)!), int.parse(match.group(2)!)));
  }

  /// Formats a date that arrived as a STRING from the database — the
  /// `params.date` of a notification.
  ///
  /// **Anything that is not ISO comes back untouched.** That is the whole
  /// legacy story: a row written before U-24 stores an already-formatted
  /// PT-BR string and keeps rendering exactly as its reader first received
  /// it — no backfill, no history that appears rewritten. It also covers the
  /// reverse risk (a trigger deployed ahead of the client) for free.
  String formatIsoDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return value;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    // DateTime rolls invalid components over (2026-04-31 → May 1); a date
    // that does not round-trip was never a real date, so it passes through
    // exactly as DateOnly.TryParseExact refuses it in C#.
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return value;
    }
    return formatDate(parsed);
  }

  /// A month name on its own: `agosto` · `August` — the report filters, where
  /// the web reads `DisplayCulture.DateTimeFormat.GetMonthName(m)`.
  String monthName(int month) =>
      isEnglish ? _enMonthsFull[month - 1] : _ptMonthsFull[month - 1];

  /// The calendar header: `agosto de 2026` · `August 2026`. Month names are
  /// display culture in the web (`"MMMM 'de' yyyy"` pt-BR / `"MMMM yyyy"`
  /// en-US), mirrored here as tables.
  String formatMonthYear(int year, int month) => isEnglish
      ? '${_enMonthsFull[month - 1]} $year'
      : '${_ptMonthsFull[month - 1]} de $year';

  /// Abbreviated weekday name for [DateTime.weekday] (Mon=1..Sun=7):
  /// `seg` · `Mon`. The pt-BR culture's trailing dot is trimmed, as the web
  /// renders (`CalendarHelpers.FormatHandoffDate`).
  String weekdayAbbrev(int weekday) => isEnglish
      ? _enWeekdaysAbbrev[weekday - 1]
      : _ptWeekdaysAbbrev[weekday - 1];

  /// U-63 — a DEADLINE, as a person says it: `sábado, 10/10, à 0h` /
  /// `domingo, 11/10, às 18h30` · `Saturday, 10 Oct, at 12 AM` /
  /// `Sunday, 11 Oct, at 6:30 PM`. "10/10/2026 00:00" was a timestamp, and
  /// midnight read as a time that belongs to no day. PT-BR says "à" for the
  /// singular hours (0h, 1h) and "às" for the rest.
  String formatDeadline(DateTime moment) {
    if (isEnglish) {
      final h = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
      final ampm = moment.hour < 12 ? 'AM' : 'PM';
      final time = moment.minute == 0 ? '$h $ampm' : '$h:${_two(moment.minute)} $ampm';
      return '${_enWeekdaysFull[moment.weekday - 1]}, ${_two(moment.day)} '
          '${_enMonthsAbbrev[moment.month - 1]}, at $time';
    }
    final prep = moment.hour <= 1 ? 'à' : 'às';
    final time = moment.minute == 0
        ? '${moment.hour}h'
        : '${moment.hour}h${_two(moment.minute)}';
    return '${_ptWeekdaysFull[moment.weekday - 1]}, ${_two(moment.day)}/'
        '${_two(moment.month)}, $prep $time';
  }

  /// T-105 — a deadline on the FAMILY's clock (America/Sao_Paulo, where the
  /// server decides it), with "(horário de Brasília)" when this device reads
  /// another clock — a parent in Manaus is otherwise an hour off without
  /// knowing it. [deviceDiffers] defaults to this device ([FamilyTime]).
  String formatFamilyDeadline(DateTime moment, {bool? deviceDiffers}) {
    final base = formatDeadline(moment);
    return (deviceDiffers ?? FamilyTime.deviceDiffers())
        ? '$base ${this[KApp.familyTimeSuffix]}'
        : base;
  }

  /// The Today card's date line, mirroring `TodayCard.razor`'s
  /// `"dddd, dd 'de' MMMM"` pt-BR / `"dddd, MMMM d"` en-US:
  /// `quarta-feira, 19 de agosto` · `Wednesday, August 19`.
  String formatTodayHeading(DateTime date) => isEnglish
      ? '${_enWeekdaysFull[date.weekday - 1]}, '
          '${_enMonthsFull[date.month - 1]} ${date.day}'
      : '${_ptWeekdaysFull[date.weekday - 1]}, '
          '${_two(date.day)} de ${_ptMonthsFull[date.month - 1]}';
}
