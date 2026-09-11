// S-10 — the elevation client: the service's window/throttle behaviour against
// a fake `elevate`, the 🔐 sheet, and the two-layer `runWithSudo` gate.
//
// S-21 adds the SECOND proof — a code mailed to the account — and with it the
// case the sheet could not serve before: a session with no password. Those
// tests are at the bottom, and the one that matters is that the code path is
// reachable WITHOUT the client deciding in advance who has a password. It is
// not in a position to decide: production carries an account whose only
// identity provider is `google` and which nonetheless has one.
//
// The layer that matters most is the SECOND one: an action that comes back
// with the `ELEVATION_REQUIRED:` marker must prompt and retry, because the
// optimistic check can be wrong (window expired mid-flight, or a drifted
// device clock) and the server is the only authority.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/sudo_sheet.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, ana, bruno;

FakeCustodyDataSource fakeSource() =>
    FakeCustodyDataSource(members: const [ana, bruno], days: [])
      ..sudoPassword = 'segredo123';

Widget harness({
  required SudoService sudo,
  required void Function(BuildContext context) onTap,
  AppLanguage language = AppLanguage.ptBr,
}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => onTap(context),
              child: const Text('gatilho'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('SudoService', () {
    test('a correct password opens the window', () async {
      final source = fakeSource();
      final sudo = SudoService(source);
      expect(sudo.isElevated, isFalse);

      final error =
          await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));

      expect(error, isNull);
      expect(sudo.isElevated, isTrue);
      expect(source.elevateAttempts, ['segredo123']);
    });

    test('honours the server instant over the local estimate', () async {
      final source = fakeSource()
        ..sudoElevatedUntil =
            DateTime.now().toUtc().add(const Duration(seconds: 5)).toIso8601String();
      final sudo = SudoService(source);

      await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));

      // 5 s of server window is inside the 15 s safety margin — the client
      // must NOT claim to be elevated and race the RPC.
      expect(sudo.isElevated, isFalse);
    });

    test('propagates the server message on a wrong password', () async {
      final sudo = SudoService(fakeSource());

      final error =
          await sudo.elevate('errada', Localization(AppLanguage.ptBr));

      expect(error, 'Senha incorreta.');
      expect(sudo.isElevated, isFalse);
    });

    test('the third wrong password starts the 60 s cooldown', () async {
      final sudo = SudoService(fakeSource());
      final l = Localization(AppLanguage.ptBr);

      await sudo.elevate('errada', l);
      await sudo.elevate('errada', l);
      expect(sudo.isCoolingDown, isFalse);

      final third = await sudo.elevate('errada', l);

      expect(sudo.isCoolingDown, isTrue);
      expect(third, contains('60'));
    });

    test('a cooling-down service refuses without spending a round-trip',
        () async {
      final source = fakeSource();
      final sudo = SudoService(source);
      final l = Localization(AppLanguage.ptBr);
      for (var i = 0; i < 3; i++) {
        await sudo.elevate('errada', l);
      }
      final attemptsBefore = source.elevateAttempts.length;

      final error = await sudo.elevate('segredo123', l);

      expect(error, isNotNull);
      expect(source.elevateAttempts, hasLength(attemptsBefore));
    });

    test('a transport failure does not spend an attempt', () async {
      final source = fakeSource()..throwOnElevate = Exception('offline');
      final sudo = SudoService(source);
      final l = Localization(AppLanguage.ptBr);

      final first = await sudo.elevate('segredo123', l);
      await sudo.elevate('segredo123', l);
      await sudo.elevate('segredo123', l);

      expect(first, Localization(AppLanguage.ptBr)[KApp.sudoErrConnection]);
      expect(sudo.isCoolingDown, isFalse);
    });

    test('reset drops the window when the session ends', () async {
      final sudo = SudoService(fakeSource());
      await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));
      expect(sudo.isElevated, isTrue);

      sudo.reset();

      expect(sudo.isElevated, isFalse);
    });

    test('an English session reads the fallbacks in English', () async {
      final source = fakeSource()..throwOnElevate = Exception('offline');
      final sudo = SudoService(source);

      final error =
          await sudo.elevate('segredo123', Localization(AppLanguage.en));

      expect(error, Localization(AppLanguage.en)[KApp.sudoErrConnection]);
    });
  });

  group('sudo sheet', () {
    testWidgets('confirms with the right password and reports true',
        (tester) async {
      final sudo = SudoService(fakeSource());
      bool? granted;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) async {
          granted = await showSudoSheet(context: context, sudo: sudo);
        },
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      expect(find.text(Localization(AppLanguage.ptBr)[K.sudoTitle]), findsOne);

      await tester.enterText(find.byType(TextField), 'segredo123');
      await tester.pump();
      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.sudoConfirm]));
      await tester.pumpAndSettle();

      expect(granted, isTrue);
      expect(sudo.isElevated, isTrue);
    });

    testWidgets('shows the refusal and keeps the sheet open', (tester) async {
      final sudo = SudoService(fakeSource());
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => showSudoSheet(context: context, sudo: sudo),
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'errada');
      await tester.pump();
      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.sudoConfirm]));
      await tester.pumpAndSettle();

      expect(find.text('Senha incorreta.'), findsOne);
      expect(find.byType(TextField), findsOne);
    });

    testWidgets('cancelling reports false', (tester) async {
      final sudo = SudoService(fakeSource());
      bool? granted;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) async {
          granted = await showSudoSheet(context: context, sudo: sudo);
        },
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(granted, isFalse);
      expect(sudo.isElevated, isFalse);
    });
  });

  group('runWithSudo — the two layers', () {
    testWidgets('prompts BEFORE acting when not elevated', (tester) async {
      final sudo = SudoService(fakeSource());
      var ran = 0;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => runWithSudo(
          context: context,
          sudo: sudo,
          action: () async => ran++,
        ),
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      expect(ran, 0, reason: 'the action must wait for the password');

      await tester.enterText(find.byType(TextField), 'segredo123');
      await tester.pump();
      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.sudoConfirm]));
      await tester.pumpAndSettle();

      expect(ran, 1);
    });

    testWidgets('acts straight away when already elevated', (tester) async {
      final sudo = SudoService(fakeSource());
      await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));
      var ran = 0;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => runWithSudo(
          context: context,
          sudo: sudo,
          action: () async => ran++,
        ),
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      expect(ran, 1);
      expect(find.text(Localization(AppLanguage.ptBr)[K.sudoTitle]),
          findsNothing);
    });

    testWidgets('the marker coming back re-prompts and retries once',
        (tester) async {
      final sudo = SudoService(fakeSource());
      // The client believes it is elevated; the server disagrees — exactly the
      // window-expired-mid-flight case the second layer exists for.
      await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));
      var attempts = 0;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => runWithSudo(
          context: context,
          sudo: sudo,
          action: () async {
            attempts++;
            if (attempts == 1) {
              throw Exception('ELEVATION_REQUIRED: Confirme sua senha para '
                  'alterar permissões de administrador.');
            }
          },
        ),
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      expect(find.text(Localization(AppLanguage.ptBr)[K.sudoTitle]), findsOne);

      await tester.enterText(find.byType(TextField), 'segredo123');
      await tester.pump();
      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.sudoConfirm]));
      await tester.pumpAndSettle();

      expect(attempts, 2, reason: 'the action retries after the elevation');
    });

    testWidgets('a non-elevation failure is rethrown untouched',
        (tester) async {
      final sudo = SudoService(fakeSource());
      await sudo.elevate('segredo123', Localization(AppLanguage.ptBr));
      Object? caught;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) async {
          try {
            await runWithSudo(
              context: context,
              sudo: sudo,
              action: () async => throw Exception('permission denied'),
            );
          } catch (e) {
            caught = e;
          }
        },
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      expect(caught, isNotNull);
      expect(find.text(Localization(AppLanguage.ptBr)[K.sudoTitle]),
          findsNothing);
    });

    testWidgets('dismissing the prompt reports false and never acts',
        (tester) async {
      final sudo = SudoService(fakeSource());
      var ran = 0;
      bool? outcome;
      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) async {
          outcome = await runWithSudo(
            context: context,
            sudo: sudo,
            action: () async => ran++,
          );
        },
      ));

      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.text(Localization(AppLanguage.ptBr)[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(outcome, isFalse);
      expect(ran, 0);
    });
  });

  // ── S-21: the second proof ──────────────────────────────────────────────────

  group('SudoService — the e-mail code', () {
    test('a correct code opens the same window a password opens', () async {
      final source = fakeSource()..sudoCode = '246810';
      final sudo = SudoService(source);

      final asked = await sudo.requestCode(Localization(AppLanguage.ptBr));
      expect(asked.codeReady, isTrue);
      expect(source.codeRequests, 1);

      final error =
          await sudo.elevateWithCode('246810', Localization(AppLanguage.ptBr));

      expect(error, isNull);
      expect(sudo.isElevated, isTrue);
    });

    test('a code copied with its spacing is not refused on shape', () async {
      final source = fakeSource()..sudoCode = '246 810';
      final sudo = SudoService(source);

      // Normalising for the WIRE is the data source's job; what the service
      // must not do is refuse a pasted code for carrying a space.
      expect(
          await sudo.elevateWithCode('246 810', Localization(AppLanguage.ptBr)),
          isNull);
    });

    test('a malformed code never leaves the device', () async {
      final source = fakeSource()..sudoCode = '246810';
      final sudo = SudoService(source);

      final error =
          await sudo.elevateWithCode('2468', Localization(AppLanguage.ptBr));

      expect(error, Localization(AppLanguage.ptBr)[KApp.sudoErrCodeShape]);
      expect(source.codeAttempts, isEmpty,
          reason: 'a four-character guess must not spend a request, and must '
              'not spend one of the three attempts the server allows');
    });

    test('a refused code does NOT start the password cooldown', () async {
      // The ceiling on a code lives on the SERVER, which destroys it after
      // three wrong guesses. A local cooldown on top would punish the same
      // mistake twice — and the second time invisibly, on a proof the person
      // may still be holding a valid copy of.
      final source = fakeSource();
      final sudo = SudoService(source);

      for (var i = 0; i < 3; i++) {
        await sudo.elevateWithCode('000000', Localization(AppLanguage.ptBr));
      }

      expect(sudo.isCoolingDown, isFalse);
      expect(source.codeAttempts.length, 3);
    });

    test('the throttled answer still hands over a code to type', () async {
      // 429 here means one was sent moments ago and is STILL VALID. Sending
      // someone back to wait for a message already in their inbox is how they
      // end up asking for a third one.
      final source = fakeSource()
        ..throwOnRequestCode = const ElevationRefused(
            serverMessage: 'Já enviamos um código há pouco.',
            rateLimited: true);
      final sudo = SudoService(source);

      final asked = await sudo.requestCode(Localization(AppLanguage.ptBr));

      expect(asked.codeReady, isTrue);
      expect(asked.message, 'Já enviamos um código há pouco.');
      expect(sudo.codeMinutes, SudoRules.codeTtl.inMinutes);
    });

    test('a failed send says so and offers no code field', () async {
      final source = fakeSource()
        ..throwOnRequestCode =
            const ElevationRefused(serverMessage: 'Não foi possível enviar.');
      final sudo = SudoService(source);

      final asked = await sudo.requestCode(Localization(AppLanguage.ptBr));

      expect(asked.codeReady, isFalse);
      expect(asked.message, 'Não foi possível enviar.');
    });

    test('reset drops the code state with the window', () async {
      final sudo = SudoService(fakeSource()..sudoCode = '246810');
      await sudo.requestCode(Localization(AppLanguage.ptBr));
      await sudo.elevateWithCode('246810', Localization(AppLanguage.ptBr));

      sudo.reset();

      expect(sudo.isElevated, isFalse);
      expect(sudo.codeMinutes, isNull);
    });
  });

  group('the sheet — both proofs, no guessing', () {
    final l = Localization(AppLanguage.ptBr);

    testWidgets('a session with NO password reaches the code and elevates',
        (tester) async {
      // The whole item, in one test: this source accepts no password at all,
      // which is exactly what `elevate` answers for a Google account. Before
      // S-21 the sheet ended here, and so did the person.
      final source = fakeSource()
        ..sudoPassword = null
        ..sudoCode = '246810'
        ..sessionEmailValue = 'sem.senha@example.com';
      final sudo = SudoService(source);
      bool? granted;

      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) async {
          granted = await showSudoSheet(context: context, sudo: sudo);
        },
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      // The way across is offered without the sheet being told anything about
      // this account — it never asks which proof applies, because it is not in
      // a position to know.
      await tester.tap(find.text(l[KApp.sudoSendCode]));
      await tester.pumpAndSettle();

      expect(source.codeRequests, 1);
      expect(
          find.text(l.format(KApp.sudoCodeSentTo,
              ['sem.senha@example.com', '${SudoRules.codeTtl.inMinutes}'])),
          findsOne,
          reason: 'the prompt must name the address the code went to');

      await tester.enterText(find.byType(TextField), '246810');
      await tester.pump();
      await tester.tap(find.text(l[K.sudoConfirm]));
      await tester.pumpAndSettle();

      expect(granted, isTrue);
      expect(sudo.isElevated, isTrue);
      expect(source.codeAttempts, ['246810']);
    });

    testWidgets('the confirm button stays down until the code is well formed',
        (tester) async {
      final source = fakeSource()
        ..sudoCode = '246810'
        ..sessionEmailValue = 'alguem@example.com';
      final sudo = SudoService(source);

      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => showSudoSheet(context: context, sudo: sudo),
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.sudoSendCode]));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '2468');
      await tester.pump();
      final short = tester.widget<FilledButton>(find.ancestor(
          of: find.text(l[K.sudoConfirm]),
          matching: find.byType(FilledButton)));
      expect(short.onPressed, isNull);

      await tester.enterText(find.byType(TextField), '246810');
      await tester.pump();
      final full = tester.widget<FilledButton>(find.ancestor(
          of: find.text(l[K.sudoConfirm]),
          matching: find.byType(FilledButton)));
      expect(full.onPressed, isNotNull);
    });

    testWidgets('the way back to the password is never a dead end',
        (tester) async {
      final source = fakeSource()..sessionEmailValue = 'alguem@example.com';
      final sudo = SudoService(source);

      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => showSudoSheet(context: context, sudo: sudo),
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.sudoSendCode]));
      await tester.pumpAndSettle();
      expect(find.text(l[K.sudoCurrentPassword]), findsNothing);

      await tester.tap(find.text(l[KApp.sudoUsePassword]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.sudoCurrentPassword]), findsOne);
      expect(find.text(l[KApp.sudoSendCode]), findsOne);
    });

    testWidgets('the password cooldown does not disable the code',
        (tester) async {
      // Three wrong passwords start the LOCAL throttle. Someone who then
      // remembers they never had a password must still be able to ask for a
      // code — the cooldown is about guessing, and asking is not a guess.
      final source = fakeSource()..sessionEmailValue = 'alguem@example.com';
      final sudo = SudoService(source);
      for (var i = 0; i < 3; i++) {
        await sudo.elevate('errada', l);
      }
      expect(sudo.isCoolingDown, isTrue);

      await tester.pumpWidget(harness(
        sudo: sudo,
        onTap: (context) => showSudoSheet(context: context, sudo: sudo),
      ));
      await tester.tap(find.text('gatilho'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l[KApp.sudoSendCode]));
      await tester.pumpAndSettle();

      expect(source.codeRequests, 1);
      expect(find.text(l[KApp.sudoCodeLabel]), findsOne);
    });
  });
}
