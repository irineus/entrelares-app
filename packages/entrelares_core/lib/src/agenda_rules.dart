/// F-55 — the day agenda's client-side mirror.
///
/// The server is the rule (`agenda_validate`, `agenda_editable_row`): flag on,
/// an active member, today on, the Premium gate, the free note cap, the day
/// cap, the text limit. This file mirrors what the sheet needs to say BEFORE a
/// round trip — with the RPC's own PT-BR sentences, byte for byte, so a rule
/// that trips on either side reads the same (the `CustomRoleRules` convention)
/// — and the pure shape of the timeline.
library;

import 'date_math.dart';
import 'localization/k_app.dart';

/// The closed kinds (owner, 24/09/2026). The wire key travels; the label is
/// the reader's language (the F-44/F-52 rule).
enum AgendaKind {
  school('school'),
  health('health'),
  medicine('medicine'),
  activity('activity'),
  free('free'),
  note('note'),
  other('other');

  final String wire;
  const AgendaKind(this.wire);

  static AgendaKind? parse(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }

  /// Every kind but the note needs the child, and is Premium.
  bool get isStructured => this != note;

  /// The catalog key of the label — the reader's language, never the wire.
  String get labelKey => switch (this) {
        school => KApp.agendaKindSchool,
        health => KApp.agendaKindHealth,
        medicine => KApp.agendaKindMedicine,
        activity => KApp.agendaKindActivity,
        free => KApp.agendaKindFree,
        note => KApp.agendaKindNote,
        other => KApp.agendaKindOther,
      };
}

/// One event, as the timeline needs it — the app maps its row onto this.
class AgendaEntry {
  final int id;
  final AgendaKind kind;

  /// `HH:mm`, or null.
  final String? start;
  final String? end;
  final DateTime createdAt;

  const AgendaEntry({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.start,
    this.end,
  });
}

abstract final class AgendaRules {
  /// The picker's order: the note first — it is the free door and the old
  /// observation — then the day as a parent reads it.
  static const List<AgendaKind> pickerOrder = [
    AgendaKind.note,
    AgendaKind.school,
    AgendaKind.activity,
    AgendaKind.health,
    AgendaKind.medicine,
    AgendaKind.free,
    AgendaKind.other,
  ];

  /// The column CHECK; the operator key is at most this.
  static const int hardTextMax = 2000;

  /// A day is written from TODAY on; the past is read-only for everyone, the
  /// admin mode included (the F-67 relato covers the past).
  static bool canWriteDay(DateTime day, DateTime today) =>
      !dateOnly(day).isBefore(dateOnly(today));

  /// Whether this family is limited to the note: Premium-only on, not Premium.
  static bool freeLimited({required bool isPremium, required bool premiumOnly}) =>
      premiumOnly && !isPremium;

  /// Whether an EXISTING event may still be changed or removed by this
  /// family: a structured event of a family that lapsed is read-only.
  static bool canChange({
    required AgendaKind kind,
    required DateTime day,
    required DateTime today,
    required bool freeLimited,
  }) =>
      canWriteDay(day, today) && !(kind.isStructured && freeLimited);

  /// The timeline: untimed entries first (the note, a free morning with no
  /// hour), then by start, then by the order they were written.
  static List<T> timeline<T>(List<T> entries, AgendaEntry Function(T) view) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      final x = view(a);
      final y = view(b);
      final xs = x.start;
      final ys = y.start;
      if (xs == null && ys != null) return -1;
      if (xs != null && ys == null) return 1;
      if (xs != null && ys != null) {
        final byStart = xs.compareTo(ys);
        if (byStart != 0) return byStart;
      }
      return x.createdAt.compareTo(y.createdAt);
    });
    return sorted;
  }

  /// "07:30–12:00", "07:30", or null for an untimed entry.
  static String? timeRange(String? start, String? end) {
    if (start == null) return null;
    return end == null ? start : '$start–$end';
  }

  /// Notes still available today for a limited family (never below zero).
  static int notesLeft({required int notesOnDay, required int freeNotesPerDay}) {
    final left = freeNotesPerDay - notesOnDay;
    return left < 0 ? 0 : left;
  }

  /// The client's half of `agenda_validate`, in the RPC's words. Null when the
  /// draft may be sent.
  static String? validate({
    required AgendaKind kind,
    required int? childId,
    required String? start,
    required String? end,
    required String? body,
    required int maxChars,
  }) {
    final clean = (body ?? '').trim();
    if (clean.isNotEmpty && clean.runes.length > maxChars) {
      return 'O texto do evento é limitado a $maxChars caracteres.';
    }
    if (kind == AgendaKind.note && clean.isEmpty) {
      return 'Escreva o texto da nota.';
    }
    if (end != null && (start == null || end.compareTo(start) <= 0)) {
      return 'O horário de fim precisa vir depois do início.';
    }
    if (kind.isStructured && childId == null) {
      return 'Escolha a criança do evento. Se ainda não há criança cadastrada, '
          'o administrador cadastra em Família.';
    }
    return null;
  }
  // ── F-55 (PR 3): the routine ──────────────────────────────────────────────

  /// `save_child_routine`'s refusal for a routine with no weekday, in its
  /// words — the sheet says it before the round trip.
  static const String noWeekday =
      'Escolha pelo menos um dia da semana para a rotina.';

  /// The days a routine writes: every date from [from] to [until] (both
  /// inclusive, date-only) whose ISO weekday (`DateTime.weekday`) is in
  /// [weekdays] — the server's loop, for the editor's preview and tests.
  static List<DateTime> routineDays(
      DateTime from, DateTime until, Iterable<int> weekdays) {
    final wanted = weekdays.toSet();
    final days = <DateTime>[];
    var d = DateTime(from.year, from.month, from.day);
    final last = DateTime(until.year, until.month, until.day);
    while (!d.isAfter(last)) {
      if (wanted.contains(d.weekday)) days.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return days;
  }

  /// "seg, qua, sex" — the weekdays in week order (Monday first), each
  /// through [abbrev] (the reader's language).
  static String weekdaysLabel(
          Iterable<int> weekdays, String Function(int weekday) abbrev) =>
      (weekdays.toSet().toList()..sort()).map(abbrev).join(', ');

  /// The agenda's Histórico: one line per created or deleted event — and ONE
  /// line for what a routine wrote (or removed) in one go, the F-51 fold. A
  /// routine's events share the batch and the instant of the transaction
  /// that wrote them, so a re-apply is a new line, not a merge with the
  /// first. A note converted from the observation was added by nobody: no
  /// "added" line. Newest first; a line's events in date order.
  static List<AgendaTrailLine<T>> trail<T>(
    Iterable<T> events, {
    required DateTime Function(T) date,
    required DateTime Function(T) createdAt,
    required DateTime? Function(T) deletedAt,
    required String? Function(T) batchId,
    required bool Function(T) converted,
  }) {
    final lines = <String, AgendaTrailLine<T>>{};
    var seq = 0;
    void put(T e, DateTime at, bool deleted) {
      final batch = batchId(e);
      final key = batch == null
          ? 'e${seq++}'
          : '$batch|$deleted|${at.microsecondsSinceEpoch}';
      (lines[key] ??= AgendaTrailLine<T>(
              key: key, at: at, deleted: deleted, batchId: batch, events: []))
          .events
          .add(e);
    }

    for (final e in events) {
      if (!converted(e)) put(e, createdAt(e), false);
      final gone = deletedAt(e);
      if (gone != null) put(e, gone, true);
    }
    for (final line in lines.values) {
      line.events.sort((a, b) => date(a).compareTo(date(b)));
    }
    return lines.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }
}

/// F-55 PR 4 — who an agenda item's notice and reminder go to. The wire
/// keys are `child_events.notify_to`'s CHECK.
enum AgendaAudience {
  none('none'),
  self('self'),
  responsible('responsible'),
  family('family');

  const AgendaAudience(this.wire);
  final String wire;

  static AgendaAudience parse(String? wire) =>
      values.where((a) => a.wire == wire).firstOrNull ?? none;
}

/// F-55 PR 4 — the creator's choice: who, which channels (push and/or in-app,
/// never e-mail) and the reminder offset. The offsets are FIXED (T-84: a
/// closed catalogue, not a key).
class AgendaNotify {
  const AgendaNotify({
    this.to = AgendaAudience.none,
    this.push = true,
    this.inApp = true,
    this.remindMinutes,
  });

  static const none = AgendaNotify();
  static const List<int> remindOffsets = [0, 15, 30, 60];

  final AgendaAudience to;
  final bool push;
  final bool inApp;
  final int? remindMinutes;

  /// The client's half of `agenda_notify_validate`, in its words. Null when
  /// the choice may be sent. [start] is the item's start time, if any.
  String? validate({required String? start}) {
    if (to != AgendaAudience.none && !push && !inApp) {
      return 'Escolha pelo menos um canal da notificação: no celular ou no app.';
    }
    final remind = remindMinutes;
    if (remind != null) {
      if (!remindOffsets.contains(remind)) {
        return 'O lembrete é na hora ou 15, 30 ou 60 minutos antes.';
      }
      if (start == null) return 'O lembrete precisa do horário de início.';
      if (to == AgendaAudience.none) return 'Escolha quem recebe o lembrete.';
    }
    return null;
  }

  /// What is actually sent: no audience means no channel choice and no
  /// reminder; no start time means no reminder.
  AgendaNotify normalized({required String? start}) => to == AgendaAudience.none
      ? none
      : AgendaNotify(
          to: to,
          push: push,
          inApp: inApp,
          remindMinutes: start == null ? null : remindMinutes,
        );
}

/// One line of the agenda's Histórico ([AgendaRules.trail]).
class AgendaTrailLine<T> {
  const AgendaTrailLine({
    required this.key,
    required this.at,
    required this.deleted,
    required this.events,
    this.batchId,
  });

  /// Stable within one load — what the reader's "show the days" remembers.
  final String key;
  final DateTime at;
  final bool deleted;
  final String? batchId;
  final List<T> events;

  /// What a routine wrote or removed in one go (folded).
  bool get isRoutine => batchId != null;
}
