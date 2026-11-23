// F-08 — *Exportar para outro calendário* (owner, 20/11/2026).
//
// What the sheet adds over the core rules (calendar_export_rules_test): the
// Premium gate with its own token, the live count, the file handed to the
// platform (here: a recording function), and the "para quem" choice that a
// Visualizador never sees.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/calendar_export_sheet.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, ana, bruno;

final l = Localization(AppLanguage.ptBr);
const family = Family(id: 7, name: 'Silva', plan: 'premium');
const viewer =
    Member(id: 9, fullName: 'Vera Dias', colorSlot: 0, membershipType: 'viewer');

CareSchedule day(int d, int who, {String? handoff}) => CareSchedule(
      id: d,
      scheduleDate: DateTime(2026, 12, d),
      scheduledParentId: who,
      handoffTime: handoff,
    );

FakeCustodyDataSource source() => FakeCustodyDataSource(
      members: const [ana, bruno],
      days: [
        CareSchedule(
            id: 100, scheduleDate: DateTime(2026, 11, 30), scheduledParentId: ana.id),
        day(1, ana.id),
        day(2, bruno.id, handoff: '18:00:00'),
        day(3, bruno.id),
        day(4, ana.id, handoff: '09:00:00'),
      ],
    )..childEvents = [
        ChildEvent(
          id: 1,
          familyId: 7,
          eventDate: DateTime(2026, 12, 3),
          kind: 'school',
          startTime: '08:00',
          createdAt: DateTime.utc(2026, 11, 1),
        ),
      ];

Future<List<(String, String)>> pump(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  bool allowed = true,
  Member? me = ana,
  VoidCallback? onOpenPlan,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final delivered = <(String, String)>[];
  await tester.pumpWidget(AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CalendarExportSheet(
            dataSource: ds,
            family: family,
            members: const [ana, bruno],
            children: const [],
            me: me,
            allowed: allowed,
            agendaEnabled: true,
            visibleMonth: DateTime(2026, 12),
            onOpenPlan: onOpenPlan,
            deliver: (name, text) async => delivered.add((name, text)),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return delivered;
}

String countText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(CalendarExportSheet.countKey)).data!;

void main() {
  testWidgets('a family without Premium meets the gate, which opens the plan',
      (tester) async {
    var opened = 0;
    await pump(tester, source(), allowed: false, onOpenPlan: () => opened++);
    expect(find.byKey(const ValueKey('cal-export-premium')), findsOne);
    expect(find.text(l[KApp.calExportPremium]), findsOne);
    expect(find.byKey(CalendarExportSheet.submitKey), findsNothing);
    expect(find.text(l[KApp.calExportSubmit]), findsNothing);

    await tester.tap(find.text(l[K.famSeePremium]));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('the month on screen, handoffs and events: the count follows '
      'every toggle without a new read', (tester) async {
    final ds = source();
    await pump(tester, ds);
    // Two handoffs (Ana → Bruno on the 2nd, Bruno → Ana on the 4th) and the
    // school event; D-1 (30/11) is read, never exported.
    expect(countText(tester), l.format(KApp.calExportCountMany, [3]));
    expect(ds.periodReads.single.$1, DateTime(2026, 11, 30));
    expect(find.text(l[KApp.calExportTip]), findsOne,
        reason: 'the import tip is said, not a tooltip');

    await tester.tap(find.byKey(const ValueKey('cal-export-events')));
    await tester.pumpAndSettle();
    expect(countText(tester), l.format(KApp.calExportCountMany, [2]));

    await tester.tap(find.byKey(const ValueKey('cal-export-days')));
    await tester.pumpAndSettle();
    // + three runs: Ana 1, Bruno 2–3, Ana 4.
    expect(countText(tester), l.format(KApp.calExportCountMany, [5]));
    expect(ds.periodReads, hasLength(1));
  });

  testWidgets('"só o que envolve você" and the file handed to the platform',
      (tester) async {
    final delivered = await pump(tester, source(), me: bruno);
    await tester.tap(find.text(l[KApp.calExportScopeMine]));
    await tester.pumpAndSettle();
    // Both handoffs involve Bruno; the school event is on his day (3rd).
    expect(countText(tester), l.format(KApp.calExportCountMany, [3]));

    final submit = find.text(l[KApp.calExportSubmit]);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(delivered.single.$1, 'entrelares-20261201-20261231.ics');
    final text = delivered.single.$2;
    expect('BEGIN:VEVENT'.allMatches(text), hasLength(3));
    expect(text, contains('SUMMARY:Entrega: Ana → Bruno'));
    expect(text, contains('X-WR-CALNAME:Entrelares — Silva'));
  });

  testWidgets('nothing to export says so and offers no file', (tester) async {
    final ds = FakeCustodyDataSource(members: const [ana, bruno], days: []);
    final delivered = await pump(tester, ds);
    expect(countText(tester), l[KApp.calExportEmpty]);
    final submit = find.text(l[KApp.calExportSubmit]);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(delivered, isEmpty);
  });

  testWidgets('a Visualizador exports the family, with no "para quem"',
      (tester) async {
    await pump(tester, source(), me: viewer);
    expect(find.text(l[KApp.calExportScopeMine]), findsNothing);
    expect(countText(tester), l.format(KApp.calExportCountMany, [3]));
  });
}
