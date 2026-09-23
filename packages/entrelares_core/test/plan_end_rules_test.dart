import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 9, 23);

  group('PlanEndRules.wizardStart', () {
    test('a plan still ahead opens on the day after its last day', () {
      expect(PlanEndRules.wizardStart('2026-11-12', today), DateTime(2026, 11, 13));
    });

    test('the last day being today opens tomorrow', () {
      expect(PlanEndRules.wizardStart('2026-09-23', today), DateTime(2026, 9, 24));
    });

    test('a plan that ended yesterday opens today', () {
      expect(PlanEndRules.wizardStart('2026-09-22', today), today);
    });

    test('a plan that ended long ago opens today, never in the past', () {
      expect(PlanEndRules.wizardStart('2026-08-17', today), today);
    });

    test('the month and year roll over', () {
      expect(PlanEndRules.wizardStart('2026-12-31', today), DateTime(2027, 1, 1));
    });

    test('a time of day on today is ignored', () {
      expect(PlanEndRules.wizardStart('2026-09-01', DateTime(2026, 9, 23, 18, 30)),
          today);
    });

    test('not an ISO day → null', () {
      for (final bad in [null, '', '12/11/2026', '2026-02-30', '2026-11-12T00:00']) {
        expect(PlanEndRules.wizardStart(bad, today), isNull, reason: '$bad');
      }
    });
  });

  group('PlanEndRules.actionStart', () {
    test('both kinds the job writes offer the action', () {
      expect(
          PlanEndRules.actionStart(
              'plan_ending', '{"kind":"ending","date":"2026-11-12"}', today),
          DateTime(2026, 11, 13));
      expect(
          PlanEndRules.actionStart(
              'plan_ending', '{"kind":"ended","date":"2026-09-22"}', today),
          today);
    });

    test('another type, an unknown kind, no date or bad JSON offer nothing', () {
      for (final (type, json) in [
        ('billing', '{"kind":"ending","date":"2026-11-12"}'),
        ('plan_ending', '{"kind":"something_new","date":"2026-11-12"}'),
        ('plan_ending', '{"kind":"ending"}'),
        ('plan_ending', '{"kind":"ending","date":12}'),
        ('plan_ending', '[1,2]'),
        ('plan_ending', 'not json'),
      ]) {
        expect(PlanEndRules.actionStart(type, json, today), isNull,
            reason: '$type $json');
      }
      expect(PlanEndRules.actionStart('plan_ending', null, today), isNull);
    });
  });

  group('PlanEndRules.stripKind', () {
    test('never planned: nothing (the empty-month strip owns that case)', () {
      expect(PlanEndRules.stripKind(null, today), isNull);
    });

    test('31 days ahead: nothing; 30: ending; today: ending', () {
      expect(PlanEndRules.stripKind(DateTime(2026, 10, 24), today), isNull);
      expect(PlanEndRules.stripKind(DateTime(2026, 10, 23), today), 'ending');
      expect(PlanEndRules.stripKind(today, today), 'ending');
    });

    test('yesterday or before: ended', () {
      expect(PlanEndRules.stripKind(DateTime(2026, 9, 22), today), 'ended');
      expect(PlanEndRules.stripKind(DateTime(2026, 9, 2), today), 'ended');
    });

    test('a time of day on either side is ignored', () {
      expect(
          PlanEndRules.stripKind(
              DateTime(2026, 9, 23, 0, 1), DateTime(2026, 9, 23, 23, 59)),
          'ending');
    });
  });

  test('startAfter: the next day, never before today', () {
    expect(PlanEndRules.startAfter(DateTime(2026, 10, 1), today),
        DateTime(2026, 10, 2));
    expect(PlanEndRules.startAfter(DateTime(2026, 9, 2), today), today);
  });
}
