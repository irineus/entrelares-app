// F-76 — the word search on Relatórios → Histórico. The matching and the cut
// are the server's (`search_history`, SECURITY INVOKER — the DB gate pins
// them); what the screen adds is pinned here: the words go to the server as
// typed, the results replace the timeline as a flat list newest day first,
// each names its kind, its day and its author, a tap opens the day in the
// month view, and clearing brings the timeline back.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/history_search_hit.dart';
import 'package:entrelares_app/screens/reports_audit_tab.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'reports_audit_test.dart' show source, today;
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final l = Localization(AppLanguage.ptBr);

HistorySearchHit hit(String kind, String body,
        {int day = 12, int author = 2}) =>
    HistorySearchHit(
      kind: kind,
      day: DateTime(2026, 8, day),
      writtenAt: DateTime.utc(2026, 8, day + 1, 10),
      authorProfileId: author,
      body: body,
    );

Future<List<DateTime>> pump(WidgetTester tester, FakeCustodyDataSource ds) async {
  final opened = <DateTime>[];
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: ReportsAuditTab(
            dataSource: ds, now: () => today, onOpenDay: opened.add),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

Future<void> search(WidgetTester tester, String words) async {
  await tester.enterText(
      find.descendant(
          of: find.byKey(const ValueKey('history-search-field')),
          matching: find.byType(TextField)),
      words);
  await tester.tap(find.byKey(const ValueKey('history-search')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the words go to the server as typed; the results replace the '
      'timeline, each with its kind, day and author', (tester) async {
    final ds = source()
      ..historyHits = [
        hit('relato', 'Febre de 38 graus, levei ao pronto-socorro.', day: 14),
        hit('agenda', 'Consulta: febre voltou', day: 12, author: 1),
      ];
    await pump(tester, ds);
    await search(tester, '  febre ');

    expect(ds.historyQueries, ['febre']);
    expect(find.text(l.format(KApp.historySearchCountMany, [2])), findsOne);
    expect(find.text(l[KApp.dayAccountSearchKind]), findsOne);
    expect(find.text(l[KApp.agendaSearchKind]), findsOne);
    expect(find.textContaining('pronto-socorro'), findsOne);
    expect(find.textContaining('Bruno Lima'), findsOne);
    // The timeline's filter is out of the way while results are on screen.
    expect(find.text(l[K.repByMonth]), findsNothing);
  });

  testWidgets('a tap opens the day in the month view', (tester) async {
    final ds = source()..historyHits = [hit('reply', 'Foi às 18h.', day: 9)];
    final opened = await pump(tester, ds);
    await search(tester, 'foi');
    await tester.tap(find.byKey(const ValueKey('history-hit-0')));
    await tester.pumpAndSettle();
    expect(opened, [DateTime(2026, 8, 9)]);
  });

  testWidgets('nothing found says so with the words; clearing brings the '
      'timeline back', (tester) async {
    final ds = source();
    await pump(tester, ds);
    await search(tester, 'aeroporto');
    expect(find.text(l.format(KApp.historySearchEmpty, ['aeroporto'])),
        findsOne);

    await tester.tap(find.byKey(const ValueKey('history-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text(l[K.repByMonth]), findsOne);
  });

  testWidgets('a failed search says so and keeps the field', (tester) async {
    final ds = source()..throwOnHistorySearch = Exception('offline');
    await pump(tester, ds);
    await search(tester, 'febre');
    expect(find.text(l[KApp.historySearchError]), findsOne);
    expect(find.byKey(const ValueKey('history-search-field')), findsOne);
  });

  testWidgets('an empty field searches nothing', (tester) async {
    final ds = source();
    await pump(tester, ds);
    await search(tester, '   ');
    expect(ds.historyQueries, isEmpty);
    expect(find.text(l[K.repByMonth]), findsOne);
  });
}
