/// Today-at-a-Glance rules — the "who is responsible today" projection and the
/// next-handoff scan. In the web these live INLINE in `Home.razor`
/// (lines 83–106 and `CustodyService.GetNextHandoffDateAsync`), untested;
/// extracting them into pure mirrors is the improvement the owner directive
/// allows — the rules themselves are ported verbatim.
library;

import 'calendar_rules.dart';

/// Everything the Today card renders about today's schedule, computed from
/// data the calendar already holds. Names stay raw member data; the widget
/// resolves the localized fallbacks (`K.homeNotDefined` etc.) at render time
/// so a language switch re-renders correctly.
class TodayGlance {
  /// Web: `currentDaySchedule != null` — today has a `care_schedules` row.
  final bool hasSchedule;

  /// The effective responsible's full name, or null when there is no schedule
  /// or the member is unknown (web renders `K.homeNotDefined` then).
  final String? responsibleName;

  /// The card avatar letter. Deliberately the web card's NAIVE first letter
  /// (`FullName.Substring(0,1).ToUpper()`), NOT the collision-resolving
  /// [displayInitials] the day cells use — the divergence exists in the frozen
  /// Blazor card and ports as-is.
  final String avatarLetter;

  /// Today was swapped (a real responsible set, different from the plan).
  final bool isSwapped;

  /// Raw wire handoff time (`HH:mm[:ss]`), or null. Shown independently of
  /// [isSwapped] — both badges can appear. Render via `formatTimeString`.
  final String? handoffTime;

  /// Color slot of the signed-in user (top accent) — 0 = gray/unknown.
  final int userSlot;

  /// Color slot of today's responsible (bottom accent); equals [userSlot]
  /// when there is no responsible, so the card reads as one block.
  final int responsibleSlot;

  /// Web: `isCardUnified` — both halves share one accent.
  bool get isUnified => userSlot == responsibleSlot;

  const TodayGlance({
    required this.hasSchedule,
    required this.responsibleName,
    required this.avatarLetter,
    required this.isSwapped,
    required this.handoffTime,
    required this.userSlot,
    required this.responsibleSlot,
  });
}

/// Mirror of the card projection in `Home.razor:83–106`. Pass null
/// [scheduledParentId] when today has no row.
TodayGlance todayGlance({
  required int? userProfileId,
  required int? scheduledParentId,
  required int? actualParentId,
  required String? handoffTime,
  required List<MemberView> members,
}) {
  final userSlot =
      userProfileId == null ? 0 : profileSlotIndex(userProfileId, members);
  if (scheduledParentId == null) {
    return TodayGlance(
      hasSchedule: false,
      responsibleName: null,
      avatarLetter: '?',
      isSwapped: false,
      handoffTime: null,
      userSlot: userSlot,
      responsibleSlot: userSlot,
    );
  }

  final effectiveId = actualParentId ?? scheduledParentId;
  MemberView? responsible;
  for (final m in members) {
    if (m.id == effectiveId) {
      responsible = m;
      break;
    }
  }
  final name = responsible?.fullName.trim();
  return TodayGlance(
    hasSchedule: true,
    responsibleName: (name == null || name.isEmpty) ? null : name,
    avatarLetter: (name == null || name.isEmpty)
        ? '?'
        : name.substring(0, 1).toUpperCase(),
    isSwapped: actualParentId != null && actualParentId != scheduledParentId,
    handoffTime: handoffTime,
    userSlot: userSlot,
    responsibleSlot:
        responsible == null ? userSlot : profileSlotIndex(effectiveId, members),
  );
}

/// One future `care_schedules` row, as the next-handoff scan needs it.
typedef UpcomingDay = ({
  DateTime date,
  int scheduledParentId,
  int? actualParentId,
});

/// The web's fetch window: `GetNextHandoffDateAsync` searches from tomorrow
/// through tomorrow + 90 days. The fetch lives in the app; this constant keeps
/// the two stacks' windows provably equal.
const int nextHandoffWindowDays = 90;

/// Mirror of `CustodyService.GetNextHandoffDateAsync`'s scan: the first row
/// (in the given order — feed it date-ascending, starting TOMORROW) whose
/// EFFECTIVE responsible (`actual ?? scheduled`) differs from
/// [currentParentId]. Unassigned days simply aren't rows, so gaps are skipped;
/// null = no handoff inside the window (the card shows no handoff line).
DateTime? nextHandoffDate(
    int currentParentId, Iterable<UpcomingDay> upcoming) {
  for (final day in upcoming) {
    if ((day.actualParentId ?? day.scheduledParentId) != currentParentId) {
      return day.date;
    }
  }
  return null;
}

/// F-31 mirror (`Home.razor` `ShowInviteNudge`): an admin alone in the family
/// sees the invite prompt instead of the responsible row — the app only works
/// fully when both caregivers use it. Never during a load (no flicker).
///
/// T-76 split the rule in two. This half is the PRECONDITION, and it is what
/// decides whether the calendar pays for the open-invitation read at all: a
/// family whose second seat is filled never asks the question.
bool inviteNudgeApplies({
  required bool isLoading,
  required bool isAdmin,
  required int activeMemberCount,
}) =>
    !isLoading && isAdmin && activeMemberCount == 1;

/// Whether the nudge is actually drawn (T-76, owner 18/09/2026) — the
/// refinement the F-31 record left written down and never shipped: an admin
/// whose invitation is still open has already done the thing the nudge asks
/// for, so it stays quiet until that invitation is accepted, revoked or
/// EXPIRES. Expiry brings it back on purpose: a reach-out that fizzled is a
/// family alone again, which is the state the nudge exists for.
///
/// [hasOpenInvitation] is required and not defaulted: a fact that can hide the
/// prompt has to be answered by every caller, never inherited from a default —
/// the F-56 lesson about saying WHICH null you mean.
bool showInviteNudge({
  required bool isLoading,
  required bool isAdmin,
  required int activeMemberCount,
  required bool hasOpenInvitation,
}) =>
    inviteNudgeApplies(
      isLoading: isLoading,
      isAdmin: isAdmin,
      activeMemberCount: activeMemberCount,
    ) &&
    !hasOpenInvitation;

/// Web: `IsViewingCurrentMonth` — the card is tappable ("back to today") only
/// when the visible month is NOT today's.
bool isCurrentMonth(DateTime visibleMonth, DateTime today) =>
    visibleMonth.year == today.year && visibleMonth.month == today.month;
