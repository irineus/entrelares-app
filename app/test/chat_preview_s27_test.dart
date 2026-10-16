// S-27 — the Conversa's push hides the text by default; the member turns the
// preview on (and off) from the Conversa, and the switch is the server's.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_f35_test.dart' show pumpChat, source, text;

void main() {
  final l = Localization(AppLanguage.ptBr);
  final button = find.byKey(const ValueKey('chat-preview'));

  testWidgets('off by default: the switch offers to SHOW the text, and saves',
      (tester) async {
    final ds = source()..chatMessages = [text(1, 2, 'oi')];
    await pumpChat(tester, ds);
    expect(find.byTooltip(l[KApp.chatPreviewShow]), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(ds.chatPushPreview, isTrue);
    expect(find.text(l[KApp.chatPreviewShown]), findsOneWidget);
    expect(find.byTooltip(l[KApp.chatPreviewHide]), findsOneWidget);
  });

  testWidgets('a stored preview loads on',
      (tester) async {
    final on = source()
      ..chatMessages = [text(1, 2, 'oi')]
      ..chatPushPreview = true;
    await pumpChat(tester, on);
    expect(find.byTooltip(l[KApp.chatPreviewHide]), findsOneWidget);
  });

  testWidgets('a silenced chat hides the switch', (tester) async {
    final muted = source()
      ..chatMessages = [text(1, 2, 'oi')]
      ..chatPushMuted = true;
    await pumpChat(tester, muted);
    expect(button, findsNothing);
  });
}
