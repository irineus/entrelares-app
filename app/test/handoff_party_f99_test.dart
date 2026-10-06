// F-99 — only the two ends of a handoff (or an admin) change its time. The
// database refuses the rest (gate suite `handoff_party.dart`); the day sheet
// reads the time to everyone else and points them at the aviso.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);
const _carla =
    Member(id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');

void main() {
  testWidgets('a caregiver at neither end reads the time and is pointed at '
      'the aviso', (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    // Carla reads (first member); Bruno has D-1, Ana has the day.
    final ds = FakeCustodyDataSource(members: [
      _carla,
      ana,
      bruno
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);

    expect(find.byKey(const ValueKey('handoff-party-only')), findsOneWidget);
    expect(find.text(_pt[KApp.noticeHandoffPartyOnly]), findsOneWidget);
    expect(tester.widget<AppTimeField>(find.byType(AppTimeField)).enabled,
        isFalse);
  });

  testWidgets('the end that hands over may change it', (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    // Bruno reads (first member) and has D-1.
    final ds = FakeCustodyDataSource(members: [
      bruno,
      ana
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);
    expect(find.byKey(const ValueKey('handoff-party-only')), findsNothing);
    expect(tester.widget<AppTimeField>(find.byType(AppTimeField)).enabled,
        isTrue);
  });

  // Owner's QA of 3.1.10 (06/10/2026): the way out is a link — the Conversa
  // on another day, the aviso today for whoever may send one.
  testWidgets('another day points at the Conversa, as a link that opens it',
      (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    var opened = 0;
    final ds = FakeCustodyDataSource(members: [
      _carla,
      ana,
      bruno
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ])
      ..publicSettings = const {'feature.chat': 'true'};
    await tester.pumpWidget(app(ds, onOpenChat: () => opened++));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);

    final line = find.byKey(const ValueKey('handoff-party-only'));
    final rich = tester.widget<RichText>(
        find.descendant(of: line, matching: find.byType(RichText)));
    expect(
        rich.text.toPlainText(),
        '${_pt[KApp.noticeHandoffPartyOnly]} '
        '${_pt.format(KApp.noticeHandoffPartyChat, [_pt[KApp.chatTabChat]])}');
    expect(find.textContaining(_pt[KApp.noticeHandoffPartySendLink]),
        findsNothing, reason: 'no aviso about a day that is not today');

    // The link itself.
    TextSpan? link;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) link = span;
      return link == null;
    });
    expect(link?.text, _pt[KApp.chatTabChat]);
    (link!.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(const ValueKey('handoff-party-only')), findsNothing,
        reason: 'the sheet closed before leaving');
  });

  testWidgets('with the Conversa off, the line stops at whose time it is',
      (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    final ds = FakeCustodyDataSource(members: [
      _carla,
      ana,
      bruno
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds, onOpenChat: () {}));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);
    expect(find.text(_pt[KApp.noticeHandoffPartyOnly]), findsOneWidget);
  });
}
