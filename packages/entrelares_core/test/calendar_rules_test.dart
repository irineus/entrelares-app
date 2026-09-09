/// Mirror of `entrelares-app` `Entrelares.Tests/CalendarHelpersTests.cs` —
/// same cases, same expected verdicts, both languages since the U-13/U-24
/// port (T-53 lote 1). The two suites must keep saying the same thing: a
/// divergence here is a bug in the port, not a test to adjust.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _today = DateTime(2026, 8, 19);
DateTime _fromToday(int days) => _today.add(Duration(days: days));

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

void main() {
  group('daysUntilLabel', () {
    const cases = {
      0: 'hoje',
      1: 'amanhã',
      2: 'em 2 dias',
      7: 'em 7 dias',
      -1: 'ontem',
      -3: 'há 3 dias', // T-08 finding: used to render "em -3 dias"
    };
    cases.forEach((days, expected) {
      test('$days dia(s) → "$expected"', () {
        expect(daysUntilLabel(_fromToday(days), _today, _pt), expected);
      });
    });

    // The English half: the words come from the catalog, the rule is shared.
    const enCases = {
      0: 'today',
      1: 'tomorrow',
      2: 'in 2 days',
      -1: 'yesterday',
      -3: '3 days ago',
    };
    enCases.forEach((days, expected) {
      test('$days day(s) → "$expected" (EN)', () {
        expect(daysUntilLabel(_fromToday(days), _today, _en), expected);
      });
    });
  });

  group('isTransitionDay', () {
    test('no previous day: custody starts here', () {
      expect(isTransitionDay(null, 1), isTrue);
    });
    test('the responsible changes', () {
      expect(isTransitionDay(1, 2), isTrue);
    });
    test('same responsible as yesterday', () {
      expect(isTransitionDay(2, 2), isFalse);
    });
  });

  group('formatHandoffDate', () {
    test('abbreviated PT-BR weekday without trailing dot', () {
      // 04/07/2025 is a Friday — the C# suite's own example ("sex, 04/07").
      expect(formatHandoffDate(DateTime(2025, 7, 4), _pt), 'sex, 04/07');
    });
    test('PT-BR numeric part stays dd/MM', () {
      expect(formatHandoffDate(DateTime(2026, 8, 19), _pt), 'qua, 19/08');
    });
    // U-24 applied to the numeric half too: an English reader must never see
    // `04/07` (the web helper's dd/MM-in-English is a frozen residue, not the
    // rule — see the function's doc comment).
    test('EN gets the weekday and the spelled month', () {
      expect(formatHandoffDate(DateTime(2025, 7, 4), _en), 'Fri, 04 Jul');
      expect(formatHandoffDate(DateTime(2026, 8, 19), _en), 'Wed, 19 Aug');
    });
  });

  group('handoffUrgency', () {
    const cases = {
      0: HandoffUrgency.urgent,
      1: HandoffUrgency.soon,
      2: HandoffUrgency.near,
      3: HandoffUrgency.none,
    };
    cases.forEach((days, expected) {
      test('$days dia(s) → $expected', () {
        expect(handoffUrgency(_fromToday(days), _today), expected);
      });
    });
  });

  // Members: Ana (slot 1), Bruno (slot 2) — distinct first letters.
  const ana = MemberView(id: 1, fullName: 'Ana Souza', colorSlot: 1);
  const bruno = MemberView(id: 2, fullName: 'Bruno Lima', colorSlot: 2);
  const family = [ana, bruno];

  group('dayPaint', () {
    test('null schedule is unassigned', () {
      expect(dayPaint(null, family), isA<DayUnassigned>());
    });
    test('actual differs from scheduled → swapped', () {
      const day = DayAssignment(scheduledParentId: 1, actualParentId: 2);
      expect(dayPaint(day, family), isA<DaySwapped>());
    });
    test('actual equals scheduled → not swapped, scheduled slot', () {
      const day = DayAssignment(scheduledParentId: 1, actualParentId: 1);
      final paint = dayPaint(day, family);
      expect(paint, isA<DaySlot>());
      expect((paint as DaySlot).slot, 1);
    });
    test('scheduled only → member slot (F-27: slot, not role)', () {
      const day = DayAssignment(scheduledParentId: 2);
      expect((dayPaint(day, family) as DaySlot).slot, 2);
    });
    test('inactive member → slot 0 (gray)', () {
      const gone = MemberView(
          id: 3, fullName: 'Caio', colorSlot: 3, isActiveMember: false);
      const day = DayAssignment(scheduledParentId: 3);
      expect((dayPaint(day, [ana, bruno, gone]) as DaySlot).slot, 0);
    });
  });

  group('isSwapped', () {
    test('null schedule → false', () => expect(isSwapped(null), isFalse));
    test('actual differs → true', () {
      expect(
          isSwapped(const DayAssignment(scheduledParentId: 1, actualParentId: 2)),
          isTrue);
    });
    test('no actual parent → false', () {
      expect(isSwapped(const DayAssignment(scheduledParentId: 1)), isFalse);
    });
    test('actual equals scheduled → false', () {
      expect(
          isSwapped(const DayAssignment(scheduledParentId: 1, actualParentId: 1)),
          isFalse);
    });
    test('matches dayPaint swapped verdict', () {
      const day = DayAssignment(scheduledParentId: 1, actualParentId: 2);
      expect(isSwapped(day), dayPaint(day, family) is DaySwapped);
    });
  });

  group('parentInitial', () {
    test('null schedule → bullet', () {
      expect(parentInitial(null, family), '•');
    });
    test('uses actual parent when swapped', () {
      const day = DayAssignment(scheduledParentId: 1, actualParentId: 2);
      expect(parentInitial(day, family), 'B');
    });
    test('falls back to scheduled parent', () {
      const day = DayAssignment(scheduledParentId: 1);
      expect(parentInitial(day, family), 'A');
    });
    test('unknown parent → question mark', () {
      const day = DayAssignment(scheduledParentId: 99);
      expect(parentInitial(day, family), '?');
    });
  });

  group('displayInitials (F-28 accessibility tiers)', () {
    test('tier 1 — unique first letters stay a single letter', () {
      expect(displayInitials(1, family), 'A');
      expect(displayInitials(2, family), 'B');
    });
    test('tier 2 — same first letter resolves via the surname initial', () {
      const maria1 = MemberView(id: 1, fullName: 'Maria Souza', colorSlot: 1);
      const maria2 = MemberView(id: 2, fullName: 'Maria Oliveira', colorSlot: 2);
      expect(displayInitials(1, const [maria1, maria2]), 'MS');
      expect(displayInitials(2, const [maria1, maria2]), 'MO');
    });
    test('tier 3 — identical names append the slot index (legend order)', () {
      const m1 = MemberView(id: 1, fullName: 'Maria Souza', colorSlot: 1);
      const m2 = MemberView(id: 2, fullName: 'Maria Souza', colorSlot: 2);
      expect(displayInitials(1, const [m1, m2]), 'MS1');
      expect(displayInitials(2, const [m1, m2]), 'MS2');
    });
    test('single-word same name collides straight into the slot fallback', () {
      const m1 = MemberView(id: 1, fullName: 'Maria', colorSlot: 1);
      const m2 = MemberView(id: 2, fullName: 'Maria', colorSlot: 2);
      expect(displayInitials(1, const [m1, m2]), 'M1');
      expect(displayInitials(2, const [m1, m2]), 'M2');
    });
  });

  group('profileSlotIndex', () {
    test('active member with slot 1-4 → the slot', () {
      expect(profileSlotIndex(1, family), 1);
      expect(profileSlotIndex(2, family), 2);
    });
    test('unknown id → 0', () => expect(profileSlotIndex(99, family), 0));
    test('inactive member → 0 even with a slot recorded', () {
      const gone = MemberView(
          id: 3, fullName: 'Caio', colorSlot: 3, isActiveMember: false);
      expect(profileSlotIndex(3, const [ana, bruno, gone]), 0);
    });
    test('active member without slot → 0', () {
      const noSlot = MemberView(id: 4, fullName: 'Duda');
      expect(profileSlotIndex(4, const [noSlot]), 0);
    });
    test('F-56: a pending member keeps its slot — the grey texture is the '
        'departure\'s, not the missing account\'s', () {
      const pending = MemberView(
          id: 5,
          fullName: 'Eva',
          colorSlot: 3,
          isActiveMember: false,
          isPendingMember: true);
      expect(profileSlotIndex(5, const [ana, bruno, pending]), 3);
      expect(pending.isAssignable, isTrue);
    });
  });
}
