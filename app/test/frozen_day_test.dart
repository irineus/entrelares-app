// F-12 frozen days on the calendar (lote 3): the 🔔/⏳ cell badges, the
// frozen-day panel replacing the editor on tap, and the three role views —
// target (approve/reject with the F-44 dual note), requester (cancel),
// observer. The DB enforces every transition; these test the mirror UI
// against the fake data source.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';

import 'calendar_slice_test.dart';

final l = Localization(AppLanguage.ptBr);

SwapRequest swapReq(
  int id,
  DateTime date, {
  int requesting = 2,
  int target = 1,
  int proposed = 1,
  String status = 'pending',
  String? handoff,
  String? message,
}) =>
    SwapRequest.fromJson({
      'id': id,
      'schedule_date': CareSchedule.isoDate(date),
      'requesting_profile_id': requesting,
      'target_profile_id': target,
      'proposed_actual_parent_id': proposed,
      'proposed_handoff_time': handoff,
      'status': status,
      'request_message': message,
    });

void main() {
  testWidgets('a pending request awaiting ME paints 🔔 on the cell',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [swapReq(10, dayOfMonth(day))];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(find.text('🔔'), findsOneWidget);
    expect(find.text('⏳'), findsNothing);
  });

  testWidgets('a pending request awaiting the OTHER paints ⏳', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        swapReq(10, dayOfMonth(day), requesting: 1, target: 2, proposed: 2)
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(find.text('⏳'), findsOneWidget);
    expect(find.text('🔔'), findsNothing);
  });

  testWidgets('tapping a frozen day opens the panel, not the editor',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        swapReq(10, dayOfMonth(day), message: 'Tenho consulta')
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    // U-28 QA: the urgency emoji rides in the sheet title now, so the title is
    // "⚠️ Solicitação de troca pendente" and not the bare sentence.
    expect(find.textContaining(l[K.frozenSwapTitle]), findsOneWidget);
    // The editor's save button must NOT be there.
    expect(find.text(l[K.commonSave]), findsNothing);
    // F-44: the requester's message shows on the panel.
    expect(find.text('Tenho consulta'), findsOneWidget);
    // Roles: Ana (profile 1) is the target → approve/reject + the note field.
    expect(find.text(l[K.frozenApprove]), findsOneWidget);
    expect(find.text(l[K.frozenRejectAction]), findsOneWidget);
  });

  testWidgets('target approves with the F-44 note; toast + reload',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [swapReq(10, dayOfMonth(day))];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    await tester.enterText(find.byType(TextField).last, 'Busco às 18h');
    await tester.tap(find.text(l[K.frozenApprove]));
    await tester.pumpAndSettle();

    expect(ds.approvedSwaps, [(id: 10, note: 'Busco às 18h')]);
    expect(find.text(l[K.toastSwapApproved]), findsOneWidget);
  });

  testWidgets('target rejects; a blank note travels as null', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [swapReq(10, dayOfMonth(day))];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    await tester.tap(find.text(l[K.frozenRejectAction]));
    await tester.pumpAndSettle();

    expect(ds.rejectedSwaps, [(id: 10, reason: null)]);
    expect(find.text(l[K.toastSwapRejected]), findsOneWidget);
  });

  testWidgets('requester sees only the cancel action', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        // Ana (1) requested; Bruno (2) must answer.
        swapReq(10, dayOfMonth(day), requesting: 1, target: 2, proposed: 2)
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    expect(find.text(l[K.frozenApprove]), findsNothing);
    expect(find.text(l[K.frozenCancelRequest]), findsOneWidget);

    await tester.tap(find.text(l[K.frozenCancelRequest]));
    await tester.pumpAndSettle();
    expect(ds.cancelledSwaps, [10]);
    expect(find.text(l[K.toastRequestCancelled]), findsOneWidget);
  });

  testWidgets('an uninvolved member observes', (tester) async {
    final day = futureDay;
    if (day == null) return;
    const carla =
        Member(id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');
    // Own profile is the FIRST member — Carla observes Bruno↔Ana's swap.
    final ds =
        FakeCustodyDataSource(members: [carla, ana, bruno], days: [])
          ..frozenRequests = [
            swapReq(10, dayOfMonth(day), requesting: 2, target: 1, proposed: 1)
          ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    expect(find.text(l[K.frozenApprove]), findsNothing);
    expect(find.text(l[K.frozenCancelRequest]), findsNothing);
    expect(find.text(l.format(K.frozenObserver, ['Ana Souza'])),
        findsOneWidget);
  });

  testWidgets('a revert_pending panel carries the revert actions',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        swapReq(10, dayOfMonth(day), status: 'revert_pending')
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    expect(find.textContaining(l[K.frozenRevertTitle]), findsOneWidget);
    expect(find.text(l[K.frozenConfirmRevert]), findsOneWidget);

    await tester.tap(find.text(l[K.frozenConfirmRevert]));
    await tester.pumpAndSettle();
    expect(ds.approvedReverts, [(id: 10, note: null)]);
    expect(find.text(l[K.toastRevertConfirmed]), findsOneWidget);
  });

  testWidgets('the workflow Realtime callback repaints the frozen set',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(find.text('🔔'), findsNothing);

    ds.frozenRequests = [swapReq(10, dayOfMonth(day))];
    ds.workflowCallback!();
    await tester.pumpAndSettle();
    expect(find.text('🔔'), findsOneWidget);
  });
}
