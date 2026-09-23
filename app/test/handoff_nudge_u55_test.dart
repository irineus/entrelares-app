// U-55 — a plan born without a handoff time: the admin's strip under the
// Hoje card, the "Horário das trocas" sheet that fills every future
// transition day in one call, and the per-device dismissal.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/handoff_nudge_prefs.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'calendar_slice_test.dart'
    show FakeCustodyDataSource, pickTime, row, tapSheet, today;

final _pt = Localization(AppLanguage.ptBr);

const _admin = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    isAdmin: true,
    familyId: 7);
const _member = Member(
    id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', familyId: 7);

class _MemoryPrefs implements HandoffNudgePrefs {
  final dismissed = <int>{};
  @override
  bool isDismissed(int familyId) => dismissed.contains(familyId);
  @override
  Future<void> dismiss(int familyId) async => dismissed.add(familyId);
}

/// Two weeks of a 7/7 plan from today — transitions on day 0 and day 7 —
/// with a handoff time on [timeOnDay] when given.
List<CareSchedule> _plan({int? timeOnDay}) => [
      for (var i = 0; i < 14; i++)
        row(100 + i, DateTime(today.year, today.month, today.day + i),
            i < 7 ? 1 : 2,
            handoffTime: i == timeOnDay ? '18:00:00' : null),
    ];

Widget _app(FakeCustodyDataSource ds, {HandoffNudgePrefs? prefs}) => AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
          dataSource: ds,
          adminMode: AdminMode(),
          handoffNudgePrefs: prefs,
        ),
      ),
    );

Finder get _strip => find.byKey(const Key('handoff-nudge'));

void main() {
  testWidgets('an admin on a plan with no handoff time sees the strip, and '
      'the sheet fills every future transition in ONE call', (tester) async {
    final ds =
        FakeCustodyDataSource(members: [_admin, _member], days: _plan());
    await tester.pumpWidget(_app(ds));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(find.text(_pt[K.handoffNudgeMessage]), findsOneWidget);

    await tapSheet(tester, find.text(_pt[K.handoffNudgeAction]));
    expect(find.text(_pt[K.handoffRangeTitle]), findsOneWidget);

    // No default time: "Aplicar" with nothing picked says so on the field
    // and writes nothing.
    await tapSheet(tester, find.text(_pt[K.handoffRangeApply]));
    expect(find.text(_pt[K.handoffRangeRequired]), findsOneWidget);
    expect(ds.handoffRanges, isEmpty);

    await pickTime(tester, find.byKey(const Key('handoffRangeTime')),
        hour: 18, minute: 30);
    await tapSheet(tester, find.text(_pt[K.handoffRangeApply]));

    final call = ds.handoffRanges.single;
    expect(call.from, dateOnly(today));
    expect(call.to, isNull, reason: 'every future transition, no bound');
    expect(call.time, '18:30:00');
    // The server's counts are the closing line.
    expect(find.text('2 trocas com horário definido'), findsOneWidget);
    // The reload finds the times: the strip has nothing left to offer.
    expect(_strip, findsNothing);
  });

  testWidgets('a member who is not an admin never sees it', (tester) async {
    final ds =
        FakeCustodyDataSource(members: [_member, _admin], days: _plan());
    await tester.pumpWidget(_app(ds));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('a plan that already carries a time is left alone',
      (tester) async {
    final ds = FakeCustodyDataSource(
        members: [_admin, _member], days: _plan(timeOnDay: 7));
    await tester.pumpWidget(_app(ds));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('the ✕ sends it away for good on this device, per family',
      (tester) async {
    final prefs = _MemoryPrefs();
    final ds =
        FakeCustodyDataSource(members: [_admin, _member], days: _plan());
    await tester.pumpWidget(_app(ds, prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_pt[K.handoffNudgeDismiss]));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
    expect(prefs.dismissed, {7});

    // A fresh screen on the same device stays quiet.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ds, prefs: prefs));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });
}
