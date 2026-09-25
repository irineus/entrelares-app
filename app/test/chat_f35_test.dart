// F-35 (PR 2) — the Conversa and Comunicação on screen.
//
// The server keeps the texts immutable and refuses what it must; these pin
// what the client adds: the fixed notice, the read marks it writes (only when
// something is new), "lida por", reply-by-quoting, the cited day that opens
// the calendar, search, the silencing, the viewer and Premium states, and
// the two tabs of Comunicação with their counters. Since the owner's
// validation (25/09/2026): a text or a mark from another device arrives
// without a refresh, is marked read only while the Conversa is on screen, and
// the column fits what the keyboard leaves on a phone.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/chat_message.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/communication_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/chat_view.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const ana = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    roleId: 1,
    isAdmin: true);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 1);
const vera = Member(
    id: 3,
    fullName: 'Vera Viewer',
    colorSlot: 3,
    userId: 'u3',
    roleId: 1,
    membershipType: 'viewer');

final today = DateTime(2026, 9, 24, 10);

ChatMessage text(int id, int author, String body,
        {int? quote, DateTime? day}) =>
    ChatMessage(
        id: id,
        authorProfileId: author,
        body: body,
        quoteId: quote,
        quotedDay: day,
        createdAt: DateTime.utc(2026, 9, 24, 9, id));

FakeCustodyDataSource source(
        {List<Member> members = const [ana, bruno],
        String plan = 'premium',
        Map<String, String> settings = const {'feature.chat': 'true'}}) =>
    FakeCustodyDataSource(members: members, days: const [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..publicSettings = settings
      ..chatActorId = members.first.id;

Future<void> pumpChat(WidgetTester tester, FakeCustodyDataSource ds,
    {ValueChanged<DateTime>? onOpenDay,
    Size size = const Size(420, 1400),
    ValueListenable<bool>? onScreen}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget chat = ChatView(
      dataSource: ds,
      onOpenPlan: () {},
      onOpenDay: onOpenDay,
      now: () => today);
  // go_router's shell turns the tickers of an inactive branch off; this is
  // the same signal.
  if (onScreen != null) {
    final inner = chat;
    chat = ValueListenableBuilder<bool>(
        valueListenable: onScreen,
        builder: (_, on, _) => TickerMode(enabled: on, child: inner));
  }
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(home: Scaffold(body: chat)),
  ));
  await tester.pumpAndSettle();
}

/// Another device wrote: the channel fires, the debounce passes.
Future<void> deliver(WidgetTester tester, FakeCustodyDataSource ds) async {
  ds.chatListener!();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  testWidgets('the notice opens the conversation; opening marks what is new',
      (tester) async {
    final ds = source()
      ..chatMessages = [text(1, 2, 'Busco às 18h.'), text(2, 1, 'Ok!')];
    await pumpChat(tester, ds);
    expect(find.byKey(const ValueKey('chat-notice')), findsOne);
    expect(find.text('Busco às 18h.'), findsOne);
    expect(ds.chatWrites, ['read:2']);
    // Ana's own text has not been read by anyone yet.
    expect(find.text(l[KApp.chatNotRead]), findsWidgets);

    // Nothing new: reopening writes nothing more.
    await pumpChat(tester, ds);
    expect(ds.chatWrites, ['read:2']);
  });

  testWidgets('"lida por" names who read, never the author', (tester) async {
    final ds = source()
      ..chatMessages = [text(1, 1, 'Levo a mochila.')]
      ..chatReads = [
        ChatRead(
            messageId: 1,
            profileId: 2,
            readAt: DateTime.utc(2026, 9, 24, 13, 5)),
      ];
    await pumpChat(tester, ds);
    final line = tester
        .widget<Text>(find.byKey(const ValueKey('chat-read-1')))
        .data!;
    expect(line, startsWith(l.format(KApp.chatReadBy, ['Bruno Lima (']).split('(').first));
    expect(line, contains('Bruno Lima'));
  });

  testWidgets('a reply quotes, and the text goes out with the quote',
      (tester) async {
    final ds = source()..chatMessages = [text(1, 2, 'Busco às 18h.')];
    await pumpChat(tester, ds);
    await tester.tap(find.byKey(const ValueKey('chat-reply-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-quoting')), findsOne);
    await tester.enterText(
        find.byKey(const ValueKey('chat-composer')), '  Combinado.  ');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(ds.chatWrites.last, 'send:Combinado.:1:-');
    expect(find.byKey(const ValueKey('chat-quoting')), findsNothing);
    expect(find.byKey(const ValueKey('chat-quote-500')), findsOne);
  });

  testWidgets('a cited day opens the calendar on that day', (tester) async {
    DateTime? opened;
    final ds = source()
      ..chatMessages = [
        text(1, 2, 'Troca?', day: DateTime(2026, 10, 1)),
      ];
    await pumpChat(tester, ds, onOpenDay: (d) => opened = d);
    await tester.tap(find.byKey(const ValueKey('chat-day-1')));
    expect(opened, DateTime(2026, 10, 1));
  });

  testWidgets('search forgives accents and says when nothing matched',
      (tester) async {
    final ds = source()
      ..chatMessages = [
        text(1, 2, 'Levo o ônibus escolar.'),
        text(2, 1, 'Obrigado.'),
      ];
    await pumpChat(tester, ds);
    await tester.tap(find.byKey(const ValueKey('chat-search')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')), 'ONIBUS');
    await tester.pump();
    expect(find.text('Levo o ônibus escolar.'), findsOne);
    expect(find.text('Obrigado.'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')), 'carro');
    await tester.pump();
    expect(find.text(l.format(KApp.chatSearchEmpty, ['carro'])), findsOne);
  });

  testWidgets('silencing the push is the member\'s own switch',
      (tester) async {
    final ds = source();
    await pumpChat(tester, ds);
    await tester.tap(find.byKey(const ValueKey('chat-mute')));
    await tester.pumpAndSettle();
    expect(ds.chatWrites, ['mute:true']);
  });

  testWidgets('a viewer reads, and there is nowhere to write',
      (tester) async {
    final ds = source(members: const [vera, ana])
      ..chatMessages = [text(1, 1, 'Oi, Vera.')];
    await pumpChat(tester, ds);
    expect(find.text('Oi, Vera.'), findsOne);
    expect(find.byKey(const ValueKey('chat-read-only')), findsOne);
    expect(find.byKey(const ValueKey('chat-composer')), findsNothing);
    expect(find.byKey(const ValueKey('chat-reply-1')), findsNothing);
  });

  testWidgets('without Premium the Conversa is read-only, with the way in',
      (tester) async {
    final ds = source(plan: 'free')..chatMessages = [text(1, 2, 'Oi.')];
    await pumpChat(tester, ds);
    expect(find.byKey(const ValueKey('chat-premium')), findsOne);
    expect(find.byKey(const ValueKey('chat-composer')), findsNothing);
  });

  testWidgets('flag off: no Conversa', (tester) async {
    await pumpChat(tester, source(settings: const {}));
    expect(find.byKey(const ValueKey('chat-off')), findsOne);
  });

  testWidgets('a text from another device arrives without a refresh and, on '
      'screen, is marked read', (tester) async {
    final ds = source()..chatMessages = [text(1, 2, 'Busco às 18h.')];
    await pumpChat(tester, ds);
    expect(ds.chatWrites, ['read:1']);

    ds.chatMessages = [...ds.chatMessages, text(2, 2, 'Chegamos.')];
    await deliver(tester, ds);
    expect(find.text('Chegamos.'), findsOne);
    expect(ds.chatWrites, ['read:1', 'read:2']);
  });

  testWidgets('the other side reading shows on the author\'s "lida por" '
      'without a refresh', (tester) async {
    final ds = source()..chatMessages = [text(1, 1, 'Levo a mochila.')];
    await pumpChat(tester, ds);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('chat-read-1'))).data,
        l[KApp.chatNotRead]);

    ds.chatReads = [
      ChatRead(
          messageId: 1, profileId: 2, readAt: DateTime.utc(2026, 9, 24, 13, 5)),
    ];
    await deliver(tester, ds);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('chat-read-1'))).data,
        contains('Bruno Lima'));
  });

  testWidgets('off screen a text arrives unread; back on the Conversa it is '
      'marked', (tester) async {
    final onScreen = ValueNotifier(true);
    addTearDown(onScreen.dispose);
    final ds = source()..chatMessages = [text(1, 1, 'Oi.')];
    await pumpChat(tester, ds, onScreen: onScreen);

    onScreen.value = false; // another tab of the bar
    await tester.pump();
    ds.chatMessages = [...ds.chatMessages, text(2, 2, 'Tudo certo?')];
    await deliver(tester, ds);
    expect(ds.chatWrites, isEmpty);

    onScreen.value = true;
    await tester.pumpAndSettle();
    expect(ds.chatWrites, ['read:2']);
  });

  testWidgets('the composer starts at one line and fits above a keyboard',
      (tester) async {
    final ds = source()
      ..chatMessages = [for (var i = 1; i <= 6; i++) text(i, 2, 'Texto $i.')];
    // What a 360 dp phone leaves under the app bars with the keyboard up.
    await pumpChat(tester, ds, size: const Size(360, 300));
    expect(tester.takeException(), isNull);
    final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('chat-composer')),
        matching: find.byType(TextField)));
    expect(field.minLines, 1);
    expect(field.maxLines, 5);
    // The notice scrolls with the texts: at the end, it is off screen.
    expect(find.byKey(const ValueKey('chat-notice')), findsNothing);
  });

  testWidgets('Comunicação: two tabs with counters; a chat push opens the '
      'Conversa', (tester) async {
    final ds = source();
    final badge = NotificationBadge(ds)
      ..chatUnread = 3
      ..count = 2;
    await tester.pumpWidget(AppL10n(
      l: l,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CommunicationScreen(
          badge: badge,
          openOnChat: true,
          chat: const Text('CHAT'),
          notifications: const Text('NOTIFS'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(l[KApp.chatNav]), findsOne);
    expect(find.text(l.format(KApp.chatTabCount, [l[KApp.chatTabChat], 3])),
        findsOne);
    expect(
        find.text(
            l.format(KApp.chatTabCount, [l[KApp.chatTabNotifications], 2])),
        findsOne);
    expect(find.text('CHAT'), findsOne);
    expect(badge.total, 5);
  });
}
