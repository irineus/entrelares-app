/// The day editor's pure decision rules — inline in `Home.razor` on the web,
/// with no C# unit suite. These pin the port to the web's documented
/// behaviour (F-28 scenario gate, the S-09 admin confirmation).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('canOfferAsActual (F-28 scenario gate)', () {
    // Family: user 1, planned parent of the day 2, current actual 3.
    bool offer(int candidate,
            {int? user = 1, int scheduled = 2, int? actual}) =>
        canOfferAsActual(
          candidateId: candidate,
          userProfileId: user,
          editingScheduledParentId: scheduled,
          existingActualParentId: actual,
        );

    test('scenario A: the day\'s planned parent may offer anyone', () {
      expect(offer(3, user: 2, scheduled: 2), isTrue);
      expect(offer(4, user: 2, scheduled: 2), isTrue);
    });

    test('scenario B: otherwise only themselves', () {
      expect(offer(1), isTrue);
      expect(offer(4), isFalse); // scenario C: a third member — forbidden
    });

    test('the planned parent stays listed (no-swap saves keep working)', () {
      expect(offer(2), isTrue);
    });

    test('the current actual stays listed (revert saves keep working)', () {
      expect(offer(3, actual: 3), isTrue);
    });

    test('no user profile loaded: only planned/current-actual candidates', () {
      expect(offer(2, user: null), isTrue);
      expect(offer(4, user: null), isFalse);
    });
  });

  group('needsAdminScheduleChangeConfirm (S-09)', () {
    test('changing the planned parent of an assigned day asks first', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isTrue);
    });
    test('an unassigned day never asks', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: null,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isFalse);
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 0,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isFalse);
    });
    test('keeping the same parent never asks', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 1,
            alreadyConfirmed: false,
          ),
          isFalse);
    });
    test('a given confirmation is consumed by the save, not asked again', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 2,
            alreadyConfirmed: true,
          ),
          isFalse);
    });
  });

  group('swapAvailableForScheduled (F-56)', () {
    const active = MemberView(id: 1, fullName: 'Ana');
    const pending = MemberView(
        id: 2, fullName: 'Bia', isActiveMember: false, isPendingMember: true);
    const gone = MemberView(id: 3, fullName: 'Caio', isActiveMember: false);
    const members = [active, pending, gone];

    test('a pending planned parent has nobody to approve — no workflow', () {
      expect(swapAvailableForScheduled(2, members), isFalse);
    });
    test('an active planned parent keeps the workflow', () {
      expect(swapAvailableForScheduled(1, members), isTrue);
    });
    test('a departed planned parent is the S-11 ghost, not this rule', () {
      expect(swapAvailableForScheduled(3, members), isTrue);
    });
    test('no planned parent, or an unknown one, never blocks', () {
      expect(swapAvailableForScheduled(null, members), isTrue);
      expect(swapAvailableForScheduled(0, members), isTrue);
      expect(swapAvailableForScheduled(99, members), isTrue);
    });
  });
}
