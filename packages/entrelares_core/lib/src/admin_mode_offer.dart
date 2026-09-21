/// F-67 Part B — the admin mode offered where it is needed.
///
/// Field evidence (family 19, 19/09/2026): an admin on Premium, inside the
/// F-40 window, needed to correct the day before and never found the mode —
/// an unlabelled shield in the calendar bar and a row inside Família. So when
/// an ADMIN reaches for something only the mode allows, the app asks
/// *"Ativar agora?"* at that spot and, on yes, switches the mode on and
/// carries the action through.
///
/// This decides WHETHER to ask. It never relaxes a guard by itself: the mode
/// stays an explicit act (a confirmation, never a silent switch), a member who
/// is not an admin never sees the question, and the database stays the
/// enforcement (`enforce_day_protection` reads `profiles.is_admin` and the F-40
/// window — the mode does not exist on the server at all).
library;

import 'date_math.dart';
import 'day_protection_rules.dart';
import 'localization/k_app.dart';

/// Every place the client hides or refuses something because the mode is off
/// while the member IS an admin. Closed on purpose: it is also the `action`
/// property of the `admin-mode-offer` analytics event.
///
/// Not in the list, and why: a FROZEN day opens the frozen panel for everyone,
/// admins in the mode included (web parity), so no editor is ever refused
/// there; and changing the REAL carer outside the workflow is not refused —
/// with the mode off it opens a swap request, which is the right door.
enum AdminModeAction {
  /// The day sheet of a past day: "Corrigir o planejamento".
  editPastDay('edit-past-day'),

  /// The day sheet's "Limpar dia" on an assigned day.
  clearDay('clear-day'),

  /// The planned parent of an already assigned day (S-09 lock).
  changePlannedParent('change-planned-parent'),

  /// The bulk sheet's "Limpar dias".
  bulkClearDays('bulk-clear-days'),

  /// The bulk sheet: past days it would skip, or the planned parent it would
  /// keep on assigned days.
  bulkOverwrite('bulk-overwrite'),

  /// The wizard's "Substituir os dias já planejados" (F-51).
  wizardReplace('wizard-replace'),

  /// The calendar menu's "Limpar mês" (F-51).
  clearMonth('clear-month');

  const AdminModeAction(this.wireName);

  /// The analytics value — kebab-case, like every other event property.
  final String wireName;
}

/// What the client does when an admin reaches for [AdminModeAction].
enum AdminModeOfferKind {
  /// Nothing to offer: not an admin, or the mode is already on. The screen
  /// stays exactly as it is today.
  none,

  /// Ask *"Ativar agora?"* — activating would unlock this action.
  offer,

  /// The mode would not help on this tier, but Premium would: the U-49 gate
  /// banner with its CTA to `/family/plan`, never the question.
  gate,

  /// Beyond what any tier reaches: the F-40 limit sentence, no question.
  outOfWindow,
}

/// Decides the offer for [action].
///
/// [dates] are the PAST days the action would touch; an action with none
/// (a future day, a month cleared from today on) is not bound by the F-40
/// window — free admins keep the frozen-day, planned-parent and clear powers.
/// With several past dates the answer is the most useful one any of them
/// gives: one date the mode unlocks is reason enough to ask.
///
/// [isPremium] null means the entitlement read failed: the client does not
/// guess a limit it cannot see, so it offers and lets the trigger answer —
/// the same fail-open posture the F-40 banner already takes.
AdminModeOfferKind adminModeOfferFor({
  required AdminModeAction action,
  required bool isAdmin,
  required bool adminModeActive,
  required DateTime today,
  required bool? isPremium,
  required int overrideFreeDays,
  required int overridePremiumMonths,
  Iterable<DateTime> dates = const [],
}) {
  if (!isAdmin || adminModeActive) return AdminModeOfferKind.none;
  final past = [
    for (final d in dates)
      if (isDayInPast(d, today)) dateOnly(d),
  ];
  if (past.isEmpty || isPremium == null) return AdminModeOfferKind.offer;

  bool reaches(DateTime date, {required bool premium}) =>
      isWithinAdminRetroactiveReach(
        date: date,
        today: today,
        isPremium: premium,
        overrideFreeDays: overrideFreeDays,
        overridePremiumMonths: overridePremiumMonths,
      );

  if (past.any((d) => reaches(d, premium: isPremium))) {
    return AdminModeOfferKind.offer;
  }
  if (!isPremium && past.any((d) => reaches(d, premium: true))) {
    return AdminModeOfferKind.gate;
  }
  return AdminModeOfferKind.outOfWindow;
}

/// The sentence that names [action] in the question. One per action, so the
/// question always says WHAT the mode is being turned on for.
String adminModeOfferMessageKey(AdminModeAction action) => switch (action) {
      AdminModeAction.editPastDay => KApp.adminOfferEditPastDay,
      AdminModeAction.clearDay => KApp.adminOfferClearDay,
      AdminModeAction.changePlannedParent => KApp.adminOfferChangePlanned,
      AdminModeAction.bulkClearDays => KApp.adminOfferBulkClear,
      AdminModeAction.bulkOverwrite => KApp.adminOfferBulkOverwrite,
      AdminModeAction.wizardReplace => KApp.adminOfferWizardReplace,
      AdminModeAction.clearMonth => KApp.adminOfferClearMonth,
    };
