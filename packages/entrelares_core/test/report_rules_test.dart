/// The reports mirror — the numbers the "Resumo do Período" screen shows and
/// the F-33 document prints are ONE computation here, so the parity the web
/// keeps by comment (`ReportsSummary.ComputeStats` ↔ `ReportPdfService.Build`)
/// is structural. The expectations below were transcribed from those two files
/// on 19/08/2026 and are the contract (U-20 projection, U-07 given/received).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

const _members = [
  MemberView(id: 1, fullName: 'Ana Prado', colorSlot: 1),
  MemberView(id: 2, fullName: 'Bruno Prado', colorSlot: 2),
  MemberView(id: 3, fullName: 'Carla Souza', colorSlot: 3),
];

final _today = DateTime(2026, 8, 19);

/// Period: 15/08 to 22/08. Past days are 15–18, future days 19–22 (today
/// itself is NOT past — `scheduleDate < today`, strictly).
List<ReportDay> _period() => [
      // Past, as planned.
      ReportDay(scheduleDate: DateTime(2026, 8, 15), scheduledParentId: 1),
      ReportDay(scheduleDate: DateTime(2026, 8, 16), scheduledParentId: 1),
      // Past, swapped: Ana planned, Bruno actually had the day.
      ReportDay(
          scheduleDate: DateTime(2026, 8, 17),
          scheduledParentId: 1,
          actualParentId: 2),
      // Past, as planned (Bruno's own day, actual echoing the plan is NOT a
      // swap — the web compares actual != scheduled).
      ReportDay(
          scheduleDate: DateTime(2026, 8, 18),
          scheduledParentId: 2,
          actualParentId: 2),
      // Today and the future.
      ReportDay(scheduleDate: DateTime(2026, 8, 19), scheduledParentId: 2),
      ReportDay(scheduleDate: DateTime(2026, 8, 20), scheduledParentId: 1),
      // Future, already-approved swap: Bruno planned, Carla will have it.
      ReportDay(
          scheduleDate: DateTime(2026, 8, 21),
          scheduledParentId: 2,
          actualParentId: 3),
      ReportDay(scheduleDate: DateTime(2026, 8, 22), scheduledParentId: 1),
    ];

CaregiverStat _statOf(List<CaregiverStat> stats, int id) =>
    stats.firstWhere((s) => s.profileId == id);

void main() {
  group('caregiverStats — the default view (no projection)', () {
    final stats = caregiverStats(
      members: _members,
      days: _period(),
      today: _today,
      includeFutureSwaps: false,
    );

    test('planned counts every day of the period assigned to the member', () {
      expect(_statOf(stats, 1).plannedDays, 5); // 15,16,17,20,22
      expect(_statOf(stats, 2).plannedDays, 3); // 18,19,21
      expect(_statOf(stats, 3).plannedDays, 0);
    });

    test('actual counts REALIZED days only, with actual ?? scheduled', () {
      expect(_statOf(stats, 1).actualDays, 2); // 15,16 (17 went to Bruno)
      expect(_statOf(stats, 2).actualDays, 2); // 17 (received) + 18
      expect(_statOf(stats, 3).actualDays, 0); // her swap is in the future
    });

    test('today is not a realized day — the comparison is strict', () {
      // 19/08 is Bruno's and is NOT counted in actualDays above (2, not 3).
      expect(_statOf(stats, 2).actualDays, isNot(3));
    });

    test('U-07 given/received ignore future swaps while the toggle is off',
        () {
      expect(_statOf(stats, 1).swapsGiven, 1); // the 17th
      expect(_statOf(stats, 2).swapsReceived, 1); // the 17th
      expect(_statOf(stats, 2).swapsGiven, 0); // the 21st is future
      expect(_statOf(stats, 3).swapsReceived, 0);
    });

    test('total swaps counts realized swaps only', () {
      expect(
        totalVisibleSwaps(
            days: _period(), today: _today, includeFutureSwaps: false),
        1,
      );
    });

    test('projected is computed even when it is not shown (U-20)', () {
      // The screen hides the row; the number is the same one the projection
      // would print, so turning the toggle on cannot change it.
      expect(_statOf(stats, 1).projectedDays, 4); // 15,16,20,22
      expect(_statOf(stats, 2).projectedDays, 3); // 17,18,19
      expect(_statOf(stats, 3).projectedDays, 1); // 21
    });

    test('every member gets a card, including the one with nothing', () {
      expect(stats.map((s) => s.profileId), [1, 2, 3]);
      expect(hasSummaryData(stats), isTrue);
    });
  });

  group('caregiverStats — with accepted future swaps (U-20/U-07)', () {
    final stats = caregiverStats(
      members: _members,
      days: _period(),
      today: _today,
      includeFutureSwaps: true,
    );

    test('given/received now include the accepted future swap', () {
      expect(_statOf(stats, 2).swapsGiven, 1); // the 21st
      expect(_statOf(stats, 3).swapsReceived, 1); // the 21st
      expect(
        totalVisibleSwaps(
            days: _period(), today: _today, includeFutureSwaps: true),
        2,
      );
    });

    test('planned and actual are untouched by the toggle', () {
      expect(_statOf(stats, 1).plannedDays, 5);
      expect(_statOf(stats, 1).actualDays, 2);
    });
  });

  group('hasSummaryData', () {
    test('a period with no assignment at all shows the empty state', () {
      final stats = caregiverStats(
        members: _members,
        days: const [],
        today: _today,
        includeFutureSwaps: false,
      );
      expect(hasSummaryData(stats), isFalse);
    });
  });

  group('reportCaregivers — the document table', () {
    test('drops members the period does not involve, orders by planned desc',
        () {
      final stats = caregiverStats(
        members: _members,
        days: _period(),
        today: _today,
        includeFutureSwaps: false,
      );
      final table = reportCaregivers(stats, includeFutureSwaps: false);

      // Carla has planned = actual = 0 and only a FUTURE received swap, which
      // the default view does not count — she stays out.
      expect(table.map((c) => c.profileId), [1, 2]);
    });

    test('a received future swap alone makes a caregiver visible', () {
      final stats = caregiverStats(
        members: _members,
        days: _period(),
        today: _today,
        includeFutureSwaps: true,
      );
      final table = reportCaregivers(stats, includeFutureSwaps: true);

      expect(table.map((c) => c.profileId), [1, 2, 3]);
      expect(_statOf(table, 3).plannedDays, 0);
      expect(_statOf(table, 3).swapsReceived, 1);
    });

    test('ties on planned days fall back to the name', () {
      const tied = [
        MemberView(id: 1, fullName: 'Zoe'),
        MemberView(id: 2, fullName: 'Ana'),
      ];
      final days = [
        ReportDay(scheduleDate: DateTime(2026, 8, 15), scheduledParentId: 1),
        ReportDay(scheduleDate: DateTime(2026, 8, 16), scheduledParentId: 2),
      ];
      final table = reportCaregivers(
        caregiverStats(
            members: tied,
            days: days,
            today: _today,
            includeFutureSwaps: false),
        includeFutureSwaps: false,
      );
      expect(table.map((c) => c.name), ['Ana', 'Zoe']);
    });
  });

  group('buildCustodyReport', () {
    final l = Localization(AppLanguage.ptBr);

    final logs = [
      AuditLogView(
        id: 10,
        affectedDate: DateTime(2026, 8, 17),
        createdAtLocal: DateTime(2026, 8, 16, 9, 30),
        action: 'UPDATE',
        performedById: 1,
        oldData: const {'actual_parent_id': null},
        newData: const {'actual_parent_id': 2},
      ),
      AuditLogView(
        id: 11,
        affectedDate: DateTime(2026, 8, 20),
        createdAtLocal: DateTime(2026, 8, 15, 8, 0),
        action: 'INSERT',
        performedById: 99, // no such member
        newData: const {'scheduled_parent_id': 1},
      ),
    ];

    CustodyReport build({
      bool future = false,
      Map<int, SwapOrigin> origins = const {},
      String? childName,
    }) =>
        buildCustodyReport(
          familyName: 'Família Prado',
          childName: childName,
          start: DateTime(2026, 8, 15),
          end: DateTime(2026, 8, 22),
          today: _today,
          days: _period(),
          members: _members,
          auditLogs: logs,
          roleLabelOf: (id) => id == 1 ? 'Mãe' : 'Pai',
          diffFor: (log) =>
              computeAuditDiff(log: log, profiles: _members, l: l),
          generatedBy: 'Ana Prado',
          generatedAtLocal: DateTime(2026, 8, 19, 21, 5),
          appVersion: '0.2.20+22',
          l: l,
          resolutionOrigins: origins,
          includeAcceptedFutureSwaps: future,
        );

    test('carries the period, the day count and the role labels', () {
      final report = build();
      expect(report.totalDays, 8);
      expect(report.caregivers.first.role, 'Mãe');
      expect(report.includesFutureSwaps, isFalse);
      expect(report.totalSwaps, 1);
    });

    test('the child name is trimmed, and blank means absent', () {
      expect(build(childName: '  Lia  ').childName, 'Lia');
      expect(build(childName: '   ').childName, isNull);
      expect(build().childName, isNull);
    });

    test('entries run OLDEST first — a document reads forward', () {
      final report = build();
      expect(report.auditEntries.map((e) => e.timestampLocal),
          [DateTime(2026, 8, 15, 8, 0), DateTime(2026, 8, 16, 9, 30)]);
    });

    test('an unknown performer falls back to the system label', () {
      final report = build();
      expect(report.auditEntries.first.performedBy, l[K.pdfDocSystem]);
      expect(report.auditEntries.last.performedBy, 'Ana Prado');
    });

    test('F-45: the origin sentence and both F-44 texts ride the entry', () {
      final report = build(origins: {
        10: const SwapOrigin(
          requestingProfileId: 1,
          targetProfileId: 2,
          status: 'approved',
          resolvedBy: 'user',
          requestMessage: 'Tenho consulta médica',
          approvalNote: 'Sem problema',
        ),
      });

      final swapped = report.auditEntries.last;
      expect(swapped.originText, contains('Ana Prado'));
      expect(swapped.originText, contains('Bruno Prado'));
      expect(swapped.originMessage, 'Tenho consulta médica');
      expect(swapped.originNote, 'Sem problema');

      // A manual edit has no origin at all.
      expect(report.auditEntries.first.originText, isNull);
    });

    test('the diff callback is what fills the entry changes', () {
      final report = build();
      final swapped = report.auditEntries.last;
      expect(swapped.changes.single.label, l[K.auditFieldActualParent]);
      expect(swapped.changes.single.to, 'Bruno Prado');
    });

    test('F-61: the authorship lines ride the entry; no context, none', () {
      final report = buildCustodyReport(
        familyName: 'Família Prado',
        childName: null,
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 22),
        today: _today,
        days: _period(),
        members: _members,
        auditLogs: [
          ...logs,
          AuditLogView(
            id: 12,
            affectedDate: DateTime(2026, 8, 21),
            createdAtLocal: DateTime(2026, 8, 17, 8, 0),
            action: 'INSERT',
            performedById: 1,
            newData: const {'scheduled_parent_id': 2},
            context: const AuditContext(
                scheduledParentHasAccount: false, actorIsAdmin: true),
          ),
        ],
        roleLabelOf: (id) => id == 1 ? 'Mãe' : 'Pai',
        diffFor: (log) => computeAuditDiff(log: log, profiles: _members, l: l),
        generatedBy: 'Ana Prado',
        generatedAtLocal: DateTime(2026, 8, 19, 21, 5),
        appVersion: '0.2.20+22',
        l: l,
      );

      final stamped = report.auditEntries.last;
      expect(stamped.authorshipLines,
          ['Bruno Prado ainda não tinha conta no aplicativo neste momento.']);
      for (final older in report.auditEntries.take(2)) {
        expect(older.authorshipLines, isEmpty);
      }
    });

    test('the projection reaches the document numbers', () {
      final report = build(future: true);
      expect(report.includesFutureSwaps, isTrue);
      expect(report.totalSwaps, 2);
      expect(report.caregivers.map((c) => c.profileId), [1, 2, 3]);
    });
  });
}
