// F-68 — "Ajuda e contato": the form on both sides of the login, what it sends,
// and how each answer of `send-support-request` reads on screen.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_app/screens/help_screen.dart';
import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/services/support_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

final pt = Localization(AppLanguage.ptBr);

Widget _wrap(Widget child) => AppL10n(
      l: pt,
      setLanguage: (_) async {},
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

const _diagnostics = {
  'appVersion': '2.7.5+125',
  'channel': 'web',
  'platform': 'iOS · Safari',
  'language': 'pt-BR',
  'route': '/login',
};

class _Recorder {
  final List<SupportDraft> drafts = [];
  SupportResult answer = const SupportResult(SupportOutcome.sent, 42);
  Future<SupportResult> send(SupportDraft d) async {
    drafts.add(d);
    return answer;
  }
}

Future<void> _pumpHelp(WidgetTester tester, _Recorder rec,
    {String? accountEmail, List<Uri>? mails, VoidCallback? onClose}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(HelpScreen(
    accountEmail: accountEmail,
    diagnostics: _diagnostics,
    onSend: rec.send,
    onClose: onClose ?? () {},
    openMail: (uri) async => mails?.add(uri),
  )));
  await tester.pumpAndSettle();
}

Future<void> _typeMessage(WidgetTester tester, String text) async {
  await tester.enterText(
      find.descendant(
          of: find.byKey(HelpScreen.messageKey),
          matching: find.byType(EditableText)),
      text);
}

/// The form is a lazy ListView: what is below the fold is not built until the
/// list scrolls to it.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapSend(WidgetTester tester) async {
  await _reveal(tester, find.byKey(HelpScreen.sendKey));
  await tester.tap(find.byKey(HelpScreen.sendKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed out: asks for the e-mail and sends it with the message',
      (tester) async {
    final rec = _Recorder();
    await _pumpHelp(tester, rec);

    expect(find.byKey(HelpScreen.emailKey), findsOneWidget);
    await tester.tap(find.text(pt[KApp.helpCatProblem]));
    await _typeMessage(tester, 'O calendário não abre no meu celular.');
    await tester.enterText(
        find.descendant(
            of: find.byKey(HelpScreen.emailKey),
            matching: find.byType(EditableText)),
        'ana@exemplo.com');
    await _tapSend(tester);

    expect(rec.drafts, hasLength(1));
    final d = rec.drafts.single;
    expect(d.category, SupportCategory.problem);
    expect(d.replyEmail, 'ana@exemplo.com');
    expect(d.language, 'pt-BR');
    expect(d.diagnostics, _diagnostics);
    expect(find.text(pt[KApp.helpSentTitle]), findsOneWidget);
    expect(find.text(pt.format(KApp.helpSentBody, ['42', 'ana@exemplo.com'])),
        findsOneWidget);
  });

  testWidgets('signed in: no e-mail field — the reply goes to the account',
      (tester) async {
    final rec = _Recorder();
    await _pumpHelp(tester, rec, accountEmail: 'bia@exemplo.com');

    expect(find.byKey(HelpScreen.emailKey), findsNothing);
    expect(find.text(pt.format(KApp.helpReplyTo, ['bia@exemplo.com'])),
        findsOneWidget);
    await _typeMessage(tester, 'Como troco um dia com o outro responsável?');
    await _tapSend(tester);

    expect(rec.drafts.single.replyEmail, isNull);
  });

  testWidgets('unticking the technical block sends none of it',
      (tester) async {
    final rec = _Recorder();
    await _pumpHelp(tester, rec, accountEmail: 'bia@exemplo.com');

    await _reveal(tester, find.byKey(HelpScreen.diagnosticsKey));
    await tester.tap(find.byKey(HelpScreen.diagnosticsKey));
    await tester.pumpAndSettle();
    await _typeMessage(tester, 'Uma sugestão para o relatório em PDF.');
    await _tapSend(tester);

    expect(rec.drafts.single.diagnostics, isNull);
  });

  testWidgets('the preview lists exactly what would be sent', (tester) async {
    await _pumpHelp(tester, _Recorder());
    await _reveal(tester, find.text(pt[KApp.helpDiagPreview]));
    await tester.tap(find.text(pt[KApp.helpDiagPreview]));
    await tester.pumpAndSettle();
    for (final value in _diagnostics.values) {
      await _reveal(tester, find.text(value));
      expect(find.text(value), findsOneWidget, reason: value);
    }
  });

  testWidgets('a short message or a bad e-mail is refused on the spot',
      (tester) async {
    final rec = _Recorder();
    await _pumpHelp(tester, rec);

    await _typeMessage(tester, 'curta');
    await _tapSend(tester);

    expect(rec.drafts, isEmpty);
    expect(
        find.text(pt.format(KApp.helpMessageTooShort,
            ['${SupportRules.messageMinChars}'])),
        findsOneWidget);
    expect(find.text(pt[KApp.helpEmailInvalid]), findsOneWidget);
  });

  testWidgets('each refusal of the server has its sentence, and the form stays',
      (tester) async {
    final rec = _Recorder();
    await _pumpHelp(tester, rec, accountEmail: 'bia@exemplo.com');
    await _typeMessage(tester, 'Mensagem longa o bastante para passar.');

    for (final (outcome, text) in [
      (
        SupportOutcome.rateLimited,
        pt.format(KApp.helpErrRateLimited, ['suporte@entrelares.app'])
      ),
      (
        SupportOutcome.sendFailed,
        pt.format(KApp.helpErrSendFailed, ['suporte@entrelares.app'])
      ),
      (SupportOutcome.offline, pt[KApp.helpErrOffline]),
      (
        SupportOutcome.failed,
        pt.format(KApp.helpErrFailed, ['suporte@entrelares.app'])
      ),
    ]) {
      rec.answer = SupportResult(outcome);
      await _tapSend(tester);
      expect(find.text(text), findsOneWidget, reason: '$outcome');
      await _reveal(tester, find.byKey(HelpScreen.sendKey));
      expect(find.byKey(HelpScreen.sendKey), findsOneWidget);
    }
  });

  testWidgets('the mailto follows the category — privacy opens privacidade@',
      (tester) async {
    final mails = <Uri>[];
    await _pumpHelp(tester, _Recorder(), mails: mails);

    await _reveal(tester, find.byKey(HelpScreen.mailtoKey));
    await tester.tap(find.byKey(HelpScreen.mailtoKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(pt[KApp.helpCatPrivacy]));
    await tester.pumpAndSettle();
    await tester.tap(find.text(pt[KApp.helpCatPrivacy]));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(HelpScreen.mailtoKey));
    await tester.tap(find.byKey(HelpScreen.mailtoKey));
    await tester.pumpAndSettle();

    expect(mails.map((u) => u.toString()), [
      'mailto:suporte@entrelares.app',
      'mailto:privacidade@entrelares.app',
    ]);
  });

  testWidgets('the login offers the door, only when wired', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var opened = 0;
    await tester.pumpWidget(_wrap(LoginScreen(
      onSignIn: (_, _) async {},
      onForgotPassword: () {},
      onSignUp: () {},
      onHelp: () => opened++,
      prefs: prefs,
    )));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(pt[KApp.helpLoginLink]));
    await tester.tap(find.text(pt[KApp.helpLoginLink]));
    expect(opened, 1);
  });

  // T-83: a signed-in person's form counts to `support.message_max_chars`; the
  // server refuses above it, and the counter must say the same number.
  testWidgets('signed in, the form counts to the operator maximum',
      (tester) async {
    final rec = _Recorder();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(HelpScreen(
      accountEmail: 'ana@example.com',
      diagnostics: _diagnostics,
      onSend: rec.send,
      onClose: () {},
      openMail: (_) async {},
      loadSettings: () async => const {'support.message_max_chars': '500'},
    )));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(HelpScreen.messageKey), matching: find.byType(TextField)));
    expect(field.maxLength, 500);
  });
}
