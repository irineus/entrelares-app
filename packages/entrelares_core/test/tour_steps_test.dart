/// Mirror of `entrelares-app` `Entrelares.Tests/TourStepsTests.cs`, minus the
/// one case that cannot port: the web test greps the .razor markup to prove
/// every CSS selector still exists. Its Flutter twin is a WIDGET test (the
/// shell must register a key for every [TourTarget]) and rides with the
/// onboarding PR — a target with no widget degrades to a card with no
/// spotlight, which is a silent regression worth catching.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  test('four stops', () {
    expect(TourSteps.all, hasLength(4));
    expect(TourSteps.count, 4);
  });

  test('in reading order: today, colours, wizard, notifications', () {
    expect(TourSteps.all.map((s) => s.target), [
      TourTarget.todayCard,
      TourTarget.calendarLegend,
      TourTarget.actionsMenu,
      TourTarget.notificationsTab,
    ]);
  });

  test('every stop has a title and a body', () {
    for (final step in TourSteps.all) {
      expect(step.titleKey.trim(), isNotEmpty);
      expect(step.bodyKey.trim(), isNotEmpty);
      expect(step.titleKey, isNot(step.bodyKey));
    }
  });

  test('no two stops share a target', () {
    final targets = TourSteps.all.map((s) => s.target).toSet();
    expect(targets, hasLength(TourSteps.all.length));
  });

  test('no two stops share copy', () {
    final keys = [
      for (final step in TourSteps.all) ...[step.titleKey, step.bodyKey]
    ];
    expect(keys.toSet(), hasLength(keys.length));
  });

  group('at', () {
    test('returns each stop by index', () {
      for (var i = 0; i < TourSteps.count; i++) {
        expect(TourSteps.at(i), same(TourSteps.all[i]));
      }
    });

    test('null past the end signals "finished" — the caller advances until it '
        'gets null instead of tracking the bound itself', () {
      expect(TourSteps.at(TourSteps.count), isNull);
    });

    test('null before the start', () {
      expect(TourSteps.at(-1), isNull);
    });
  });
}
