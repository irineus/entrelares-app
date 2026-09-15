/// F-65 — the quick swap from a selected pair of days (Closed Alpha
/// suggestion, 15/09/2026). While days are being selected on the calendar,
/// a selection made of exactly TWO planned parents with the SAME number of
/// days each can be inverted in one gesture: every day of A is proposed to B
/// and every day of B to A.
///
/// It is the swap WORKFLOW, not a shortcut around it: the plan this file
/// produces is a list of swap requests, one per day, all addressed to the
/// same approver — the other planned parent. Nothing here writes
/// `actual_parent_id`; the database's `enforce_day_protection` would refuse
/// it anyway. The requests are independent (the approver may accept one and
/// refuse another), exactly as if the requester had opened them one by one.
///
/// The rule is all-or-nothing (owner, 15/09/2026): the button appears only
/// when EVERY selected day qualifies. An ineligible day hides it with no
/// explanation, the same treatment the three-parent case gets — a partial
/// plan would break the pairing the user is looking at.
library;

import 'calendar_rules.dart' show MemberView;
import 'date_math.dart';
import 'day_protection_rules.dart';

/// One selected day as the quick-swap rule reads it. `scheduledParentId == 0`
/// is the "unassigned" sentinel (no row, or a row with no planned parent).
class QuickSwapDay {
  final DateTime date;
  final int scheduledParentId;
  final int? actualParentId;

  const QuickSwapDay({
    required this.date,
    required this.scheduledParentId,
    this.actualParentId,
  });
}

/// One swap request the quick swap will open: [date] planned for the parent
/// who gives it, [proposedActualParentId] the one who takes it.
typedef QuickSwapRequest = ({DateTime date, int proposedActualParentId});

/// What confirming the quick swap does. [requesterDays] are the days planned
/// for the requester (they go to [counterpartId], scenario A of F-28);
/// [counterpartDays] are the days planned for the counterpart (the requester
/// takes them, scenario B). Both lists are date-sorted so the confirmation
/// reads in calendar order and the requests open in the same order.
class QuickSwapPlan {
  final int requesterId;
  final int counterpartId;
  final List<DateTime> requesterDays;
  final List<DateTime> counterpartDays;

  const QuickSwapPlan({
    required this.requesterId,
    required this.counterpartId,
    required this.requesterDays,
    required this.counterpartDays,
  });

  /// Every request the plan opens, in calendar order.
  List<QuickSwapRequest> get requests {
    final all = [
      for (final d in requesterDays)
        (date: d, proposedActualParentId: counterpartId),
      for (final d in counterpartDays)
        (date: d, proposedActualParentId: requesterId),
    ];
    all.sort((a, b) => a.date.compareTo(b.date));
    return all;
  }

  /// The number of days — and of requests — the swap covers. Always even.
  int get dayCount => requesterDays.length + counterpartDays.length;
}

/// The quick-swap plan for [selected], or null when the selection does not
/// qualify and the button must be absent. Every clause is a reason the
/// workflow would refuse or the pairing would not hold:
///
/// - every day has a planned parent, is today or later (F-13), is not frozen
///   by a pending request (F-12) and carries no approved swap — a swapped day
///   already answers "who has the child", so inverting it is a different
///   question (a revert), not this one;
/// - exactly two planned parents, with the same number of days each — the
///   "pair" the user is composing (1+1, 2+2, 3+3 …; 2+1 is not a pair yet);
/// - the requester is one of the two (F-28: a third caregiver, admin or not,
///   may not propose a swap between two other people — `createSwapRequest`
///   throws on it, so the button never offers it);
/// - both parents are ACTIVE members: a pending member (F-56) has nobody to
///   approve with and a departed one (S-11) is frozen; the database refuses
///   either as a counterpart (`enforce_swap_counterpart`).
QuickSwapPlan? quickSwapPlan({
  required Iterable<QuickSwapDay> selected,
  required int? requesterId,
  required DateTime today,
  required Iterable<DateTime> frozenDates,
  required List<MemberView> members,
}) {
  if (requesterId == null) return null;
  final days = selected.toList(growable: false);
  if (days.isEmpty) return null;

  final byParent = <int, List<DateTime>>{};
  for (final day in days) {
    if (day.scheduledParentId == 0) return null;
    if (isDayInPast(day.date, today)) return null;
    if (isDayFrozen(day.date, frozenDates)) return null;
    final actual = day.actualParentId;
    if (actual != null && actual != day.scheduledParentId) return null;
    byParent.putIfAbsent(day.scheduledParentId, () => []).add(dateOnly(day.date));
  }

  if (byParent.length != 2) return null;
  final ids = byParent.keys.toList(growable: false);
  if (byParent[ids[0]]!.length != byParent[ids[1]]!.length) return null;
  if (!ids.contains(requesterId)) return null;

  final counterpartId = ids[0] == requesterId ? ids[1] : ids[0];
  for (final id in ids) {
    final member = members.where((m) => m.id == id).firstOrNull;
    if (member == null || !member.isActiveMember) return null;
  }

  final mine = byParent[requesterId]!..sort();
  final theirs = byParent[counterpartId]!..sort();
  return QuickSwapPlan(
    requesterId: requesterId,
    counterpartId: counterpartId,
    requesterDays: List.unmodifiable(mine),
    counterpartDays: List.unmodifiable(theirs),
  );
}
