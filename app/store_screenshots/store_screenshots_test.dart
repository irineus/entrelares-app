// T-97 — the Google Play phone screenshots, rendered from the app's REAL
// widgets, in PT-BR and en-US.
//
// ON DEMAND, NEVER IN CI: this directory sits outside `test/`, which is the
// only directory the CI's bare `flutter test` discovers. Regenerate every
// image, both languages, with
//
//     cd app && fvm flutter test store_screenshots/
//
// and they land in `store/screenshots/<pt-BR|en-US>/phone-<n>.png`
// (1080×1920), numbered in listing order. store/README.md §1 is the runbook;
// the owner approves the PNGs before T-98 publishes them.
//
// Every caption is a claim about the product (S-15): it says what the screen
// below it shows, it says "Premium" over every Premium feature (each scene
// names the gate it shows), and it types no number an operator can change
// (U-57). No emoji (U-31).
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/calendar_slice_test.dart' show FakeCustodyDataSource;
import 'demo_family.dart';
import 'store_frame.dart';

/// One screenshot: its caption in each language and how to reach its screen.
class Scene {
  final String name;
  final Caption pt;
  final Caption en;

  /// Builds the data source for the language — the family's own words are
  /// typed in the screenshot's language.
  final FakeCustodyDataSource Function(DemoTexts t) source;
  final ShellTab tab;
  final bool openOnChat;

  /// What a finger does after the screen settles (open a day, switch a tab).
  final Future<void> Function(WidgetTester tester, Localization l, DemoTexts t)?
  interact;

  const Scene(
    this.name, {
    required this.pt,
    required this.en,
    required this.source,
    required this.tab,
    this.openOnChat = false,
    this.interact,
  });
}

/// Opens [date]'s day sheet the way a finger does: to the next month first
/// when the day is there, then a tap on its cell.
Future<void> _openDay(
  WidgetTester tester,
  Localization l,
  DateTime date,
) async {
  if (date.month != today.month) {
    await tester.tap(find.byTooltip(l[K.calNextMonth]));
    await tester.pumpAndSettle();
  }
  final cell = find
      .descendant(of: find.byType(PageView), matching: find.text('${date.day}'))
      .last;
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

/// Scrolls the screen's vertical list — the topmost one, a sheet's over the
/// page's — until [finder] is on screen, then places it at [alignment] of
/// the viewport (0 = top, 1 = bottom) as far as the list can scroll. A lazy
/// list has not built what is below the fold, so this drags first rather
/// than asking for the element.
Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double alignment = 1,
}) async {
  final list = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .last;
  await tester.scrollUntilVisible(finder, 120, scrollable: list);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: alignment);
  await tester.pumpAndSettle();
}

final scenes = <Scene>[
  // 1 — the month, today's carer on top. FREE: two caregivers (within
  // `free_caregivers`), no Premium module on screen.
  Scene(
    'calendar',
    pt: const Caption(
      'Quem fica com as crianças, dia a dia',
      'O mês num olhar, e com quem elas estão hoje',
    ),
    en: const Caption(
      'Who has the kids, day by day',
      'The month at a glance, and who has them today',
    ),
    source: (t) =>
        familySource(premium: false)..frozenRequests = [pendingRequest(t)],
    tab: ShellTab.calendar,
  ),

  // 2 — a swap request awaiting the reader, in the day sheet. FREE: swaps
  // have no Premium gate.
  Scene(
    'swap',
    pt: const Caption(
      'Trocas de dia pedidas e respondidas no app',
      'O pedido chega com a mensagem; a resposta fica registrada',
    ),
    en: const Caption(
      'Day swaps, asked and answered in the app',
      'The request comes with its message; the answer stays on record',
    ),
    source: (t) => familySource(premium: false)
      ..frozenRequests = [pendingRequest(t)]
      ..pendingForMe = [pendingRequest(t)],
    tab: ShellTab.calendar,
    interact: (tester, l, t) => _openDay(tester, l, requestedSaturday),
  ),

  // 3 — the PDF, generated, with the reports already issued. PREMIUM:
  // `reports_pdf_tab.dart` shows the upsell instead of the form when
  // `!_isPremium`, and the QR (F-64) is issued only `_isPremium` too.
  Scene(
    'pdf',
    pt: const Caption(
      'Relatório em PDF verificável',
      'O QR Code no documento abre a página que confere a autenticidade',
      premium: true,
    ),
    en: const Caption(
      'A verifiable PDF report',
      'The QR code on the document opens a page that checks it',
      premium: true,
    ),
    source: (t) => familySource(premium: true)..attestations = issuedReports(),
    tab: ShellTab.reports,
    interact: (tester, l, t) async {
      await tester.tap(find.text(l[K.repTabPdf]));
      await tester.pumpAndSettle();
      // The year so far: the swaps of the year are in it.
      await tester.tap(find.text(l[K.pdfByYear]));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(l[K.pdfGenerate]));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(const ValueKey('attestations-card')));
    },
  ),

  // 4 — the roster: a grandmother as a third caregiver and the nanny as a
  // Visualizador. PREMIUM: a third caregiver is beyond `free_caregivers`
  // (the family page's cap notice, `premFeatureCaregivers`).
  Scene(
    'family',
    pt: const Caption(
      'Avó, babá e quem mais cuida',
      'Cada um com seu papel; a babá acompanha como Visualizador',
      premium: true,
    ),
    en: const Caption(
      'Grandma, the nanny and everyone who helps',
      'Each with their role; the nanny follows along as a Viewer',
      premium: true,
    ),
    source: (t) => familySource(
      premium: true,
      members: const [ana, bruno, rosa, carla],
      children: const [lia, theo],
    ),
    tab: ShellTab.family,
  ),

  // 5 — a day's agenda for both children. PREMIUM: every kind but the note
  // is Premium (`AgendaKind.isStructured`, `agenda.premium_only`).
  Scene(
    'agenda',
    pt: const Caption(
      'A agenda de cada criança',
      'Escola, saúde, remédios e atividades no dia certo',
      premium: true,
    ),
    en: const Caption(
      "Each child's agenda",
      'School, health, medicine and activities on the right day',
      premium: true,
    ),
    source: (t) =>
        familySource(premium: true, children: const [lia, theo])
          ..childEvents = agendaOf(day(1), t),
    tab: ShellTab.calendar,
    interact: (tester, l, t) async {
      await _openDay(tester, l, day(1));
      await _reveal(tester, find.text(l[KApp.agendaSection]), alignment: 0);
    },
  ),

  // 6 — the Conversa. PREMIUM: `chat.premium_only` (`chat_view.dart`).
  Scene(
    'chat',
    pt: const Caption(
      'A conversa da família, registrada',
      'Ninguém da família edita ou apaga uma mensagem; cada uma pode citar o dia',
      premium: true,
    ),
    en: const Caption(
      'The family chat, on record',
      'No family member can edit or delete a message, and each can cite a day',
      premium: true,
    ),
    source: (t) {
      final messages = chatHistory(t);
      return familySource(premium: true, children: const [lia, theo])
        ..chatMessages = messages
        ..chatReads = chatReadsOf(messages);
    },
    tab: ShellTab.communication,
    openOnChat: true,
  ),

  // 7 — shared expenses. PREMIUM: `expenses.premium_only`
  // (`expenses_screen.dart`).
  Scene(
    'expenses',
    pt: const Caption(
      'As despesas das crianças, divididas',
      'Quem pagou, quanto cabe a cada um e o saldo',
      premium: true,
    ),
    en: const Caption(
      "The kids' expenses, shared",
      'Who paid, what each one owes and the balance',
      premium: true,
    ),
    source: (t) =>
        familySource(premium: true, children: const [lia, theo])
          ..expenses = expenseList(t),
    tab: ShellTab.expenses,
    interact: (tester, l, t) => _reveal(
      tester,
      find.byKey(const ValueKey('expenses-group')),
      alignment: 0,
    ),
  ),

  // 8 — the year in days per parent. FREE: the Resumo has no gate.
  Scene(
    'summary',
    pt: const Caption(
      'Quantos dias com cada um',
      'O resumo do ano, contado direto do calendário',
    ),
    en: const Caption(
      'How many days with each parent',
      "The year's summary, counted straight from the calendar",
    ),
    source: (t) => familySource(premium: false),
    tab: ShellTab.reports,
  ),
];

const _out = '../store/screenshots';

void main() {
  setUpAll(() async {
    await loadBundleFonts();
    // A scene taken out of the list must not leave its old PNG behind to be
    // uploaded by mistake: the folders hold exactly what this run wrote.
    for (final folder in ['pt-BR', 'en-US']) {
      final dir = Directory('$_out/$folder');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        if (RegExp(r'phone-\d+\.png$').hasMatch(f.path)) f.deleteSync();
      }
    }
  });

  for (final language in AppLanguage.values) {
    final en = language == AppLanguage.en;
    final folder = en ? 'en-US' : 'pt-BR';
    final l = Localization(language);
    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      testWidgets('$folder ${i + 1} ${scene.name}', (tester) async {
        await useCanvas(tester);
        final ds = scene.source(DemoTexts(en));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: StoreFrame(
              caption: en ? scene.en : scene.pt,
              premiumLabel: 'Premium',
              app: shellApp(
                ds,
                language: language,
                tab: scene.tab,
                openOnChat: scene.openOnChat,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await scene.interact?.call(tester, l, DemoTexts(en));
        await tester.pumpAndSettle();
        // A caption line cut by the band is a failure, not a silent "…".
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byKey(StoreFrame.captionKey),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: 'caption too long: "${p.text.toPlainText()}"',
          );
        }
        await capture(tester, boundary, '$_out/$folder/phone-${i + 1}.png');
      });
    }
  }
}
