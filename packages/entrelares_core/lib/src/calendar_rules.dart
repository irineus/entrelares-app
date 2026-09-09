/// Client mirrors of the calendar display/transition rules — ported from
/// `entrelares-app` `Entrelares/Helpers/CalendarHelpers.cs` and
/// `Entrelares/Services/ProfileService.cs` (GetProfileSlotIndex). Where the C#
/// version reads `DateTime.Today` internally, these take `today` as a
/// parameter: pure functions, deterministic tests.
///
/// Since the U-13/U-24 port (T-53 lote 1) the display helpers take the
/// session's [Localization] — the words come from the catalog and the date
/// layout follows the reader's language.
library;

import 'localization/date_formats.dart';
import 'localization/k.dart';
import 'localization/localization.dart';

/// The minimal slice of a `care_schedules` row these rules need. The app
/// package maps its Supabase row type onto this.
class DayAssignment {
  final int scheduledParentId;
  final int? actualParentId;

  const DayAssignment({required this.scheduledParentId, this.actualParentId});

  /// T-27: the responsible that actually counts for the day.
  int get effectiveParentId => actualParentId ?? scheduledParentId;
}

/// The minimal slice of a `profiles` row these rules need.
class MemberView {
  final int id;
  final String fullName;

  /// S-11 QA: persistent color slot (1-4), DB-managed, active members only.
  final int? colorSlot;

  /// A live, present member holds a family seat (`user_id` set, `left_at` null).
  final bool isActiveMember;

  /// F-56: invited, not yet joined (`user_id` null, `left_at` null). Holds a
  /// seat and a colour, is assignable to days, but has nobody behind it to
  /// approve a swap. Never true together with [isActiveMember].
  final bool isPendingMember;

  const MemberView({
    required this.id,
    required this.fullName,
    this.colorSlot,
    this.isActiveMember = true,
    this.isPendingMember = false,
  });

  /// Still in the family: active or pending. What "assignable to a day"
  /// means — the S-11 tombstone is the only state that is neither.
  bool get isAssignable => isActiveMember || isPendingMember;
}

/// How a calendar day cell paints. Mirrors GetDayCssClass: the color follows
/// the family-member slot (F-27), never the role; `swapped` wins over slot.
sealed class DayPaint {
  const DayPaint();
}

class DayUnassigned extends DayPaint {
  const DayUnassigned();
}

class DaySwapped extends DayPaint {
  const DaySwapped();
}

class DaySlot extends DayPaint {
  /// 1-4 for active members; 0 = inactive/unknown (gray theme).
  final int slot;
  const DaySlot(this.slot);
}

/// F-27/S-11: persistent color slot of a member still IN the family; 0 for
/// anyone departed/unknown — the 4 color themes belong to the seats. F-56: a
/// pending member holds a seat, so it keeps its colour (the grey texture is
/// the departure's, not the absence of an account).
/// Mirror of ProfileService.GetProfileSlotIndex.
int profileSlotIndex(int profileId, List<MemberView> members) {
  for (final m in members) {
    if (m.id == profileId) {
      if (!m.isAssignable) return 0;
      final slot = m.colorSlot;
      return (slot != null && slot >= 1 && slot <= 4) ? slot : 0;
    }
  }
  return 0;
}

/// A day is "swapped" (trocado) when a real responsible was set and differs
/// from the planned one — single source of truth for the day-cell color and
/// the legend's Trocado badge.
bool isSwapped(DayAssignment? day) =>
    day != null && day.actualParentId != null &&
    day.actualParentId != day.scheduledParentId;

/// Mirror of GetDayCssClass.
DayPaint dayPaint(DayAssignment? day, List<MemberView> members) {
  if (day == null) return const DayUnassigned();
  if (isSwapped(day)) return const DaySwapped();
  return DaySlot(profileSlotIndex(day.scheduledParentId, members));
}

/// T-27: a day is a TRANSITION when its effective responsible differs from the
/// previous day's — and a handoff time only makes sense there. No previous day
/// = custody starts here = transition. Since T-45 the database enforces the
/// same rule on every write path; this client mirror drives the editor's hint,
/// so the two must keep saying the same thing.
bool isTransitionDay(int? previousEffectiveParentId, int? effectiveParentId) =>
    previousEffectiveParentId == null ||
    previousEffectiveParentId != effectiveParentId;

/// Mirror of GetParentInitial: the active parent's display initials for the
/// day-cell avatar ("•" for unassigned days).
String parentInitial(DayAssignment? day, List<MemberView> members) {
  if (day == null) return '•';
  return displayInitials(day.effectiveParentId, members);
}

/// F-28 QA (accessibility): with up to 4 caregivers, the INITIAL — not the
/// color — must identify who has the day. Three tiers, computed per family:
///   1. first letter of the first name (the common case);
///   2. on collision, first-name + surname initials ("MS", "MO");
///   3. identical names: append the member's slot index — the same 1..4 order
///      the calendar legend lists, so the digit is learnable.
String displayInitials(int profileId, List<MemberView> members) {
  MemberView? me;
  for (final m in members) {
    if (m.id == profileId) {
      me = m;
      break;
    }
  }
  if (me == null) return '?';

  final one = _oneLetter(me);
  if (members.where((p) => _oneLetter(p) == one).length <= 1) return one;

  final two = _twoLetters(me);
  if (members.where((p) => _twoLetters(p) == two).length <= 1) return two;

  final sorted = [...members]..sort((a, b) => a.id.compareTo(b.id));
  final slot = sorted.indexWhere((p) => p.id == profileId) + 1;
  return '$two$slot';
}

String _oneLetter(MemberView p) {
  final name = p.fullName.trim();
  return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

String _twoLetters(MemberView p) {
  final parts =
      p.fullName.split(' ').where((s) => s.isNotEmpty).toList(growable: false);
  return parts.length > 1
      ? (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase()
      : _oneLetter(p);
}

/// Human-readable relative day in the reader's language. Mirror of
/// GetDaysUntil — with `today` passed in (T-07: date-only semantics,
/// deterministic tests).
/// T-08 finding preserved: past dates must never render "em -3 dias".
String daysUntilLabel(DateTime date, DateTime today, Localization l) {
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  final days = d.difference(t).inDays;
  if (days < -1) return l.format(K.relDaysAgo, [-days]);
  if (days == -1) return l[K.relYesterday];
  if (days == 0) return l[K.relToday];
  if (days == 1) return l[K.relTomorrow];
  return l.format(K.relInDays, [days]);
}

/// Mirror of FormatHandoffDate: abbreviated weekday + short date
/// ("sex, 04/07" · "Fri, 04 Jul").
///
/// U-24 note: the web helper still renders `dd/MM` in English — a residue the
/// 37-call-site migration missed (`CalendarHelpers.cs:45`, frozen with the
/// Blazor app). The U-24 rule ("an English reader must never see 05/08") is
/// what ports, not the residue, so the numeric half follows the language here.
String formatHandoffDate(DateTime date, Localization l) =>
    '${l.weekdayAbbrev(date.weekday)}, ${l.formatDateShort(date)}';

/// Mirror of GetHandoffUrgencyClass, as data instead of a CSS class name.
enum HandoffUrgency { urgent, soon, near, none }

HandoffUrgency handoffUrgency(DateTime date, DateTime today) {
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  return switch (d.difference(t).inDays) {
    0 => HandoffUrgency.urgent,
    1 => HandoffUrgency.soon,
    2 => HandoffUrgency.near,
    _ => HandoffUrgency.none,
  };
}
