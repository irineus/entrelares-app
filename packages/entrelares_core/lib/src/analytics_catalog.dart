/// T-78 — the closed catalogue of product events the app may send to Umami,
/// and the ONLY prop keys each one may carry.
///
/// Two failures this file exists to make loud:
///   · a renamed event silently ends one series and starts another (the U-35
///     cliff): the names below are pinned by `analytics_catalog_test`, and
///     `analytics_call_sites_test` (app) refuses a call site that spells a name
///     as a literal instead of naming a constant here;
///   · a prop that carries free text is a PII leak (T-37): `AnalyticsCatalog.
///     filterProps` drops any key the event did not declare and any value that
///     is not a short token — a sentence, an e-mail or a name cannot pass,
///     because they contain characters a token never does.
///
/// Every entry says WHEN it started counting, because a zero in a dashboard is
/// only "nothing since the instrument existed" (L-25). The dates are of the
/// Flutter client, from `git log -S`; the T-37 names were also sent by the
/// Blazor client before the 23/08/2026 cutover (Umami's first event 02/08/2026).
/// Names keep the spelling of their own time — snake_case for the T-37
/// originals, kebab-case since — because renaming is the defect.
library;

abstract final class AnalyticsEvents {
  // ── Acquisition and onboarding (T-37, 19/08/2026 unless noted) ───────────
  static const signupStarted = 'signup_started'; // type
  static const signupStep = 'signup_step'; // step — since U-44, 16/09/2026
  static const familyCreated = 'family_created';
  static const inviteeJoined = 'invitee_joined';
  static const inviteSent = 'invite_sent'; // email = none/sent/link_only
  static const inviteNudgeShown = 'invite_nudge_shown'; // once — T-76, 18/09/2026
  static const inviteNudgeClick = 'invite_nudge_click'; // T-76, 18/09/2026

  // ── Planning and the swap workflow ──────────────────────────────────────
  static const wizardStarted = 'wizard-started'; // T-78, 23/09/2026
  static const wizardCompleted = 'wizard_completed'; // handoff since U-55, 22/09/2026
  static const swapRequested = 'swap_requested'; // scenario
  static const swapAnswered = 'swap-answered'; // T-78: action × kind
  static const dayNoteSaved = 'day-note-saved'; // T-78
  static const daySheetClosed = 'day-sheet-closed'; // U-56, 23/09/2026: mode × outcome
  static const dayNoticeSent = 'day-notice-sent'; // T-78 (F-52 enums)
  static const dayNoticeAnswered = 'day-notice-answered'; // T-78
  static const dayAccountSaved = 'day-account-saved'; // T-78 (F-67)
  static const adminModeOffer = 'admin-mode-offer'; // F-67, 21/09/2026
  static const adminModeToggle = 'admin-mode-toggle'; // T-78
  static const pdfExport = 'pdf-export'; // T-78

  // ── Presence, notifications and preferences ─────────────────────────────
  static const appOpen = 'app-open'; // once per session — T-78
  static const signIn = 'sign-in'; // T-78
  static const notificationOpen = 'notification-open'; // T-78
  static const pushNudgeView = 'push-nudge-view'; // once — U-54, 21/09/2026
  static const pushNudgeClick = 'push-nudge-click'; // U-54, 21/09/2026
  static const pushEnableResult = 'push-enable-result'; // U-54, 21/09/2026
  static const installHintView = 'install-hint-view'; // U-51, 15/09/2026
  static const installHintOpen = 'install-hint-open'; // U-51, 15/09/2026
  static const installHintDismiss = 'install-hint-dismiss'; // U-51, 15/09/2026
  static const preferenceChanged = 'preference-changed'; // T-78
  static const supportContactSent = 'support-contact-sent'; // T-78 (F-68)

  // ── Monetization (T-37/F-48, 19/08/2026; paywall-view moved with U-35) ──
  static const premiumGateClick = 'premium-gate-click';
  static const premiumPaywallView = 'premium-paywall-view';
  static const premiumInterest = 'premium-interest';
  static const premiumCheckoutStart = 'premium-checkout-start';
  static const premiumCheckoutReturn = 'premium-checkout-return';
  static const premiumCheckoutOutcome = 'premium-checkout-outcome';
  static const premiumCancel = 'premium-cancel';
  static const premiumReactivate = 'premium-reactivate';
}

abstract final class AnalyticsCatalog {
  static const _funnel = {'channel', 'cycle', 'mode', 'outcome'};

  /// Event name → the prop keys it may carry. An event absent from this map
  /// may not be sent; a key absent from its set is dropped before sending.
  static const Map<String, Set<String>> props = {
    AnalyticsEvents.signupStarted: {'type'},
    AnalyticsEvents.signupStep: {'step'},
    AnalyticsEvents.familyCreated: {},
    AnalyticsEvents.inviteeJoined: {},
    AnalyticsEvents.inviteSent: {'email'},
    AnalyticsEvents.inviteNudgeShown: {'channel'},
    AnalyticsEvents.inviteNudgeClick: {'channel'},
    AnalyticsEvents.wizardStarted: {},
    AnalyticsEvents.wizardCompleted: {'created', 'replaced', 'handoff'},
    AnalyticsEvents.swapRequested: {'scenario'},
    AnalyticsEvents.swapAnswered: {'action', 'kind'},
    AnalyticsEvents.dayNoteSaved: {'state'},
    AnalyticsEvents.daySheetClosed: {'mode', 'outcome'},
    AnalyticsEvents.dayNoticeSent: {'reason', 'request', 'eta'},
    AnalyticsEvents.dayNoticeAnswered: {'outcome'},
    AnalyticsEvents.dayAccountSaved: {'correction'},
    AnalyticsEvents.adminModeOffer: {'action', 'result'},
    AnalyticsEvents.adminModeToggle: {'state'},
    AnalyticsEvents.pdfExport: {'period'},
    AnalyticsEvents.appOpen: {'channel', 'display'},
    AnalyticsEvents.signIn: {'method'},
    AnalyticsEvents.notificationOpen: {'source', 'type'},
    AnalyticsEvents.pushNudgeView: {'channel', 'platform', 'step'},
    AnalyticsEvents.pushNudgeClick: {'channel', 'platform', 'step'},
    AnalyticsEvents.pushEnableResult: {'channel', 'platform', 'outcome'},
    AnalyticsEvents.installHintView: {},
    AnalyticsEvents.installHintOpen: {},
    AnalyticsEvents.installHintDismiss: {},
    AnalyticsEvents.preferenceChanged: {'pref', 'value'},
    AnalyticsEvents.supportContactSent: {'category', 'signed_in'},
    AnalyticsEvents.premiumGateClick: {'gate'},
    AnalyticsEvents.premiumPaywallView: {'channel'},
    AnalyticsEvents.premiumInterest: {'source', 'trial'},
    AnalyticsEvents.premiumCheckoutStart: _funnel,
    AnalyticsEvents.premiumCheckoutReturn: _funnel,
    AnalyticsEvents.premiumCheckoutOutcome: _funnel,
    AnalyticsEvents.premiumCancel: _funnel,
    AnalyticsEvents.premiumReactivate: _funnel,
  };

  /// Every name the app may send.
  static Set<String> get names => props.keys.toSet();

  static bool isKnown(String name) => props.containsKey(name);

  /// A prop value is a TOKEN: an enum wire value, a bucket, a flag. Letters,
  /// digits, `_`, `-` and the `?` the billing funnel uses for an unknown
  /// cycle, at most 32 characters. No space, `@`, `.` or `/` can pass — so no
  /// sentence, e-mail, URL or full name can either.
  static final _token = RegExp(r'^[A-Za-z0-9_\-?]{1,32}$');

  /// [raw] reduced to what [name] declared, with every value a bool, a finite
  /// number or a token. Null when nothing survives (Umami then gets no `data`).
  static Map<String, Object>? filterProps(String name, Map<String, Object>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final allowed = props[name];
    if (allowed == null) return null;
    final out = <String, Object>{};
    raw.forEach((key, value) {
      if (!allowed.contains(key)) return;
      if (value is bool || (value is num && value.isFinite)) {
        out[key] = value;
      } else if (value is String && _token.hasMatch(value)) {
        out[key] = value;
      }
    });
    return out.isEmpty ? null : out;
  }

  /// The notification types `notification-open` may name; anything else is
  /// reported as `other`. The ten F-09 push types, the F-52 aviso, the F-70
  /// plan end (from 23/09/2026 — its opens are that item's success measure),
  /// and the three things a row in *Para você* opens.
  static const notificationTypes = {
    'plan_ending',
    'auto_reminder',
    'auto_approved',
    'swap_requested',
    'swap_approved',
    'swap_rejected',
    'swap_cancelled',
    'revert_requested',
    'revert_approved',
    'revert_rejected',
    'revert_cancelled',
    'day_notice',
    'swap_request',
    'revert_request',
  };

  static String notificationType(String? type) =>
      notificationTypes.contains(type) ? type! : 'other';
}
