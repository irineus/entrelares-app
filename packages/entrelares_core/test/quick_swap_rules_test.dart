/// F-65 — the quick swap from a selected pair of days. Every clause of
/// `quickSwapPlan` is a reason the workflow would refuse or the pairing would
/// not hold; each has its negative here, next to the plan it produces when
/// everything qualifies.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _today = DateTime(2026, 9, 15);
DateTime _d(int day) => DateTime(2026, 9, day);

const _ana = MemberView(id: 1, fullName: 'Ana');
const _bruno = MemberView(id: 2, fullName: 'Bruno');
const _carla = MemberView(id: 3, fullName: 'Carla');
const _pending = MemberView(
    id: 4, fullName: 'Dani', isActiveMember: false, isPendingMember: true);
const _departed = MemberView(id: 5, fullName: 'Edu', isActiveMember: false);
const _members = [_ana, _bruno, _carla, _pending, _departed];

QuickSwapDay _day(int day, int planned, {int? actual}) =>
    QuickSwapDay(date: _d(day), scheduledParentId: planned, actualParentId: actual);

QuickSwapPlan? _plan(List<QuickSwapDay> selected,
        {int? requester = 1,
        Iterable<DateTime> frozen = const [],
        List<MemberView> members = _members}) =>
    quickSwapPlan(
      selected: selected,
      requesterId: requester,
      today: _today,
      frozenDates: frozen,
      members: members,
    );

void main() {
  group('quickSwapPlan — the pair the owner described (15/09/2026)', () {
    test('1+1: two planned parents, one day each → a two-request plan', () {
      final plan = _plan([_day(20, 1), _day(23, 2)]);
      expect(plan, isNotNull);
      expect(plan!.requesterId, 1);
      expect(plan.counterpartId, 2);
      expect(plan.requesterDays, [_d(20)]);
      expect(plan.counterpartDays, [_d(23)]);
      expect(plan.dayCount, 2);
      // Every day is proposed to the OTHER parent; planned parents untouched.
      expect(plan.requests, [
        (date: _d(20), proposedActualParentId: 2),
        (date: _d(23), proposedActualParentId: 1),
      ]);
    });

    test('2+1 is not a pair yet → no plan; 2+2 → a four-request plan', () {
      expect(_plan([_day(20, 1), _day(23, 2), _day(21, 1)]), isNull);
      final plan = _plan([_day(20, 1), _day(23, 2), _day(21, 1), _day(24, 2)]);
      expect(plan, isNotNull);
      expect(plan!.dayCount, 4);
      expect(plan.requesterDays, [_d(20), _d(21)]);
      expect(plan.counterpartDays, [_d(23), _d(24)]);
    });

    test('the requests come out in calendar order whoever gives them', () {
      final plan = _plan([_day(24, 2), _day(20, 1), _day(23, 2), _day(21, 1)]);
      expect(plan!.requests.map((r) => r.date).toList(),
          [_d(20), _d(21), _d(23), _d(24)]);
    });

    test('the counterpart may be the requester: Bruno sees the same pair '
        'from his side', () {
      final plan = _plan([_day(20, 1), _day(23, 2)], requester: 2);
      expect(plan!.requesterId, 2);
      expect(plan.counterpartId, 1);
      expect(plan.requesterDays, [_d(23)]);
      expect(plan.counterpartDays, [_d(20)]);
      expect(plan.requests, [
        (date: _d(20), proposedActualParentId: 2),
        (date: _d(23), proposedActualParentId: 1),
      ]);
    });
  });

  group('quickSwapPlan — what hides the button', () {
    test('three planned parents', () {
      expect(_plan([_day(20, 1), _day(23, 2), _day(25, 3)]), isNull);
    });

    test('one planned parent only, or an empty selection', () {
      expect(_plan([_day(20, 1), _day(21, 1)]), isNull);
      expect(_plan([]), isNull);
    });

    test('an unassigned day (no planned parent)', () {
      expect(_plan([_day(20, 1), _day(23, 2), _day(25, 0)]), isNull);
    });

    test('a past day (F-13); today itself still qualifies', () {
      expect(_plan([_day(14, 1), _day(23, 2)]), isNull);
      expect(_plan([_day(15, 1), _day(23, 2)]), isNotNull);
    });

    test('a frozen day (F-12: a pending request already holds it)', () {
      expect(_plan([_day(20, 1), _day(23, 2)], frozen: [_d(23)]), isNull);
      // Date-only comparison, like every frozen check.
      expect(_plan([_day(20, 1), _day(23, 2)], frozen: [DateTime(2026, 9, 23, 8)]),
          isNull);
    });

    test('an already-swapped day (actual set and ≠ planned) — that is a '
        'revert, not a quick swap', () {
      expect(_plan([_day(20, 1, actual: 2), _day(23, 2)]), isNull);
      // actual == planned is not a swap: still clean.
      expect(_plan([_day(20, 1, actual: 1), _day(23, 2)]), isNotNull);
    });

    test('F-28: the requester must be one of the two planned parents', () {
      expect(_plan([_day(20, 1), _day(23, 2)], requester: 3), isNull);
      expect(_plan([_day(20, 1), _day(23, 2)], requester: null), isNull);
    });

    test('F-56 / S-11: a pending or departed counterpart cannot approve', () {
      expect(_plan([_day(20, 1), _day(23, 4)]), isNull);
      expect(_plan([_day(20, 1), _day(23, 5)]), isNull);
      // The requester's own seat is checked the same way.
      expect(_plan([_day(20, 4), _day(23, 1)], requester: 4), isNull);
    });

    test('a parent the roster does not know', () {
      expect(_plan([_day(20, 1), _day(23, 2)], members: const [_ana]), isNull);
    });
  });
}
