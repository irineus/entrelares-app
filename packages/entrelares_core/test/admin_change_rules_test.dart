import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-81 — what a `day_admin_change` row opens: the day for one, the
/// Histórico for several, nothing for a shape no writer sends today.
void main() {
  const type = AdminChangeRules.type;

  group('AdminChangeRules.targetOf', () {
    test('one day opens that day', () {
      const json = '{"kind":"single","date":"2026-10-12","name":"Ana"}';
      expect(AdminChangeRules.targetOf(type, json), AdminChangeTarget.day);
      expect(AdminChangeRules.dayOf(type, json), DateTime(2026, 10, 12));
    });

    test('several days open the Histórico', () {
      const json =
          '{"kind":"batch","date":"2026-10-12","to":"2026-10-20","count":"9"}';
      expect(
        AdminChangeRules.targetOf(type, json),
        AdminChangeTarget.auditTrail,
      );
      expect(AdminChangeRules.dayOf(type, json), isNull);
    });

    test('another type, a future kind or a bad day offers nothing', () {
      expect(
        AdminChangeRules.targetOf(
          'plan_ending',
          '{"kind":"single","date":"2026-10-12"}',
        ),
        isNull,
      );
      expect(
        AdminChangeRules.targetOf(
          type,
          '{"kind":"undone","date":"2026-10-12"}',
        ),
        isNull,
      );
      expect(
        AdminChangeRules.targetOf(
          type,
          '{"kind":"single","date":"12/10/2026"}',
        ),
        isNull,
      );
      expect(AdminChangeRules.targetOf(type, '{"kind":"single"}'), isNull);
      expect(AdminChangeRules.targetOf(type, null), isNull);
      expect(AdminChangeRules.targetOf(type, 'not json'), isNull);
    });
  });

  group('AdminChangeRules.parseIsoDay', () {
    test('a real calendar day', () {
      expect(AdminChangeRules.parseIsoDay('2026-02-28'), DateTime(2026, 2, 28));
    });

    test('a day that rolls over, or any other shape, is refused', () {
      for (final value in [
        '2026-02-30',
        '2026-13-01',
        '2026-10-12T00:00',
        ' 2026-10-12',
        '',
        null,
        20261012,
      ]) {
        expect(AdminChangeRules.parseIsoDay(value), isNull, reason: '$value');
      }
    });
  });

  test('the push routing names the same type and kinds', () {
    expect(PushRouting.adminChangeType, AdminChangeRules.type);
    expect(PushRouting.adminChangeDayKinds, {AdminChangeRules.single});
    expect(PushRouting.adminChangeTrailKinds, {AdminChangeRules.batch});
  });
}
