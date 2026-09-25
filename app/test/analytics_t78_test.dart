// T-78 — the product events: one catalogue, enforced at the transport, and
// fired where the action HAPPENED (after the write), never from `build`.
//
// The catalogue itself (names, keys, the token filter) is proven in core
// (`analytics_catalog_test.dart`). This suite pins what only the app can get
// wrong: a call site that spells a name by hand, a transport that lets an
// undeclared prop through, and a sheet that counts an action that failed or
// never changed anything.
import 'dart:convert';
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';

/// Every event this service sent, as (name, data).
class _Recorder {
  final events = <({String name, Map<String, dynamic>? data})>[];

  late final AnalyticsService service = AnalyticsService(
    websiteId: 'site-1',
    host: 'https://cloud.umami.is',
    hostname: 'app.entrelares.app',
    client: MockClient((request) async {
      final payload = (jsonDecode(request.body)
          as Map<String, dynamic>)['payload'] as Map<String, dynamic>;
      final name = payload['name'] as String?;
      if (name != null) {
        events.add((name: name, data: payload['data'] as Map<String, dynamic>?));
      }
      return http.Response('', 200);
    }),
  );

  List<String> get names => [for (final e in events) e.name];
}

void main() {
  group('the transport enforces the catalogue', () {
    test('an undeclared key and a free-text value never leave the device',
        () async {
      final r = _Recorder();
      await r.service.trackEvent(AnalyticsEvents.supportContactSent, props: {
        'category': 'problem',
        'signed_in': 'yes',
        'message': 'Não consigo entrar na conta da Ana',
      });
      await r.service.trackEvent(AnalyticsEvents.preferenceChanged,
          props: {'pref': 'language', 'value': 'ana@example.com'});

      expect(r.events[0].data, {'category': 'problem', 'signed_in': 'yes'});
      expect(r.events[1].data, {'pref': 'language'});
    });

    test('a name outside the catalogue fails loudly in debug', () {
      expect(() => _Recorder().service.trackEvent('made-up-event'),
          throwsA(isA<AssertionError>()));
    });
  });

  group('lib/ names events only through AnalyticsEvents', () {
    // A literal at a call site is how a rename slips in unseen: the string
    // compiles, the dashboard gets a NEW series and the old one flat-lines.
    test('no trackEvent/trackEventOnce/event: argument is a string literal',
        () {
      final literal =
          RegExp(r'''(trackEvent(?:Once)?\(\s*|\bevent:\s*)['"]''');
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (literal.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'use an AnalyticsEvents constant (core analytics_catalog)');
    });
  });

  group('day-note-saved', () {
    testWidgets('fires once when a save WROTE the note', (tester) async {
      final day = futureDay;
      if (day == null) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(
        members: [ana, bruno],
        days: [row(5, dayOfMonth(day), 1)],
      )..analytics = r.service;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDayEditor(tester, day);
      await tester.enterText(find.byType(TextField), 'Trocar mochila');
      await tapSheet(tester, find.text('Salvar'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(r.names.where((n) => n == AnalyticsEvents.dayNoteSaved),
          hasLength(1));
      expect(
          r.events
              .firstWhere((e) => e.name == AnalyticsEvents.dayNoteSaved)
              .data,
          {'state': 'set'});
      await settleSnack(tester);
    });

    testWidgets('a save the server refused counts nothing', (tester) async {
      final day = futureDay;
      if (day == null) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(
        members: [ana, bruno],
        days: [row(5, dayOfMonth(day), 1)],
      )
        ..analytics = r.service
        ..throwOnWrite = Exception('23505 duplicate key');
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDayEditor(tester, day);
      await tester.enterText(find.byType(TextField), 'Nota qualquer');
      await tapSheet(tester, find.text('Salvar'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(r.names, isNot(contains(AnalyticsEvents.dayNoteSaved)));
    });
  });

  group('day-sheet-closed (U-56)', () {
    // The number that says whether opening in the editor was right: how many
    // sheets end with nothing written, per opening mode.
    Map<String, dynamic>? closed(_Recorder r) => r.events
        .where((e) => e.name == AnalyticsEvents.daySheetClosed)
        .single
        .data;

    testWidgets('a day opened and closed with nothing written: edit × none',
        (tester) async {
      final day = futureDay;
      if (day == null) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(
        members: [ana, bruno],
        days: [row(5, dayOfMonth(day), 1)],
      )..analytics = r.service;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, day);
      await tapSheet(tester, find.byKey(AppSheetFrame.closeKey));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(closed(r), {'mode': 'edit', 'outcome': 'none'});
    });

    testWidgets('a save that wrote: edit × saved, once', (tester) async {
      final day = futureDay;
      if (day == null) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(
        members: [ana, bruno],
        days: [row(5, dayOfMonth(day), 1)],
      )..analytics = r.service;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, day);
      await tester.enterText(find.byType(TextField), 'Trocar mochila');
      await tapSheet(tester, find.text('Salvar'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(closed(r), {'mode': 'edit', 'outcome': 'saved'});
      await settleSnack(tester);
    });

    testWidgets('an empty day planned: plan × saved', (tester) async {
      final day = futureDay;
      if (day == null) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..analytics = r.service;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, day);
      await tapSheet(tester, memberChip('Bruno'));
      await tapSheet(tester, find.text('Salvar'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(closed(r), {'mode': 'plan', 'outcome': 'saved'});
      await settleSnack(tester);
    });

    testWidgets('a read-only past day: view × none', (tester) async {
      if (today.day == 1) return;
      final r = _Recorder();
      final ds = FakeCustodyDataSource(
        members: [ana, bruno],
        days: [row(5, dayOfMonth(today.day - 1), 1)],
      )..analytics = r.service;
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      await openDay(tester, today.day - 1);
      await tapSheet(tester, find.byKey(AppSheetFrame.closeKey));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(closed(r), {'mode': 'view', 'outcome': 'none'});
    });
  });
}
