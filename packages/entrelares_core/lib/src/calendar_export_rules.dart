/// F-08 — what an export to another calendar (.ics) carries (owner,
/// 20/11/2026).
///
/// The card was written for the Blazor client: one event per day, titled with
/// the parent's name. The app today has lanes per child (F-07), handoff times
/// (U-55) and the children's agenda (F-55), and the owner's read was that the
/// moments a parent plans around are the HANDOFFS and the children's EVENTS —
/// a whole day "with Ana" is the least useful of the three. So the export is
/// three layers the reader picks:
///
///   * **handoffs** (on by default) — one event per change of carer in a lane
///     (the effective carer of D against D-1's, F-07's lane rule), at the
///     handoff hour for 30 minutes, or all-day when the family has no set
///     time; a swapped day says who was planned;
///   * **children's events** — the F-55 agenda, filtered by kind (the day
///     note is off by default); a soft-deleted event in the period goes out
///     CANCELLED, so a re-import cleans it where the calendar app honours it;
///   * **each carer's days** (off by default) — one all-day event per RUN of
///     consecutive days with the same carer, shown as free time.
///
/// "Só o que envolve você" keeps the handoffs the reader gives or takes, the
/// reader's own runs and the events that fall on the reader's days.
///
/// The file is a SNAPSHOT: a swap approved afterwards does not reach the
/// phone's calendar by itself (F-109 is the subscription that would). Every
/// event has a stable UID, so a re-import updates instead of duplicating.
/// The Premium gate is the app's (`calendar_export.premium_only`), like the
/// PDF's: nothing here is a rule the server could enforce on a read.
library;

import 'agenda_rules.dart';
import 'family_time.dart';
import 'ics_writer.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// One `care_schedules` row as the export reads it. [lane] is F-07's child id
/// (null in a single-plan family).
class ExportPlanDay {
  const ExportPlanDay({
    required this.date,
    required this.plannedId,
    required this.effectiveId,
    this.lane,
    this.handoff,
  });

  final DateTime date;
  final int? lane;
  final int plannedId;
  final int effectiveId;

  /// `HH:mm` or `HH:mm:ss` (PostgREST's), or null.
  final String? handoff;
}

/// One `child_events` row as the export reads it.
class ExportAgendaEvent {
  const ExportAgendaEvent({
    required this.id,
    required this.date,
    required this.kind,
    this.childId,
    this.start,
    this.end,
    this.body,
    this.deleted = false,
    this.remindMinutes,
  });

  final int id;
  final DateTime date;
  final AgendaKind kind;

  /// Null on a day note.
  final int? childId;
  final String? start;
  final String? end;
  final String? body;
  final bool deleted;
  final int? remindMinutes;
}

/// The reader's choices on the sheet.
class CalendarExportOptions {
  const CalendarExportOptions({
    required this.from,
    required this.to,
    this.handoffs = true,
    this.events = true,
    this.days = false,
    this.reminders = false,
    this.kinds = CalendarExportRules.defaultKinds,
    this.children,
    this.onlyProfileId,
  });

  /// Inclusive, date-only.
  final DateTime from;
  final DateTime to;
  final bool handoffs;
  final bool events;
  final bool days;
  final bool reminders;
  final Set<AgendaKind> kinds;

  /// The children picked (F-96's picker); null = every child.
  final Set<int>? children;

  /// "Só o que envolve você": the reader's profile id; null = the family.
  final int? onlyProfileId;

  CalendarExportOptions copyWith({
    DateTime? from,
    DateTime? to,
    bool? handoffs,
    bool? events,
    bool? days,
    bool? reminders,
    Set<AgendaKind>? kinds,
    Set<int>? Function()? children,
    int? Function()? onlyProfileId,
  }) =>
      CalendarExportOptions(
        from: from ?? this.from,
        to: to ?? this.to,
        handoffs: handoffs ?? this.handoffs,
        events: events ?? this.events,
        days: days ?? this.days,
        reminders: reminders ?? this.reminders,
        kinds: kinds ?? this.kinds,
        children: children == null ? this.children : children(),
        onlyProfileId:
            onlyProfileId == null ? this.onlyProfileId : onlyProfileId(),
      );
}

/// What the export knows about the family.
class CalendarExportFamily {
  const CalendarExportFamily({
    required this.familyId,
    required this.familyName,
    required this.names,
    this.childNames = const {},
    this.perChild = false,
    this.dayUrl,
  });

  final int familyId;
  final String familyName;

  /// Profile id → the name the event shows (the app passes first names).
  final Map<int, String> names;

  /// Child id → first name, in the family's order.
  final Map<int, String> childNames;

  /// `families.schedule_mode = per_child` (F-07): a lane's events name the
  /// child.
  final bool perChild;

  /// The app's address of a day (`<webOrigin>/?day=YYYY-MM-DD`), or null.
  final String Function(DateTime day)? dayUrl;
}

abstract final class CalendarExportRules {
  /// Every kind but the day note: a note is a sentence about the day, not an
  /// appointment (owner, 20/11/2026).
  static const Set<AgendaKind> defaultKinds = {
    AgendaKind.school,
    AgendaKind.health,
    AgendaKind.medicine,
    AgendaKind.activity,
    AgendaKind.free,
    AgendaKind.other,
  };

  static const Duration handoffLength = Duration(minutes: 30);
  static const Duration eventDefaultLength = Duration(hours: 1);
  static const int handoffReminderMinutes = 60;

  /// The longest title a body contributes before the ellipsis.
  static const int titleBodyMax = 60;

  /// Only the day before [options.from] is read outside the period — it says
  /// whether the first day is a handoff. The app fetches from there.
  static DateTime fetchFrom(DateTime from) =>
      DateTime(from.year, from.month, from.day - 1);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _inPeriod(DateTime d, CalendarExportOptions o) {
    final day = _day(d);
    return !day.isBefore(_day(o.from)) && !day.isAfter(_day(o.to));
  }

  /// The UTC instant of [hhmm] (`HH:mm[:ss]`) on [date] on the family's
  /// clock — the FIXED São Paulo offset, never a test override.
  static DateTime? familyInstant(DateTime date, String? hhmm) {
    if (hhmm == null || hhmm.length < 5) return null;
    final h = int.tryParse(hhmm.substring(0, 2));
    final m = int.tryParse(hhmm.substring(3, 5));
    if (h == null || m == null) return null;
    return DateTime.utc(date.year, date.month, date.day, h, m)
        .subtract(FamilyTime.offset);
  }

  /// A lane is in the export when the family plans once (null lane) or the
  /// lane's child was picked.
  static bool _laneIncluded(int? lane, CalendarExportOptions o) =>
      lane == null || o.children == null || o.children!.contains(lane);

  static String _name(CalendarExportFamily f, int id) => f.names[id] ?? '?';

  /// "Com Ana" / "Com Ana · Lucas" — the child only where lanes exist.
  static String _withLane(String text, int? lane, CalendarExportFamily f) {
    if (!f.perChild || lane == null) return text;
    final child = f.childNames[lane];
    return child == null ? text : '$text · $child';
  }

  static String _uidLane(int? lane) => lane?.toString() ?? 'all';

  /// The events, ordered by start. Cancelled ones included; [count] skips
  /// them.
  static List<IcsEvent> build({
    required List<ExportPlanDay> plan,
    required List<ExportAgendaEvent> agenda,
    required CalendarExportOptions options,
    required CalendarExportFamily family,
    required Localization l,
  }) {
    final o = options;
    final me = o.onlyProfileId;
    final byLaneDay = <(int?, DateTime), ExportPlanDay>{
      for (final d in plan) (d.lane, _day(d.date)): d,
    };
    final lanes = {for (final d in plan) d.lane};
    final out = <IcsEvent>[];

    String? urlFor(DateTime day) => family.dayUrl?.call(day);

    // ── Handoffs ──
    if (o.handoffs) {
      for (final d in plan) {
        if (!_inPeriod(d.date, o) || !_laneIncluded(d.lane, o)) continue;
        final day = _day(d.date);
        final prev = byLaneDay[(d.lane, DateTime(day.year, day.month, day.day - 1))];
        if (prev == null || prev.effectiveId == d.effectiveId) continue;
        final from = prev.effectiveId;
        final to = d.effectiveId;
        if (me != null && from != me && to != me) continue;
        final start = familyInstant(day, d.handoff);
        final names = [_name(family, from), _name(family, to)];
        final summary = _withLane(
            l.format(
                start == null
                    ? KApp.calExportHandoffNoTime
                    : KApp.calExportHandoff,
                names),
            d.lane,
            family);
        final description = d.effectiveId != d.plannedId
            ? l.format(KApp.sheetPlanned, [_name(family, d.plannedId)])
            : null;
        final uid =
            'handoff-${family.familyId}-${_uidLane(d.lane)}-${_ymd(day)}@entrelares.app';
        out.add(start == null
            ? IcsEvent.allDay(
                uid: uid,
                summary: summary,
                start: day,
                endExclusive: DateTime(day.year, day.month, day.day + 1),
                description: description,
                url: urlFor(day),
                transparent: true,
              )
            : IcsEvent.timed(
                uid: uid,
                summary: summary,
                startUtc: start,
                endUtc: start.add(handoffLength),
                description: description,
                url: urlFor(day),
                alarm: o.reminders
                    ? const IcsAlarm.before(handoffReminderMinutes)
                    : null,
              ));
      }
    }

    // ── Each carer's days: one event per run ──
    if (o.days) {
      for (final lane in lanes) {
        if (!_laneIncluded(lane, o)) continue;
        final days = [
          for (final d in plan)
            if (d.lane == lane && _inPeriod(d.date, o)) d
        ]..sort((a, b) => a.date.compareTo(b.date));
        var i = 0;
        while (i < days.length) {
          final first = days[i];
          var last = first;
          var j = i + 1;
          while (j < days.length &&
              days[j].effectiveId == first.effectiveId &&
              _day(days[j].date) ==
                  DateTime(last.date.year, last.date.month, last.date.day + 1)) {
            last = days[j];
            j++;
          }
          i = j;
          if (me != null && first.effectiveId != me) continue;
          final start = _day(first.date);
          final end = _day(last.date);
          out.add(IcsEvent.allDay(
            uid:
                'days-${family.familyId}-${_uidLane(lane)}-${_ymd(start)}@entrelares.app',
            summary: _withLane(
                l.format(KApp.calExportWith, [_name(family, first.effectiveId)]),
                lane,
                family),
            start: start,
            endExclusive: DateTime(end.year, end.month, end.day + 1),
            url: urlFor(start),
            transparent: true,
          ));
        }
      }
    }

    // ── Children's events ──
    if (o.events) {
      bool onMyDay(ExportAgendaEvent e) {
        final day = _day(e.date);
        if (e.childId != null) {
          final lane = family.perChild ? e.childId : null;
          return byLaneDay[(lane, day)]?.effectiveId == me;
        }
        // A day note belongs to the DAY: mine when I hold any lane of it.
        return lanes.any((lane) => byLaneDay[(lane, day)]?.effectiveId == me);
      }

      for (final e in agenda) {
        if (!_inPeriod(e.date, o) || !o.kinds.contains(e.kind)) continue;
        if (e.childId != null &&
            o.children != null &&
            !o.children!.contains(e.childId)) {
          continue;
        }
        if (me != null && !onMyDay(e)) continue;
        final day = _day(e.date);
        final child = e.childId == null ? null : family.childNames[e.childId];
        final summary = eventTitle(l, e.kind, child: child, body: e.body);
        final description = e.body?.trim();
        final uid = 'event-${e.id}@entrelares.app';
        final start = familyInstant(day, e.start);
        if (start == null) {
          out.add(IcsEvent.allDay(
            uid: uid,
            summary: summary,
            start: day,
            endExclusive: DateTime(day.year, day.month, day.day + 1),
            description: description,
            url: urlFor(day),
            transparent: true,
            cancelled: e.deleted,
          ));
          continue;
        }
        final end = familyInstant(day, e.end);
        out.add(IcsEvent.timed(
          uid: uid,
          summary: summary,
          startUtc: start,
          endUtc: end != null && end.isAfter(start)
              ? end
              : start.add(eventDefaultLength),
          description: description,
          url: urlFor(day),
          cancelled: e.deleted,
          alarm: o.reminders ? _eventAlarm(day, start, e.remindMinutes) : null,
        ));
      }
    }

    out.sort((a, b) {
      final byStart = a.sortKey.compareTo(b.sortKey);
      return byStart != 0 ? byStart : a.uid.compareTo(b.uid);
    });
    return out;
  }

  /// The event's own reminder (F-55/F-105): minutes before the start, or
  /// F-105's "na véspera às 19h" as an absolute instant.
  static IcsAlarm? _eventAlarm(DateTime day, DateTime start, int? minutes) {
    if (minutes == null) return null;
    if (minutes == AgendaNotify.eveAt19) {
      final eve = familyInstant(
          DateTime(day.year, day.month, day.day - 1), '19:00');
      return eve == null ? null : IcsAlarm.at(eve);
    }
    return minutes < 0 ? null : IcsAlarm.before(minutes);
  }

  /// "Escola · Lucas: reunião de pais" — the kind in the reader's language,
  /// the child where there is one, and the first line of the text, cut.
  static String eventTitle(Localization l, AgendaKind kind,
      {String? child, String? body}) {
    final head = child == null ? l[kind.labelKey] : '${l[kind.labelKey]} · $child';
    final line = body?.trim().split('\n').first.trim() ?? '';
    if (line.isEmpty) return head;
    final cut = line.length > titleBodyMax
        ? '${line.substring(0, titleBodyMax).trimRight()}…'
        : line;
    return '$head: $cut';
  }

  /// What the sheet counts: the events that will show, not the cancellations.
  static int count(List<IcsEvent> events) =>
      events.where((e) => !e.cancelled).length;

  /// The `calendar-export` analytics props: tokens only, never a name.
  static String layersToken(CalendarExportOptions o) =>
      '${o.handoffs ? 'h' : ''}${o.events ? 'e' : ''}${o.days ? 'd' : ''}';

  static String sizeBucket(int n) => n < 10
      ? 'lt10'
      : n < 50
          ? 'lt50'
          : n < 200
              ? 'lt200'
              : 'gte200';

  /// `entrelares-20261201-20261231.ics` — no family or person name in a file
  /// that travels through share sheets.
  static String fileName(CalendarExportOptions o) =>
      'entrelares-${_ymd(o.from)}-${_ymd(o.to)}.ics';

  /// The calendar the import creates (Apple) or is named after.
  static String calendarName(Localization l, CalendarExportFamily f) =>
      l.format(KApp.calExportCalendarName, [f.familyName]);
}
