// U-59 — *Exportar conversa*: the Conversa's door to the EXISTING PDF.
//
// What the door adds, and nothing else: the PDF tab opens pre-filled (the
// last 30 days, the Conversa's switch on), a family without Premium meets
// the gate with its way in (`/family/plan`), a viewer exports too, and the
// QR is promised only where the PDF can carry one (F-64: never a viewer's).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/screens/reports_pdf_tab.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/chat_view.dart';

import 'chat_f35_test.dart' show ana, bruno, vera, source, today;
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final l = Localization(AppLanguage.ptBr);

const _chatAndQr = {
  'feature.chat': 'true',
  'feature.report_attestation': 'true',
};

Future<void> pumpChat(WidgetTester tester, FakeCustodyDataSource ds,
    {VoidCallback? onOpenPlan}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ChatView(
            dataSource: ds, onOpenPlan: onOpenPlan ?? () {}, now: () => today),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> openExport(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-export')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the action sits in the Conversa bar, named for the reader',
      (tester) async {
    await pumpChat(tester, source(settings: _chatAndQr));
    expect(find.byTooltip(l[KApp.chatExport]), findsOne);
  });

  testWidgets('it opens the EXISTING PDF tab with the Conversa on and the last '
      '30 days, and promises the QR', (tester) async {
    await pumpChat(tester, source(settings: _chatAndQr));
    await openExport(tester);

    expect(find.text(l[KApp.chatExportTitle]), findsOne);
    expect(find.byKey(const ValueKey('chat-export-qr')), findsOne);
    final tab = tester.widget<ReportsPdfTab>(find.byType(ReportsPdfTab));
    expect(tab.initialIncludeChat, isTrue);
    expect(tab.analyticsSource, 'chat');
    expect(tab.initialPeriod, ChatExportRules.initialPeriod(today));
    // The switch the Relatórios tab leaves off is ON here.
    final chatSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('pdf-include-chat')));
    expect(chatSwitch.value, isTrue);
    // Editable: the reader may still turn it off.
    await tester.ensureVisible(find.byKey(const ValueKey('pdf-include-chat')));
    await tester.tap(find.byKey(const ValueKey('pdf-include-chat')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('pdf-include-chat')))
            .value,
        isFalse);
  });

  testWidgets('a viewer exports too, and is never promised a QR it cannot get',
      (tester) async {
    await pumpChat(tester, source(members: const [vera, ana], settings: _chatAndQr));
    await openExport(tester);

    expect(find.byType(ReportsPdfTab), findsOne);
    expect(find.byKey(const ValueKey('chat-export-qr')), findsNothing);
  });

  testWidgets('with verification off, nobody is promised the QR',
      (tester) async {
    await pumpChat(tester, source());
    await openExport(tester);

    expect(find.byType(ReportsPdfTab), findsOne);
    expect(find.byKey(const ValueKey('chat-export-qr')), findsNothing);
  });

  testWidgets('without Premium: the gate, whose way in opens the plan page',
      (tester) async {
    var opened = 0;
    await pumpChat(tester, source(plan: 'free', settings: _chatAndQr),
        onOpenPlan: () => opened++);
    await openExport(tester);

    expect(find.byType(ReportsPdfTab), findsNothing);
    final gate = find.byKey(const ValueKey('chat-export-premium'));
    expect(gate, findsOne);
    await tester.tap(
        find.descendant(of: gate, matching: find.text(l[K.famSeePremium])));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byKey(const ValueKey('chat-export-premium')), findsNothing);
  });

  testWidgets('a caregiver with Premium also sees the rest of the Conversa '
      'untouched', (tester) async {
    await pumpChat(tester, source(members: const [ana, bruno]));
    expect(find.byKey(const ValueKey('chat-search')), findsOne);
    expect(find.byKey(const ValueKey('chat-mute')), findsOne);
  });
}
