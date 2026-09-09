/// Client mirrors of the reports — ported from `entrelares-app`
/// `Entrelares/Services/ReportPdfService.cs` (Build) and the counting block of
/// `Entrelares/Pages/ReportsSummary.razor` (ComputeStats).
///
/// **Why one file for both.** The on-screen "Resumo do Período" and the F-33
/// document must show the SAME numbers — in the web that is a comment asking
/// two code paths to stay in step ("Counting expressions mirror
/// ReportPdfService.Build"). Here they are literally one function: the screen
/// and the report call [caregiverStats], and the report only adds the
/// visibility filter and the ordering a printed table needs.
///
/// No new server surface: every number comes from rows the family already
/// reads under RLS.
library;

import 'audit_rules.dart';
import 'calendar_rules.dart' show MemberView;
import 'date_math.dart';
import 'localization/k.dart';
import 'localization/localization.dart';

/// The slice of a `care_schedules` row the report counts. Dated, unlike
/// [DayAssignment]: every count here splits on realized (past) vs. future.
class ReportDay {
  final DateTime scheduleDate; // date-only
  final int scheduledParentId;
  final int? actualParentId;

  const ReportDay({
    required this.scheduleDate,
    required this.scheduledParentId,
    this.actualParentId,
  });
}

/// Planned-vs-actual for one caregiver over the period. Same semantics on the
/// screen and in the document, by construction.
class CaregiverStat {
  final int profileId;
  final String name;
  final String role;

  /// F-27: the member's persistent color slot — the screen paints the card
  /// with it; the document ignores it.
  final int? colorSlot;

  /// Every day of the period assigned to them.
  final int plannedDays;

  /// REALIZED (past) days where they were the real responsible.
  final int actualDays;

  /// U-20: `actual ?? scheduled` over the WHOLE period — approval writes
  /// `actual_parent_id` immediately, even for future days. Always computed;
  /// only SHOWN when the reader asked for the projection.
  final int projectedDays;

  /// U-07: days they gave away (scheduled = them, actual = someone else).
  final int swapsGiven;

  /// U-07: days they received (actual = them, scheduled = someone else).
  final int swapsReceived;

  const CaregiverStat({
    required this.profileId,
    required this.name,
    required this.role,
    required this.colorSlot,
    required this.plannedDays,
    required this.actualDays,
    required this.projectedDays,
    required this.swapsGiven,
    required this.swapsReceived,
  });
}

/// A swap the current view counts: the actual responsible differs from the
/// plan, and the day is realized (past) unless the projection includes future
/// ones. Mirror of `ReportsSummary.IsVisibleSwap`.
bool isVisibleSwap(
  ReportDay day, {
  required DateTime today,
  required bool includeFutureSwaps,
}) =>
    day.actualParentId != null &&
    day.actualParentId != day.scheduledParentId &&
    (includeFutureSwaps || day.scheduleDate.isBefore(dateOnly(today)));

/// The per-member numbers, in the order the members were given — this is what
/// the Resumo screen renders (one card per family member, including the ones
/// with nothing in the period, exactly like the web).
List<CaregiverStat> caregiverStats({
  required List<MemberView> members,
  required List<ReportDay> days,
  required DateTime today,
  required bool includeFutureSwaps,
  String Function(int profileId)? roleLabelOf,
}) {
  final floor = dateOnly(today);

  return [
    for (final m in members)
      CaregiverStat(
        profileId: m.id,
        name: m.fullName,
        role: roleLabelOf?.call(m.id) ?? '',
        colorSlot: m.colorSlot,
        plannedDays: days.where((d) => d.scheduledParentId == m.id).length,
        actualDays: days
            .where((d) =>
                d.scheduleDate.isBefore(floor) &&
                (d.actualParentId ?? d.scheduledParentId) == m.id)
            .length,
        projectedDays: days
            .where((d) => (d.actualParentId ?? d.scheduledParentId) == m.id)
            .length,
        swapsGiven: days
            .where((d) =>
                isVisibleSwap(d,
                    today: today, includeFutureSwaps: includeFutureSwaps) &&
                d.scheduledParentId == m.id)
            .length,
        swapsReceived: days
            .where((d) =>
                isVisibleSwap(d,
                    today: today, includeFutureSwaps: includeFutureSwaps) &&
                d.actualParentId == m.id)
            .length,
      ),
  ];
}

/// Total swaps over the period under the same visibility rule.
int totalVisibleSwaps({
  required List<ReportDay> days,
  required DateTime today,
  required bool includeFutureSwaps,
}) =>
    days
        .where((d) => isVisibleSwap(d,
            today: today, includeFutureSwaps: includeFutureSwaps))
        .length;

/// Mirror of `ReportsSummary.HasData`: a period with no assignment at all
/// gets the empty state instead of a wall of zeros.
bool hasSummaryData(List<CaregiverStat> stats) =>
    stats.any((s) => s.plannedDays > 0);

/// The document's caregiver table: only members the period actually involves,
/// ordered by planned days (desc) then by name. Mirror of the `Where` +
/// `OrderByDescending` in `ReportPdfService.Build` — including the subtle
/// part: SwapsReceived alone can make a caregiver visible, because a member
/// whose only involvement is a received FUTURE swap has planned = actual = 0
/// while the projection is on.
List<CaregiverStat> reportCaregivers(
  List<CaregiverStat> stats, {
  required bool includeFutureSwaps,
}) {
  final visible = [
    for (final s in stats)
      if (s.plannedDays > 0 ||
          s.actualDays > 0 ||
          (includeFutureSwaps ? s.projectedDays : 0) > 0 ||
          s.swapsReceived > 0)
        s,
  ];
  visible.sort((a, b) {
    final byPlanned = b.plannedDays.compareTo(a.plannedDays);
    return byPlanned != 0 ? byPlanned : a.name.compareTo(b.name);
  });
  return visible;
}

/// One audit-log row of the period as the F-33 document prints it.
class ReportAuditEntry {
  final DateTime affectedDate;
  final DateTime timestampLocal;
  final String actionLabel;
  final String performedBy;
  final List<AuditFieldChange> changes;

  /// F-45: when the change was produced by a swap workflow, the origin
  /// sentence and the F-44 texts — the motivation that makes the paid report
  /// genuinely richer. Null for manual edits.
  final String? originText;
  final String? originMessage;
  final String? originNote;

  /// F-61: the dated facts beyond the diff — an assignee without an account
  /// at that instant, the admin's direct change. Empty for rows older than
  /// F-61, whose context is unknown.
  final List<String> authorshipLines;

  const ReportAuditEntry({
    required this.affectedDate,
    required this.timestampLocal,
    required this.actionLabel,
    required this.performedBy,
    required this.changes,
    this.originText,
    this.originMessage,
    this.originNote,
    this.authorshipLines = const [],
  });
}

/// The assembled consolidated history report (F-33). Pure data built by
/// [buildCustodyReport] from the family's own RLS-scoped reads; the renderer
/// only lays it out.
class CustodyReport {
  final String familyName;

  /// Optional free-text child name typed at generation (not stored — there is
  /// no child entity yet; multi-child is F-07). Omitted when blank.
  final String? childName;

  final DateTime periodStart;
  final DateTime periodEnd;

  /// Device-local time (matches the on-screen timeline) — honest and
  /// consistent; the report footer states it.
  final DateTime generatedAtLocal;
  final String generatedBy;
  final String appVersion;

  final List<CaregiverStat> caregivers;
  final int totalSwaps;
  final List<ReportAuditEntry> auditEntries;

  /// U-20: built with "considerar trocas futuras já aceitas" — the projected
  /// column is printed and every swap count includes accepted future swaps.
  final bool includesFutureSwaps;

  const CustodyReport({
    required this.familyName,
    required this.childName,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAtLocal,
    required this.generatedBy,
    required this.appVersion,
    required this.caregivers,
    required this.totalSwaps,
    required this.auditEntries,
    required this.includesFutureSwaps,
  });

  int get totalDays =>
      dateOnly(periodEnd).difference(dateOnly(periodStart)).inDays + 1;
}

/// Pure report assembly — no I/O — so the paid content contract is unit-tested
/// directly. Mirror of `ReportPdfService.Build`.
CustodyReport buildCustodyReport({
  required String familyName,
  required String? childName,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required List<ReportDay> days,
  required List<MemberView> members,
  required List<AuditLogView> auditLogs,
  required String Function(int profileId) roleLabelOf,
  required List<AuditFieldChange> Function(AuditLogView log) diffFor,
  required String generatedBy,
  required DateTime generatedAtLocal,
  required String appVersion,
  // U-13: the report is read by whoever generated it, so the labels follow
  // THEIR language. Passed in rather than resolved inside so the function
  // stays pure.
  required Localization l,
  // F-45: log id → the swap request whose resolution produced it. A report
  // without the lookup (or a log without a request) simply omits the origin.
  Map<int, SwapOrigin> resolutionOrigins = const {},
  bool includeAcceptedFutureSwaps = false,
}) {
  final stats = caregiverStats(
    members: members,
    days: days,
    today: today,
    includeFutureSwaps: includeAcceptedFutureSwaps,
    roleLabelOf: roleLabelOf,
  );

  final entries = [...auditLogs]
    ..sort((a, b) => a.createdAtLocal.compareTo(b.createdAtLocal));

  return CustodyReport(
    familyName: familyName,
    childName: (childName == null || childName.trim().isEmpty)
        ? null
        : childName.trim(),
    periodStart: dateOnly(start),
    periodEnd: dateOnly(end),
    generatedAtLocal: generatedAtLocal,
    generatedBy: generatedBy,
    appVersion: appVersion,
    caregivers:
        reportCaregivers(stats, includeFutureSwaps: includeAcceptedFutureSwaps),
    totalSwaps: totalVisibleSwaps(
      days: days,
      today: today,
      includeFutureSwaps: includeAcceptedFutureSwaps,
    ),
    auditEntries: [
      for (final log in entries)
        _entryFor(log, resolutionOrigins[log.id], members, diffFor, l),
    ],
    includesFutureSwaps: includeAcceptedFutureSwaps,
  );
}

ReportAuditEntry _entryFor(
  AuditLogView log,
  SwapOrigin? origin,
  List<MemberView> members,
  List<AuditFieldChange> Function(AuditLogView) diffFor,
  Localization l,
) {
  String? performer;
  if (log.performedById != null) {
    for (final m in members) {
      if (m.id == log.performedById) performer = m.fullName;
    }
  }

  return ReportAuditEntry(
    affectedDate: dateOnly(log.affectedDate),
    timestampLocal: log.createdAtLocal,
    actionLabel: reportActionLabel(log.action, l),
    performedBy: performer ?? l[K.pdfDocSystem],
    changes: diffFor(log),
    originText:
        origin == null ? null : resolutionOriginText(origin, members, l),
    originMessage: origin?.requestMessage,
    originNote: origin?.approvalNote,
    authorshipLines: authorshipLines(log: log, profiles: members, l: l),
  );
}
