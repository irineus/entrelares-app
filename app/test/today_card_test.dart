// TodayCard (T-53 lote 1) — the widget states of the web's TodayCard.razor:
// responsible row with badges and the next-handoff block, the no-responsible
// hint, the F-31 invite nudge (which wins over everything), the back-to-today
// affordance, and the English rendering.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/today_card.dart';

const ana = MemberView(id: 1, fullName: 'Ana Souza', colorSlot: 1);
const bruno = MemberView(id: 2, fullName: 'Bruno Lima', colorSlot: 2);

final today = DateTime(2026, 8, 19);

Widget wrap(Widget child, {AppLanguage language = AppLanguage.ptBr}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(home: Scaffold(body: child)),
    );

TodayCard card({
  TodayGlance? glance,
  DateTime? nextHandoff,
  bool viewingCurrentMonth = true,
  bool showInviteNudge = false,
  VoidCallback? onGoToToday,
  VoidCallback? onInvite,
}) =>
    TodayCard(
      glance: glance ??
          todayGlance(
            userProfileId: 1,
            scheduledParentId: null,
            actualParentId: null,
            handoffTime: null,
            members: const [ana, bruno],
          ),
      userFullName: 'Ana Souza',
      today: today,
      nextHandoffDate: nextHandoff,
      viewingCurrentMonth: viewingCurrentMonth,
      showInviteNudge: showInviteNudge,
      onGoToToday: onGoToToday ?? () {},
      onInvite: onInvite ?? () {},
    );

void main() {
  testWidgets('responsible row: greeting, date heading, name, next handoff',
      (tester) async {
    final glance = todayGlance(
      userProfileId: 1,
      scheduledParentId: 2,
      actualParentId: null,
      handoffTime: null,
      members: const [ana, bruno],
    );
    await tester.pumpWidget(wrap(card(
        glance: glance, nextHandoff: DateTime(2026, 8, 22))));

    // U-28: the greeting uses the FIRST name — the full legal name wrapped
    // onto three lines of card on a phone.
    expect(find.text('Olá, Ana!'), findsOneWidget);
    // U-28 QA: the date heading starts with a capital — it is a heading, not a
    // clause inside a sentence — and it never truncates.
    expect(find.text('Quarta-feira, 19 de agosto'), findsOneWidget);
    expect(find.text('Responsável hoje'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget);
    expect(find.text('B'), findsOneWidget, reason: 'naive avatar letter');
    expect(find.text('Próxima troca'), findsOneWidget);
    expect(find.text('sáb, 22/08'), findsOneWidget);
    expect(find.text('em 3 dias'), findsOneWidget);
    // Current month: the card is not tappable, no hint.
    expect(find.text('↩ Voltar para hoje'), findsNothing);
  });

  testWidgets('U-28 QA: the date sits at the RIGHT edge, not beside the name',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(card()));

    final date = tester.getRect(find.text('Quarta-feira, 19 de agosto'));
    final greeting = tester.getRect(find.text('Olá, Ana!'));
    final band = tester.getRect(find.byType(Card));

    // Two earlier attempts LOOKED right in code and were not: `Flexible` sized
    // the date to itself, and `Expanded` + `FittedBox` gave the alignment
    // nothing to align against. Only geometry catches that.
    // `Card`'s own rect includes its margin, so the visible surface ends 12 dp
    // inside it and the content another 12 dp inside that.
    expect(date.right, closeTo(band.right - 24, 2),
        reason: 'the date ends where the card content ends');
    expect(date.left, greaterThan(greeting.right),
        reason: 'and it never overlaps the greeting');
  });

  testWidgets('swapped day shows both badges — 🔄 and the ⏰ time',
      (tester) async {
    final glance = todayGlance(
      userProfileId: 1,
      scheduledParentId: 1,
      actualParentId: 2,
      handoffTime: '18:30:00',
      members: const [ana, bruno],
    );
    await tester.pumpWidget(wrap(card(glance: glance)));

    expect(find.text('🔄 Trocado'), findsOneWidget);
    expect(find.text('⏰ 18:30'), findsOneWidget);
  });

  testWidgets('no schedule: the 📭 hint, and no handoff line', (tester) async {
    await tester.pumpWidget(wrap(card()));

    expect(find.text('Dia sem responsável'), findsOneWidget);
    expect(
        find.text('Toque em um dia no calendário para definir'), findsOneWidget);
    expect(find.text('Próxima troca'), findsNothing);
  });

  testWidgets('the F-31 invite nudge wins over the responsible row',
      (tester) async {
    var invited = false;
    final glance = todayGlance(
      userProfileId: 1,
      scheduledParentId: 1,
      actualParentId: null,
      handoffTime: null,
      members: const [ana],
    );
    await tester.pumpWidget(wrap(card(
      glance: glance,
      showInviteNudge: true,
      onInvite: () => invited = true,
    )));

    expect(find.text('Convide o outro responsável'), findsOneWidget);
    expect(find.text('Responsável hoje'), findsNothing);

    await tester.tap(find.text('Convidar'));
    expect(invited, isTrue);
  });

  testWidgets('viewing another month: the card itself goes back to today',
      (tester) async {
    var wentToToday = false;
    await tester.pumpWidget(wrap(card(
      viewingCurrentMonth: false,
      onGoToToday: () => wentToToday = true,
    )));

    // U-28 QA: the "Voltar para hoje" LINE left the card — as link text inside
    // a coloured band it read as an orphan sentence. It is a chip in the month
    // bar now (calendar_slice_test covers it); the card stays tappable.
    expect(find.textContaining('Voltar para hoje'), findsNothing);
    await tester.tap(find.byType(InkWell).first);
    expect(wentToToday, isTrue);
  });

  testWidgets('an English session renders the card in English',
      (tester) async {
    final glance = todayGlance(
      userProfileId: 1,
      scheduledParentId: 2,
      actualParentId: null,
      handoffTime: null,
      members: const [ana, bruno],
    );
    await tester.pumpWidget(wrap(
      card(glance: glance, nextHandoff: DateTime(2026, 8, 20)),
      language: AppLanguage.en,
    ));

    expect(find.text('Hi, Ana!'), findsOneWidget);
    expect(find.text('Wednesday, August 19'), findsOneWidget);
    expect(find.text('Caregiver today'), findsOneWidget);
    expect(find.text('Next handover'), findsOneWidget);
    expect(find.text('tomorrow'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget,
        reason: 'names never translate');
  });
}
