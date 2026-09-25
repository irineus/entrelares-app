// U-38 — the sheet CHROME, pinned once for every sheet.
//
// AppSheetFrame pins "Salvar" at the bottom (U-28 QA), so the finger is there
// while the eyes may be anywhere in the scroll. Three things a tap on that row
// produces used to render inside the scroll — the failure, the question it
// raised, and (in the bulk sheet) the destructive action itself sat in a label
// row. These tests measure WHERE they land on a 700 dp phone, not whether they
// exist: U-28 already learned that presence is not position.
import 'dart:io';

import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart';
import 'day_editor_test.dart' show anaAdmin;

const _phone = Size(360, 700);

final _pt = Localization(AppLanguage.ptBr);

const _anaAdmin = Member(
  id: 1,
  fullName: 'Ana Souza',
  colorSlot: 1,
  userId: 'u1',
  isAdmin: true,
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(width: _phone.width, height: _phone.height, child: child),
    ),
  ),
);

void _usePhone(WidgetTester tester, {Size size = _phone}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The day sheet's form fits a 700 dp phone since the compact form (owner's
/// validation, 25/09/2026) — which was the point. Its pinned-row tests need a
/// body that scrolls, so they run on a short phone, where it still does.
const Size _shortPhone = Size(360, 560);

/// Visible as the reader holds the phone: on the screen AND reachable by a
/// tap at its centre. The second half is the one that matters — a banner at
/// the end of the scroll can sit inside the screen's bounds while hidden
/// behind the pinned action row or clipped by the body's viewport, and only a
/// hit test tells those apart.
void _expectOnScreen(WidgetTester tester, Finder finder, String what) {
  final target = find
      .descendant(of: finder, matching: find.byType(Text), matchRoot: true)
      .first;
  final rect = tester.getRect(target);
  expect(
    rect.top,
    greaterThanOrEqualTo(0),
    reason: '$what starts above the screen',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(_phone.height),
    reason: '$what ends below the screen ($rect)',
  );
  final box = tester.renderObject(target);
  final hit = tester.hitTestOnBinding(rect.center);
  expect(
    hit.path.any((entry) => entry.target == box),
    isTrue,
    reason:
        '$what is inside the screen but not where a finger reaches it '
        '— clipped by the scroll or covered by the pinned row ($rect)',
  );
}

/// Not inside the frame's scrolling body.
void _expectNotInScroll(Finder finder, String what) {
  expect(
    find.ancestor(of: finder, matching: find.byKey(AppSheetFrame.bodyKey)),
    findsNothing,
    reason: '$what must not scroll with the body',
  );
}

/// The reader back at the top of a sheet's form.
Future<void> _scrollBodyToTop(WidgetTester tester) async {
  await tester.drag(find.byKey(AppSheetFrame.bodyKey), const Offset(0, 3000));
  await tester.pumpAndSettle();
}

/// The sheet's body really is taller than what it shows — otherwise "pinned"
/// and "at the end of the scroll" are the same place and the test proves
/// nothing.
void _expectBodyScrolls(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(AppSheetFrame.bodyKey),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  expect(
    position.maxScrollExtent,
    greaterThan(0),
    reason:
        'the form fits on screen, so this test cannot tell pinned from '
        'scrolled',
  );
}

Widget _longFrame({String? error, Widget? confirmation, Widget? extra}) =>
    AppSheetFrame(
      title: 'Um dia qualquer',
      error: error,
      confirmation: confirmation,
      primaryLabel: 'Salvar',
      onPrimary: () {},
      secondaryLabel: 'Cancelar',
      onSecondary: () {},
      extraAction: extra,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 40, child: Text('linha $i')),
      ],
    );

/// The test font draws every glyph as a square one em wide, so a 220-character
/// warning takes eleven lines on a 360 dp phone and nothing fits anywhere.
/// A question about what fits on a screen has to be measured in the fonts the
/// screen uses: Inter (the app's theme) and Roboto (the bare MaterialApp the
/// calendar fixtures build).
Future<void> _loadRealFonts() async {
  Future<ByteData> bytes(String file) async => ByteData.sublistView(
    Uint8List.fromList(await File('assets/fonts/$file').readAsBytes()),
  );
  final inter = FontLoader('Inter');
  for (final f in [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    inter.addFont(bytes(f));
  }
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await Future.wait([inter.load(), roboto.load()]);
}

void main() {
  setUpAll(_loadRealFonts);

  group('AppSheetFrame', () {
    testWidgets('an error is pinned under the title, above the body, and '
        'stays put while the body scrolls', (tester) async {
      _usePhone(tester);
      await tester.pumpWidget(_host(_longFrame(error: 'Falha ao salvar.')));

      final banner = find.byKey(AppSheetFrame.errorKey);
      expect(
        find.descendant(of: banner, matching: find.text('Falha ao salvar.')),
        findsOneWidget,
      );
      _expectNotInScroll(banner, 'the error');
      final before = tester.getRect(banner);
      expect(before.bottom, lessThan(tester.getRect(find.text('linha 0')).top));

      await tester.drag(find.text('linha 3'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(banner), before);
      _expectOnScreen(tester, banner, 'the error');
    });

    testWidgets('an error comes before the pinned notice — it is about the '
        'tap just made', (tester) async {
      _usePhone(tester);
      await tester.pumpWidget(
        _host(
          const AppSheetFrame(
            title: 'Dia',
            error: 'Falhou',
            pinnedNotice: Text('Modo admin ligado'),
            children: [Text('corpo')],
          ),
        ),
      );
      expect(
        tester.getRect(find.text('Falhou')).top,
        lessThan(tester.getRect(find.text('Modo admin ligado')).top),
      );
    });

    testWidgets('a confirmation takes the action row\'s place, at the bottom, '
        'and hides the row and the extra action', (tester) async {
      _usePhone(tester);
      await tester.pumpWidget(
        _host(
          _longFrame(
            extra: AppSheetDangerAction(label: 'Limpar dia', onPressed: () {}),
          ),
        ),
      );
      final salvarRect = tester.getRect(find.text('Salvar'));

      await tester.pumpWidget(
        _host(
          _longFrame(
            extra: AppSheetDangerAction(label: 'Limpar dia', onPressed: () {}),
            confirmation: AppSheetConfirmation.destructive(
              message: 'Isso sobrescreve 3 dias.',
              yesLabel: 'Sim, alterar',
              onYes: () {},
              noLabel: 'Não, voltar',
              onNo: () {},
            ),
          ),
        ),
      );

      expect(find.text('Salvar'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.text('Limpar dia'), findsNothing);
      final strip = find.byKey(AppSheetFrame.confirmationKey);
      _expectNotInScroll(strip, 'the confirmation strip');
      _expectOnScreen(tester, find.text('Sim, alterar'), 'the confirmation');
      // Where the finger already is: the answer sits on the row "Salvar" was.
      expect(
        tester.getRect(strip).bottom,
        greaterThanOrEqualTo(salvarRect.bottom),
      );
    });

    testWidgets('a tall confirmation is capped and never starves the body', (
      tester,
    ) async {
      _usePhone(tester);
      await tester.pumpWidget(
        _host(
          _longFrame(
            confirmation: AppSheetConfirmation(
              message: 'Qual observação manter?',
              details: [for (var i = 0; i < 30; i++) Text('nota $i')],
              actions: FilledButton(
                onPressed: () {},
                child: const Text('Manter'),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(AppSheetFrame.confirmationKey)).height,
        lessThanOrEqualTo(_phone.height * 0.5 + 0.5),
      );
      expect(find.text('linha 0'), findsOneWidget);
    });

    testWidgets('the danger action wears the danger outline', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Center(
              child: AppSheetDangerAction(
                label: 'Limpar dias',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.text('Limpar dias'));
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Limpar dias'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      final side = button.style!.side!.resolve({});
      expect(side!.color, context.tokens.danger.border);
      expect(
        button.style!.foregroundColor!.resolve({}),
        context.tokens.danger.onContainer,
      );
    });

    testWidgets('AppClearToggle reports the tick and disables on null', (
      tester,
    ) async {
      bool? got;
      await tester.pumpWidget(
        _host(
          Center(
            child: AppClearToggle(
              label: 'Limpar',
              value: false,
              onChanged: (v) => got = v,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox));
      expect(got, isTrue);

      await tester.pumpWidget(
        _host(
          const Center(
            child: AppClearToggle(
              label: 'Limpar',
              value: false,
              onChanged: null,
            ),
          ),
        ),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    });
  });

  test('no sheet renders its error or its question inside the scroll', () {
    // The guard that keeps the convention from decaying: each of these was a
    // private copy in some sheet before U-38, and each is one line to write
    // back by accident.
    final offenders = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('sheets.dart'))) {
      final src = file.readAsStringSync();
      if (!src.contains('AppSheetFrame(')) continue;
      for (final pattern in [
        RegExp(r'message:\s*_error'),
        RegExp(r'Text\(\s*_error'),
        RegExp(r'pinnedNotice:\s*_error'),
        // The private confirmation box: a danger container holding a warning
        // icon. AppSheetConfirmation draws that now, in the right place.
        RegExp(
          r'Icons\.warning_amber_rounded,\s*size:\s*20,\s*color:\s*'
          r'context\.tokens\.danger\.onContainer',
        ),
        // "Limpar dias" as a red text button in a label row.
        RegExp(r'TextButton[\s\S]{0,200}colorScheme\.error'),
      ]) {
        if (pattern.hasMatch(src)) {
          offenders.add('${file.path}: ${pattern.pattern}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'an AppSheetFrame sheet passes its failure as `error:`, its '
          'question as `confirmation:` and its destructive action as an '
          'AppSheetDangerAction in `extraAction`: $offenders',
    );
  });

  group('the real sheets on a 700 dp phone', () {
    testWidgets(
      'day sheet: a failed save is visible from the pinned "Salvar"',
      (tester) async {
        final day = futureDay;
        if (day == null) return;
        _usePhone(tester, size: _shortPhone);
        // U-56: an ADMIN, because only she still sees the planned-parent
        // field — the tallest form, the one that scrolls on a 700 dp phone.
        final ds = FakeCustodyDataSource(
          members: [anaAdmin, bruno],
          days: [row(5, dayOfMonth(day), 1)],
        )..throwOnWrite = Exception('boom');
        await tester.pumpWidget(app(ds));
        await tester.pumpAndSettle();

        await openDayEditor(tester, day);
        final note = find.byType(TextField).last;
        await tester.ensureVisible(note);
        await tester.pumpAndSettle();
        await tester.enterText(note, 'Nota qualquer');
        // The defect's own posture: back at the TOP of the form, where the
        // planned parent is, and "Salvar" pinned at the bottom. The end of the
        // scroll — where the error used to be born — is out of sight.
        await _scrollBodyToTop(tester);
        _expectBodyScrolls(tester);
        await tester.tap(find.text(_pt[K.commonSave]));
        await tester.pumpAndSettle();

        final banner = find.byKey(AppSheetFrame.errorKey);
        expect(banner, findsOneWidget);
        _expectOnScreen(tester, banner, 'the day sheet error');
      },
    );

    testWidgets('day sheet: the S-09 question opens where "Salvar" was', (
      tester,
    ) async {
      final day = futureDay;
      if (day == null) return;
      _usePhone(tester, size: _shortPhone);
      final ds = FakeCustodyDataSource(
        members: [_anaAdmin, bruno],
        days: [row(7, dayOfMonth(day), 1)],
      );
      await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
      await tester.pumpAndSettle();

      await openDayEditor(tester, day);
      await tapSheet(tester, memberChip('Bruno').first);
      await _scrollBodyToTop(tester);
      await tester.tap(find.text(_pt[K.commonSave]));
      await tester.pumpAndSettle();

      expect(find.text(_pt[K.commonSave]), findsNothing);
      final yes = find.text(_pt[K.editorYesChange]);
      _expectNotInScroll(yes, 'the S-09 question');
      _expectOnScreen(tester, yes, 'the S-09 question');
      _expectOnScreen(
        tester,
        find.text(_pt[K.editorAdminChangeWarning]),
        'the S-09 warning',
      );

      await tester.tap(yes);
      await tester.pumpAndSettle();
      expect(ds.updated.single.scheduledParentId, 2);
      await settleSnack(tester);
    });

    testWidgets('bulk sheet: "Limpar dias" is the frame\'s destructive slot, '
        'and its question opens in the action row', (tester) async {
      final day = futureDay;
      if (day == null) return;
      _usePhone(tester);
      final ds = FakeCustodyDataSource(
        members: [_anaAdmin, bruno],
        days: [row(7, dayOfMonth(day), 1)],
      );
      await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
      await tester.pumpAndSettle();

      final cell = find.text('$day').last;
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.longPress(cell);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_pt.format(K.selectionEdit, [1])));
      await tester.pumpAndSettle();

      final clear = find.byKey(const Key('bulkClearDays'));
      _expectNotInScroll(clear, '"Limpar dias"');
      _expectOnScreen(tester, clear, '"Limpar dias"');
      expect(
        find.widgetWithText(TextButton, _pt[K.bulkClearDaysAction]),
        findsNothing,
      );

      await tester.tap(clear);
      await tester.pumpAndSettle();
      final yes = find.text(_pt[K.bulkYesDelete]);
      _expectNotInScroll(yes, 'the delete-all question');
      _expectOnScreen(tester, yes, 'the delete-all question');
    });

    testWidgets(
      'bulk sheet: a failed save is visible from the pinned "Salvar"',
      (tester) async {
        final day = futureDay;
        if (day == null) return;
        _usePhone(tester);
        final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
          ..throwOnWrite = Exception('boom');
        await tester.pumpWidget(app(ds));
        await tester.pumpAndSettle();

        final cell = find.text('$day').last;
        await tester.ensureVisible(cell);
        await tester.pumpAndSettle();
        await tester.longPress(cell);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_pt.format(K.selectionEdit, [1])));
        await tester.pumpAndSettle();
        await tapSheet(tester, find.byKey(const Key('bulkScheduled')));
        await tester.tap(find.text('Bruno Lima').last);
        await tester.pumpAndSettle();
        await _scrollBodyToTop(tester);
        _expectBodyScrolls(tester);
        await tester.tap(find.text(_pt[K.commonSave]));
        await tester.pumpAndSettle();

        final banner = find.byKey(AppSheetFrame.errorKey);
        expect(banner, findsOneWidget);
        _expectOnScreen(tester, banner, 'the bulk sheet error');
      },
    );
  });
}
