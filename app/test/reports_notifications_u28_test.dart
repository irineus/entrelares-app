// U-28 — the Avisos and Relatórios pass: the two event logs get their rail
// back, the summary gets its colour back, and each report tab names itself.
import 'package:entrelares_app/screens/reports_screen.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reports_audit_test.dart' as audit;
import 'reports_summary_test.dart' as reports;

final _l = Localization(AppLanguage.ptBr);

Future<void> _pumpReports(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      theme: AppTheme.light,
      home: ReportsScreen(dataSource: reports.source()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every report tab names itself, not just the hub',
      (tester) async {
    await _pumpReports(tester);
    expect(find.text(_l[K.sumHeading]), findsOneWidget);

    await tester.tap(find.text(_l[K.repTabHistory]));
    await tester.pumpAndSettle();
    expect(find.text(_l[K.auditHeading]), findsOneWidget);

    await tester.tap(find.text(_l[K.repTabPdf]));
    await tester.pumpAndSettle();
    expect(find.text(_l[K.pdfHeading]), findsOneWidget);
  });

  testWidgets('the summary card is filled with the carer colour, not striped',
      (tester) async {
    await _pumpReports(tester);

    final cards = tester
        .widgetList<Card>(find.byType(Card))
        .where((c) => c.color != null && c.color != AppTokens.light.surfaceAlt)
        .toList();
    expect(cards, isNotEmpty,
        reason: 'a 4 px rule down the left edge is not "the carer colour" — '
            'the web fills the whole card and that is what makes the two '
            'columns readable side by side');
    final slotContainers =
        AppTokens.light.slots.map((s) => s.tone.container).toSet();
    expect(cards.any((c) => slotContainers.contains(c.color)), isTrue);
  });

  testWidgets('the audit log is a timeline, at a density worth reading',
      (tester) async {
    await audit.pumpAudit(
        tester,
        audit.source(logs: [
          audit.activity(id: 1),
          audit.activity(id: 2),
          audit.activity(id: 3),
        ]));

    // Entries on a rail — a log is read for SEQUENCE, and stacked cards said
    // nothing at all about the order.
    expect(find.byType(AppTimelineEntry), findsNWidgets(3));
  });
}
