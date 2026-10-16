// U-66 (T-103 audit, 04/10/2026) — the Conversa as a record someone reads
// back.
//
// - The opening notice ("permanente…") is item 0 of the thread and scrolls
//   away once there is history; the composer says it again where one writes.
// - A search result had nothing to tap: "Ver na conversa" clears the filter
//   and lands ON the text, with what was said after it below, tinted for a
//   moment. A quote does the same for the text it quotes, loading older
//   pages when that text is not loaded yet.
// - "Ir para a data" in the search bar lands on the first text of that day.
// Immutability (F-35) does not change.
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/chat_view.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_f35_test.dart' show ana, bruno, pumpChat, source, text;

final _l = Localization(AppLanguage.ptBr);

Finder _card(int id) => find.byKey(ValueKey('chat-message-$id'));

Color? _cardColor(WidgetTester tester, int id) =>
    tester.widget<Card>(_card(id)).color;

AppTokens _tokens(WidgetTester tester) =>
    tester.element(find.byType(ChatView)).tokens;

/// The text sits inside the viewport the chat lays out.
void _expectOnScreen(WidgetTester tester, int id) {
  final scroll = tester.getRect(find.byType(CustomScrollView));
  final card = tester.getRect(_card(id));
  expect(card.top, greaterThanOrEqualTo(scroll.top - 1),
      reason: 'text $id is above the viewport');
  expect(card.top, lessThan(scroll.bottom), reason: 'text $id is below it');
}

void main() {
  testWidgets('the composer says the permanence where one writes',
      (tester) async {
    final ds = source()..chatMessages = [text(1, 2, 'oi')];
    await pumpChat(tester, ds);
    expect(find.text(_l[KApp.chatComposerPermanent]), findsOneWidget);
  });

  testWidgets(
      'a search result leads into the thread: filter cleared, the text '
      'on screen and tinted, what came after it below', (tester) async {
    final ds = source()
      ..chatMessages = [
        for (var i = 1; i <= 60; i++)
          text(i, i.isEven ? ana.id : bruno.id,
              i == 5 ? 'A mensalidade da escola subiu' : 'texto $i'),
      ];
    await pumpChat(tester, ds, size: const Size(420, 900));

    await tester.tap(find.byKey(const ValueKey('chat-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')), 'mensalidade');
    await tester.pumpAndSettle();
    expect(_card(6), findsNothing, reason: 'the filter shows the match only');

    await tester.tap(find.byKey(const ValueKey('chat-show-5')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-search-field')), findsNothing);
    _expectOnScreen(tester, 5);
    expect(_card(6), findsOneWidget, reason: 'what was said after it');
    expect(_cardColor(tester, 5), _tokens(tester).warning.container);

    await tester.pump(const Duration(seconds: 4));
    expect(_cardColor(tester, 5), isNot(_tokens(tester).warning.container),
        reason: 'the tint is brief');
  });

  testWidgets('a quote opens the text it quotes, loading older pages',
      (tester) async {
    final ds = source()
      ..chatMessages = [
        for (var i = 1; i <= 260; i++)
          i == 260
              ? text(i, ana.id, 'Respondendo', quote: 1)
              : text(i, bruno.id, i == 1 ? 'O começo de tudo' : 'texto $i'),
      ];
    await pumpChat(tester, ds, size: const Size(420, 900));
    expect(_card(1), findsNothing, reason: 'older than the first page');

    await tester.tap(find.byKey(const ValueKey('chat-quote-260')));
    await tester.pumpAndSettle();
    _expectOnScreen(tester, 1);
    expect(_cardColor(tester, 1), _tokens(tester).warning.container);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('"Ir para a data" lands on the first text of that day',
      (tester) async {
    ChatMessage on(int id, int day) => ChatMessage(
        id: id,
        authorProfileId: bruno.id,
        body: 'dia $day · $id',
        createdAt: DateTime(2026, 9, day, 12).toUtc());
    final ds = source()
      ..chatMessages = [
        for (var i = 1; i <= 30; i++) on(i, 20),
        for (var i = 31; i <= 60; i++) on(i, 22),
        for (var i = 61; i <= 90; i++) on(i, 24),
      ];
    await pumpChat(tester, ds, size: const Size(420, 900));

    await tester.tap(find.byKey(const ValueKey('chat-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-go-to-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    _expectOnScreen(tester, 31);
    expect(_cardColor(tester, 31), _tokens(tester).warning.container);
    await tester.pump(const Duration(seconds: 4));
  });
}
