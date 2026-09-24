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
}
