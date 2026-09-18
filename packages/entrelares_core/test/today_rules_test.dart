/// Today-at-a-Glance rules (T-53 lote 1) — the projection that lived inline
/// (untested) in the web's `Home.razor:83–106` and the next-handoff scan of
/// `CustodyService.GetNextHandoffDateAsync`. The behaviours pinned here are
/// the web's, verbatim — including the card's deliberately NAIVE avatar
/// letter (not the collision-resolving day-cell initials).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  const ana = MemberView(id: 1, fullName: 'Ana Silva', colorSlot: 1);
  const bruno = MemberView(id: 2, fullName: 'Bruno Souza', colorSlot: 2);
  const members = [ana, bruno];

  group('todayGlance — the card projection', () {
    test('no schedule: unified card, no responsible, "?" avatar', () {
      final g = todayGlance(
        userProfileId: 1,
        scheduledParentId: null,
        actualParentId: null,
        handoffTime: null,
        members: members,
      );
      expect(g.hasSchedule, isFalse);
      expect(g.responsibleName, isNull);
      expect(g.avatarLetter, '?');
      expect(g.isSwapped, isFalse);
      expect(g.userSlot, 1);
      expect(g.responsibleSlot, 1);
      expect(g.isUnified, isTrue);
    });

    test('scheduled day: responsible resolved, naive first-letter avatar', () {
      final g = todayGlance(
        userProfileId: 1,
        scheduledParentId: 2,
        actualParentId: null,
        handoffTime: null,
        members: members,
      );
      expect(g.hasSchedule, isTrue);
      expect(g.responsibleName, 'Bruno Souza');
      expect(g.avatarLetter, 'B');
      expect(g.isSwapped, isFalse);
      expect(g.userSlot, 1);
      expect(g.responsibleSlot, 2);
      expect(g.isUnified, isFalse);
    });

    // T-27: the responsible that counts is actual ?? scheduled.
    test('swapped day: the ACTUAL parent is the responsible', () {
      final g = todayGlance(
        userProfileId: 2,
        scheduledParentId: 1,
        actualParentId: 2,
        handoffTime: '18:30:00',
        members: members,
      );
      expect(g.responsibleName, 'Bruno Souza');
      expect(g.isSwapped, isTrue);
      expect(g.handoffTime, '18:30:00');
      expect(g.responsibleSlot, 2);
      expect(g.isUnified, isTrue); // user IS the responsible
    });

    test('actual equal to scheduled is not a swap', () {
      final g = todayGlance(
        userProfileId: 1,
        scheduledParentId: 2,
        actualParentId: 2,
        handoffTime: null,
        members: members,
      );
      expect(g.isSwapped, isFalse);
    });

    test('unknown responsible: name null, "?" avatar, accent falls back to '
        'the user (unified)', () {
      final g = todayGlance(
        userProfileId: 1,
        scheduledParentId: 99,
        actualParentId: null,
        handoffTime: null,
        members: members,
      );
      expect(g.hasSchedule, isTrue);
      expect(g.responsibleName, isNull);
      expect(g.avatarLetter, '?');
      expect(g.responsibleSlot, 1);
      expect(g.isUnified, isTrue);
    });

    test('no signed-in profile: gray accent (slot 0)', () {
      final g = todayGlance(
        userProfileId: null,
        scheduledParentId: null,
        actualParentId: null,
        handoffTime: null,
        members: members,
      );
      expect(g.userSlot, 0);
      expect(g.responsibleSlot, 0);
    });
  });

  group('nextHandoffDate — the 90-day scan', () {
    UpcomingDay day(int d, int scheduled, {int? actual}) => (
          date: DateTime(2026, 8, d),
          scheduledParentId: scheduled,
          actualParentId: actual,
        );

    test('first day with a DIFFERENT effective responsible wins', () {
      expect(
        nextHandoffDate(1, [day(20, 1), day(21, 1), day(22, 2), day(23, 2)]),
        DateTime(2026, 8, 22),
      );
    });

    // A swap makes the effective parent differ even when the plan does not.
    test('the comparison is on the EFFECTIVE parent (actual ?? scheduled)',
        () {
      expect(
        nextHandoffDate(1, [day(20, 1), day(21, 1, actual: 2), day(22, 2)]),
        DateTime(2026, 8, 21),
      );
    });

    test('a swap BACK to the current parent is not a handoff', () {
      expect(
        nextHandoffDate(1, [day(20, 2, actual: 1), day(21, 2)]),
        DateTime(2026, 8, 21),
      );
    });

    test('no different responsible in the window → null (no handoff line)',
        () {
      expect(nextHandoffDate(1, [day(20, 1), day(21, 1)]), isNull);
      expect(nextHandoffDate(1, const <UpcomingDay>[]), isNull);
    });
  });

  group('showInviteNudge — F-31 + T-76', () {
    test('admin alone in the family, nobody invited yet, sees the nudge', () {
      expect(
          showInviteNudge(
              isLoading: false,
              isAdmin: true,
              activeMemberCount: 1,
              hasOpenInvitation: false),
          isTrue);
    });

    test('never during a load, never for non-admins, never with company', () {
      expect(
          showInviteNudge(
              isLoading: true,
              isAdmin: true,
              activeMemberCount: 1,
              hasOpenInvitation: false),
          isFalse);
      expect(
          showInviteNudge(
              isLoading: false,
              isAdmin: false,
              activeMemberCount: 1,
              hasOpenInvitation: false),
          isFalse);
      expect(
          showInviteNudge(
              isLoading: false,
              isAdmin: true,
              activeMemberCount: 2,
              hasOpenInvitation: false),
          isFalse);
    });

    test('T-76: an open invitation silences it — the admin already reached out',
        () {
      expect(
          showInviteNudge(
              isLoading: false,
              isAdmin: true,
              activeMemberCount: 1,
              hasOpenInvitation: true),
          isFalse);
    });

    test('the precondition is the same rule minus the invitation', () {
      // It exists so the calendar can decide whether to ASK: a family with a
      // second seat filled must never pay for the open-invitation read.
      expect(
          inviteNudgeApplies(
              isLoading: false, isAdmin: true, activeMemberCount: 1),
          isTrue);
      expect(
          inviteNudgeApplies(
              isLoading: false, isAdmin: true, activeMemberCount: 2),
          isFalse);
      expect(
          inviteNudgeApplies(
              isLoading: true, isAdmin: true, activeMemberCount: 1),
          isFalse);
      expect(
          inviteNudgeApplies(
              isLoading: false, isAdmin: false, activeMemberCount: 1),
          isFalse);
    });
  });

  group('isCurrentMonth — the card tap gate', () {
    final today = DateTime(2026, 8, 19);
    test('same year and month is current', () {
      expect(isCurrentMonth(DateTime(2026, 8, 1), today), isTrue);
    });
    test('another month — or the same month of another year — is not', () {
      expect(isCurrentMonth(DateTime(2026, 9, 1), today), isFalse);
      expect(isCurrentMonth(DateTime(2027, 8, 1), today), isFalse);
    });
  });
}
