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

  // F-61 — section 2 of the document: each caregiver's dated account facts.
  group('caregiverTimelines', () {
    final l = Localization(AppLanguage.ptBr);
    final generatedAt = DateTime(2026, 9, 9, 15, 0);

    const stats = [
      CaregiverStat(
          profileId: 1,
          name: 'Ana Prado',
          role: 'Mãe',
          colorSlot: 1,
          plannedDays: 3,
          actualDays: 1,
          projectedDays: 3,
          swapsGiven: 0,
          swapsReceived: 0),
      CaregiverStat(
          profileId: 2,
          name: 'Bruno Prado',
          role: 'Pai',
          colorSlot: 2,
          plannedDays: 2,
          actualDays: 0,
          projectedDays: 2,
          swapsGiven: 0,
          swapsReceived: 0),
    ];

    AccountEventView event(String action,
            {int? actor = 1,
            int? target,
            String? value,
            required DateTime at}) =>
        AccountEventView(
            action: action,
            actorProfileId: actor,
            targetProfileId: target,
            newValue: value,
            createdAtLocal: at);

    List<CaregiverTimeline> run({
      required List<CaregiverAccountView> accounts,
      List<AccountEventView> events = const [],
    }) =>
        caregiverTimelines(
          caregivers: stats,
          accounts: accounts,
          events: events,
          members: _members,
          generatedAtLocal: generatedAt,
          l: l,
        );

    CaregiverTimeline of(List<CaregiverTimeline> ts, int id) =>
        ts.firstWhere((t) => t.profileId == id);

    test('a placeholder: added by the admin, then still without an account, '
        'dated at generation', () {
      final ts = run(
        accounts: [
          CaregiverAccountView(
              profileId: 1, createdAtLocal: DateTime(2026, 7, 1, 9)),
          CaregiverAccountView(
              profileId: 2,
              createdAtLocal: DateTime(2026, 9, 1, 10),
              isPending: true),
        ],
        events: [
          event('pending_member_added',
              target: 2, value: 'Bruno', at: DateTime(2026, 9, 1, 10)),
        ],
      );

      final bruno = of(ts, 2);
      expect(bruno.entries.map((e) => e.text), [
        'Adicionado ao calendário por Ana Prado.',
        'Sem conta no aplicativo até a geração deste relatório.',
      ]);
      expect(bruno.entries.last.atLocal, generatedAt);
      // The founder: the row's birth IS the account's.
      expect(of(ts, 1).entries.map((e) => e.text),
          ['Criou a conta no aplicativo.']);
      expect(of(ts, 1).entries.single.atLocal, DateTime(2026, 7, 1, 9));
    });

    test('a claimed placeholder: added, invited, then the CLAIM date — never '
        'the row creation', () {
      final ts = run(
        accounts: [
          CaregiverAccountView(
              profileId: 2,
              email: 'bruno@example.com',
              createdAtLocal: DateTime(2026, 9, 1, 10)),
        ],
        events: [
          event('pending_member_added',
              target: 2, at: DateTime(2026, 9, 1, 10)),
          event('invitation_created',
              target: 2,
              value: 'bruno@example.com',
              at: DateTime(2026, 9, 2, 8)),
          event('pending_member_claimed',
              actor: 2, target: 2, at: DateTime(2026, 9, 20, 19, 30)),
        ],
      );

      final bruno = of(ts, 2);
      expect(bruno.entries.map((e) => e.text), [
        'Adicionado ao calendário por Ana Prado.',
        'Convite enviado por Ana Prado.',
        'Criou a conta no aplicativo.',
      ]);
      expect(bruno.entries.last.atLocal, DateTime(2026, 9, 20, 19, 30));
    });

    test('a LEGACY invitation row (no target) is matched by e-mail, '
        'case-insensitively; someone else\'s is not', () {
      final ts = run(
        accounts: [
          CaregiverAccountView(
              profileId: 2,
              email: 'Bruno@Example.com',
              createdAtLocal: DateTime(2026, 9, 5)),
        ],
        events: [
          event('invitation_created',
              value: 'bruno@example.com', at: DateTime(2026, 9, 2)),
          event('invitation_created',
              value: 'carla@example.com', at: DateTime(2026, 9, 3)),
        ],
      );

      expect(of(ts, 2).entries.map((e) => e.text), [
        'Convite enviado por Ana Prado.',
        'Criou a conta no aplicativo.',
      ]);
    });

    test('a removed placeholder says by whom; a departed member says it left',
        () {
      final ts = run(
        accounts: [
          CaregiverAccountView(
              profileId: 1,
              createdAtLocal: DateTime(2026, 7, 1),
              leftAtLocal: DateTime(2026, 9, 8)),
          CaregiverAccountView(
              profileId: 2,
              createdAtLocal: DateTime(2026, 9, 1),
              leftAtLocal: DateTime(2026, 9, 6)),
        ],
        events: [
          event('pending_member_added', target: 2, at: DateTime(2026, 9, 1)),
          event('pending_member_removed',
              target: 2, at: DateTime(2026, 9, 6)),
        ],
      );

      expect(of(ts, 2).entries.map((e) => e.text), [
        'Adicionado ao calendário por Ana Prado.',
        'Removido do calendário por Ana Prado.',
      ]);
      expect(of(ts, 1).entries.map((e) => e.text),
          ['Criou a conta no aplicativo.', 'Saiu da família.']);
    });

    test('entries come out oldest first whatever the input order', () {
      final ts = run(
        accounts: [
          CaregiverAccountView(
              profileId: 2,
              createdAtLocal: DateTime(2026, 9, 1)),
        ],
        events: [
          event('pending_member_claimed', target: 2, at: DateTime(2026, 9, 9)),
          event('invitation_created', target: 2, at: DateTime(2026, 9, 2)),
          event('pending_member_added', target: 2, at: DateTime(2026, 9, 1)),
        ],
      );
      final dates = of(ts, 2).entries.map((e) => e.atLocal).toList();
      expect(dates, [...dates]..sort());
      expect(dates.length, 3);
    });

    test('an unknown actor reads as the system; a caregiver with no account '
        'row has no entries', () {
      final ts = run(
        accounts: [
          CaregiverAccountView(profileId: 2, isPending: true),
        ],
        events: [
          event('pending_member_added',
              actor: null, target: 2, at: DateTime(2026, 9, 1)),
        ],
      );
      expect(of(ts, 2).entries.first.text,
          'Adicionado ao calendário por Sistema.');
      expect(of(ts, 1).entries, isEmpty);
    });

    test('no sentence qualifies conduct — both catalogs, pinned', () {
      const banned = ['sozinh', 'sem consultar', 'alone', 'without consult',
        'unilateral', 'decidiu', 'decided'];
      for (final loc in [l, Localization(AppLanguage.en)]) {
        for (final key in [
          K.pdfDocCaregiversLead,
          K.pdfDocTlAdded,
          K.pdfDocTlInvited,
          K.pdfDocTlAccountCreated,
          K.pdfDocTlNoAccountYet,
          K.pdfDocTlRemoved,
          K.pdfDocTlLeft,
        ]) {
          final text = loc[key].toLowerCase();
          for (final word in banned) {
            expect(text, isNot(contains(word)), reason: '$key / $word');
          }
        }
      }
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

    test('F-61: section 2 is built only when the account trail was given', () {
      expect(build().caregiverTimelines, isEmpty);

      final report = buildCustodyReport(
        familyName: 'Família Prado',
        childName: null,
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 22),
        today: _today,
        days: _period(),
        members: _members,
        auditLogs: const [],
        roleLabelOf: (id) => 'Papel',
        diffFor: (_) => const [],
        generatedBy: 'Ana Prado',
        generatedAtLocal: DateTime(2026, 8, 19, 21, 5),
        appVersion: '0.2.20+22',
        l: l,
        accounts: [
          for (final m in _members)
            CaregiverAccountView(
                profileId: m.id, createdAtLocal: DateTime(2026, 7, 1)),
        ],
      );
      // One timeline per VISIBLE caregiver, in the table's order.
      expect(report.caregiverTimelines.map((t) => t.profileId),
          report.caregivers.map((c) => c.profileId));
      expect(report.caregiverTimelines.first.role, 'Papel');
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
