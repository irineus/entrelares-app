/// F-73 — when the Android app asks Google Play for its review sheet
/// (In-App Review API).
///
/// The moment (owner, 28/09/2026): the first time the swap's REQUESTER SEES
/// the other side's approval — the `swap_approved` notification addressed to
/// them, on the Notificações list, with the app open. Never after a failure,
/// never mid-task. Auto-approval (`auto_approved`) is NOT the other side
/// approving, a revert is not a success, and the receipts and the family
/// fan-out are someone else's moment.
///
/// The floors are `app_settings` keys (`review_prompt.*`, T-80): the switch,
/// the account's minimum age and the interval between two requests on the
/// same device. On top of them Play applies its own quota, decides whether a
/// sheet appears at all and never says whether anyone reviewed — so nothing
/// here can measure "reviewed"; the only reading is the Play Console's
/// ratings over time. No question precedes the request: Play forbids
/// filtering who is asked.
abstract final class ReviewPromptRules {
  /// The one notification type that is "the other side approved my swap".
  static const String triggerType = 'swap_approved';

  /// Whether a notification row is the moment: an unread `swap_approved`
  /// addressed to the reader (the requester — the writer sends it to them).
  static bool isTrigger(
          {required String type,
          required bool addressedToMe,
          required bool isRead}) =>
      type == triggerType && addressedToMe && !isRead;

  /// Only the PRODUCTION store build calls the API: never the web, never a
  /// dev build (it would ask against the production listing), never iOS
  /// (T-40), never a debug run of the prod flavour.
  static bool isStoreBuild({
    required bool isWeb,
    required bool isAndroid,
    required bool isProduction,
    required bool isRelease,
  }) =>
      !isWeb && isAndroid && isProduction && isRelease;

  /// Every floor, in the order the card lists them.
  static bool shouldRequest({
    required bool enabled,
    required bool isStoreBuild,
    required bool isViewer,
    required bool offline,
    required DateTime? accountCreatedAt,
    required DateTime? lastRequestedAt,
    required DateTime now,
    required int minAccountDays,
    required int intervalDays,
  }) {
    if (!enabled || !isStoreBuild) return false;
    // F-50: a viewer takes no part in swaps and has little to rate.
    if (isViewer) return false;
    // T-18: offline is a state; the request needs Play, and the moment is
    // not "a success" if the screen is showing an old copy.
    if (offline) return false;
    // No known account age means no floor can be proven — fail closed.
    if (accountCreatedAt == null) return false;
    if (now.difference(accountCreatedAt) < Duration(days: minAccountDays)) {
      return false;
    }
    final last = lastRequestedAt;
    if (last != null && now.difference(last) < Duration(days: intervalDays)) {
      return false;
    }
    return true;
  }
}
