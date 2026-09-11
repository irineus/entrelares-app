import 'package:entrelares_core/entrelares_core.dart'
    show AppLanguage, PreEditNotes, SwapOrigin, auditPageSize;

import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/activity_log.dart';
import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/family_deletion.dart';
import 'package:entrelares_db_contracts/models/family_invitation.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';

/// What the calendar slice needs from the backend — an interface so widget
/// tests run against a fake while the real implementation talks to Supabase.
abstract class CustodyDataSource {
  Future<List<Member>> fetchMembers();

  /// The signed-in user's OWN profile row, or null when none exists. Read at
  /// gate time for the U-13 language adoption/detection sync — before the
  /// calendar loads, not inside it.
  Future<Member?> fetchOwnProfile();

  /// U-13: persists the user's explicit language CHOICE. Best-effort at the
  /// call site — the client's language does not depend on the server write.
  Future<void> updateOwnLanguage(int profileId, String languageCode);

  /// U-13: records what this session renders in (`language_detected`), so a
  /// sender with no browser can match the screen. Best-effort, every boot
  /// where it disagrees.
  Future<void> updateDetectedLanguage(int profileId, String languageCode);

  /// All rows of [year]/[month]. RLS scopes the family server-side.
  Future<List<CareSchedule>> fetchMonth(int year, int month);

  /// Rows from [from] (inclusive) through [from] + [days], date-ascending —
  /// the Today card's row + next-handoff scan window (mirror of the web's
  /// `GetNextHandoffDateAsync` fetch; the scan itself is pure, in core).
  Future<List<CareSchedule>> fetchUpcoming(DateTime from, int days);

  /// F-32: the signed-in user's family row (RLS yields at most one), or null.
  /// The entitlement mirror fails CLOSED on null by construction.
  Future<Family?> fetchOwnFamily();

  /// T-41: the PUBLIC `app_settings` rows as key→value (RLS exposes only the
  /// public ones). Callers cache load-once and fall back to the seeded
  /// defaults on failure, as the web does.
  Future<Map<String, String>> fetchPublicSettings();

  /// T-39: the family's subscription row (RLS scopes the read), or null when
  /// the family never started a checkout. Bookkeeping only — entitlement stays
  /// on `families.plan` (F-32). Mirror of `BillingService.GetSubscriptionAsync`
  /// including its fail-closed contract: a failed read reaches the caller as
  /// null, i.e. "no subscription", never as premium.
  Future<Subscription?> fetchSubscription();

  /// F-43: the family's sanitized billing timeline, newest first. The RPC is
  /// admin-only and the DATABASE enforces it — a non-admin simply never gets
  /// the panel offered.
  Future<List<BillingHistoryEntry>> fetchBillingHistory();

  /// F-32: whether this family already registered interest in Premium (the
  /// waitlist row exists). RLS scopes the read to the caller's family.
  Future<bool> hasRegisteredPremiumInterest();

  /// F-32: records this family's interest in Premium through the SECURITY
  /// DEFINER RPC. Idempotent per family — re-registering just refreshes the
  /// row. [feature] is a coarse tag for which previewed feature drew them
  /// (optional, no PII).
  Future<void> registerPremiumInterest({String? feature});

  /// T-39: starts the hosted checkout for [cycle] (`monthly`/`annual`) and
  /// returns the gateway's payment URL to open. The call is NOT retried by
  /// construction — a retry would create a second payment link.
  Future<String> startCheckout(String cycle);

  /// F-48: starts the Pix AVULSO checkout — one single, non-recurring charge
  /// for [cycle]'s period (no card on file, no auto-renew). Same contract and
  /// the same no-retry rule as [startCheckout].
  Future<String> startAvulso(String cycle);

  /// T-48: hands a Play purchase token to the server, which verifies it with
  /// the Play Developer API and applies the effect through the SAME
  /// `set_family_plan` + `billing_events` the Asaas webhook uses (idempotent
  /// by purchase token). The client never grants anything on its own — this
  /// call is the whole entitlement path for the store rail.
  Future<void> verifyStorePurchase({
    required String productId,
    required String purchaseToken,
  });

  /// T-39: cancels the subscription. No further charges; paid time is honored
  /// SERVER-side — the client never computes what the family keeps. Throws
  /// [BillingRefused] carrying the function's own text when it refuses.
  Future<void> cancelSubscription();

  /// F-42: comes back with NO charge today — the server recreates the gateway
  /// subscription with the first invoice due at the end of the already-paid
  /// period. The refusals are user-facing text (e.g. the card guidance), so
  /// they travel verbatim in [BillingRefused].
  Future<void> reactivateSubscription();

  /// One day's row, or null when unassigned — mirror of the web's
  /// `GetScheduleForDateAsync` (the T-27 transition check on the 1st of the
  /// month needs the previous month's last day).
  Future<CareSchedule?> fetchDay(DateTime date);

  Future<void> insertDay(CareSchedule day);

  /// Full-row update carrying the T-33/T-35 echo (see CareSchedule).
  Future<void> updateDay(CareSchedule day);

  /// Clears an assigned day. Admin-only by DB rule (QA July 2026 — the UI
  /// mirrors with [isClearDayBlocked]); the trigger enforces regardless.
  Future<void> deleteDay(int id);

  /// The wizard's write path — mirror of `CustodyService.BulkUpsertAsync`:
  /// inserts only NEW future days (past and already-assigned days are
  /// skipped, never overwritten) and returns how many were created; the
  /// caller derives the "kept" count. [onProgress] reports 0–100.
  Future<int> bulkInsertNewDays(List<CareSchedule> days,
      {void Function(int percent)? onProgress});

  /// Starts listening for care_schedules changes; [onChange] fires on any
  /// insert/update/delete visible to this session. [onStatus] reports socket
  /// health (true = subscribed) — the F-23 safety poll adapts its cadence to
  /// it (owner decision 19/08/2026: the poll survives until the socket proves
  /// itself under real load). Returns a dispose callback.
  Future<void Function()> watchChanges(void Function() onChange,
      {void Function(bool connected)? onStatus});

  // ── Lote 3: swap-approval workflow (mirror of SwapRequestService.cs) ──────
  // No RPCs: the whole workflow is PostgREST CRUD plus one best-effort Edge
  // Function invoke. The mutations also write the workflow's in-app
  // notifications (composed in core, byte-identical to the web's stored
  // PT-BR sentences) — the DB stays the enforcement throughout.

  /// The month's OPEN requests (`pending`/`revert_pending`) — the F-12 frozen
  /// source. Months entirely in the past return empty without a round-trip.
  Future<List<SwapRequest>> fetchFrozenRequestsForMonth(int year, int month);

  /// Open requests awaiting MY response — the nav badge count and the
  /// "Para você" tab (⚠️ the bell badge counts THESE, not unread rows).
  Future<List<SwapRequest>> fetchPendingForMe(int myProfileId);

  /// Requests I sent, any status, newest 100 — the "Enviadas" tab is a
  /// recent-activity view, not an unbounded archive.
  Future<List<SwapRequest>> fetchSentRequests(int myProfileId);

  /// Opens a swap request for [schedule] (already upserted by the caller with
  /// scheduled parent + notes only). Enforces the F-28 scenario-C gate,
  /// snapshots the pre-edit log reference (F-26), inserts the request and the
  /// two notifications, then fires the best-effort e-mail.
  Future<void> createSwapRequest({
    required CareSchedule schedule,
    required int proposedActualParentId,
    String? proposedHandoffTime,
    String? requestMessage,
    required Member myProfile,
    required List<Member> allProfiles,
  });

  /// Applies the proposed change to the day (full-row T-33/T-35 echo), marks
  /// the request approved and notifies requester + self + uninvolved (F-28).
  Future<void> approveSwap(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles});

  Future<void> rejectSwap(int swapRequestId,
      {String? reason, required List<Member> allProfiles});

  Future<void> cancelSwap(int swapRequestId,
      {required List<Member> allProfiles});

  /// Opens a revert request for an approved swap. [restoreNotes] is the F-47
  /// answer — it travels WITH the request because the restore runs later and
  /// on the other side (approver's client or the 48h auto-approval).
  Future<void> requestRevert({
    required DateTime scheduleDate,
    required int currentActualProfileId,
    required int scheduledParentId,
    String? requestMessage,
    bool restoreNotes = false,
    required Member myProfile,
    required List<Member> allProfiles,
  });

  /// Restores the day to its pre-edit snapshot (F-26 plan computed in core),
  /// marks the request revert_approved and notifies.
  Future<void> approveRevert(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles});

  Future<void> rejectRevert(int swapRequestId,
      {String? reason, required List<Member> allProfiles});

  Future<void> cancelRevert(int swapRequestId,
      {required List<Member> allProfiles});

  /// F-47: the day's observation as the pre-edit snapshot holds it, or null
  /// when there is nothing to restore FROM (no approved swap on the date, no
  /// snapshot reference, or an old_data-less snapshot).
  Future<PreEditNotes?> fetchPreEditNotes(DateTime scheduleDate);

  /// My notifications, newest 100 — the "Histórico" tab.
  Future<List<AppNotification>> fetchNotifications(int myProfileId);

  /// Opening the Notifications page marks EVERYTHING read (web parity) — one
  /// bulk PATCH on my unread rows.
  Future<void> markAllNotificationsRead(int myProfileId);

  /// F-09: registers this device's FCM token for [myProfileId], or refreshes
  /// the `last_seen_at` of a token already registered.
  ///
  /// Upsert on the TOKEN, not on the pair: FCM rotates a token on its own
  /// schedule and hands the same one to whoever signs in next on that device.
  /// Re-pointing the existing row is what stops the previous account's notices
  /// from continuing to arrive on a phone that changed hands.
  Future<void> registerPushToken({
    required int myProfileId,
    required String token,
    required String platform,
    String? deviceLabel,
  });

  /// F-09: drops this device's registration — pressed on sign-out, and when
  /// the person turns push off.
  Future<void> deletePushToken(String token);

  /// F-09: whether THIS DEVICE — the one holding [token] — is registered for
  /// [myProfileId]. Read rather than a stored flag: the permission can be
  /// revoked in the OS, and a flag would keep claiming push was on.
  ///
  /// **Keyed on the token, not on the profile alone**, and the difference is a
  /// silent break. "Does this profile have any device?" answers yes on a
  /// SECOND phone that has never registered, so the control reads `on` while
  /// nothing was ever sent to that device — and the silent repair in
  /// [PushService.start] never runs, because it believes the work is done.
  Future<bool> isDeviceRegistered({
    required int myProfileId,
    required String token,
  });

  /// Listens for swap_requests + notifications changes — the lote-3 twin of
  /// [watchChanges] (frozen paint, badge, page refresh). Safe to call from
  /// more than one subscriber. Returns a dispose callback.
  Future<void Function()> watchWorkflowChanges(void Function() onChange,
      {void Function(bool connected)? onStatus});

  // ── Lote 4: sudo elevation (S-10) ─────────────────────────────────────────

  /// Exchanges the current password for the server's elevation window. Returns
  /// the `elevated_until` ISO instant the `elevate` Edge Function reports, or
  /// null when the response omits it (the caller falls back to the local
  /// 5-minute estimate).
  ///
  /// Throws [ElevationRefused] when the function answers with an error — the
  /// caller distinguishes a wrong password (which feeds the local throttle)
  /// from anything else. The identity always comes from the JWT: the password
  /// is proof, never a claim about WHO is elevating.
  Future<String?> elevate(String password);

  /// S-21 — asks the server to mail a one-time code to the account's address.
  ///
  /// Grants nothing by itself. Returns how many minutes the code lasts, so the
  /// prompt can say so without repeating the number; throws [ElevationRefused]
  /// with [ElevationRefused.rateLimited] when a code was already sent recently,
  /// in which case the message says the OLD one is still good.
  Future<int> requestElevationCode();

  /// S-21 — redeems a code. Same return and the same window as [elevate]:
  /// `is_elevated()` cannot tell which proof was given, by design.
  ///
  /// Throws [ElevationRefused] with [ElevationRefused.wrongCode] when the
  /// server refused it. That flag exists so a refused CODE never feeds the
  /// password throttle — the server already destroys a code after three wrong
  /// guesses, and a local cooldown on top would lock someone out of a code they
  /// are still holding.
  Future<String?> elevateWithCode(String code);

  // ── Lote 4: sign-up and invitations ───────────────────────────────────────

  /// Resolves an invitation token for an anonymous visitor, or null when the
  /// invitation is not usable. Unknown, accepted, revoked and expired tokens
  /// are all null — the RPC does not distinguish them, and neither may the UI.
  Future<InviteInfo?> fetchInviteInfo(String token);

  /// The FOUNDER branch. GoTrue creates the auth user carrying the metadata
  /// `handle_new_user` reads; the trigger is what creates family + profile
  /// atomically, so nothing here is a two-step the client could half-finish.
  ///
  /// Throws [SignUpFailure] with the catalog key to show — including for the
  /// anti-enumeration "silent duplicate" shape.
  Future<void> signUpFounder({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String familyName,
    required String languageCode,
  });

  /// The INVITEE branch (U-17), which is auto-confirmed and therefore cannot
  /// go through GoTrue sign-up: the `register-invitee` Edge Function creates
  /// the user with the service role after re-validating the invitation.
  Future<InviteeResult> registerInvitee({
    required String token,
    required String fullName,
    required String password,
    bool confirmMigration = false,
  });

  // ── F-57: social-login onboarding (deferred profile) ──────────────────────

  /// The FOUNDER half of the deferred onboarding: `complete_oauth_onboarding`
  /// creates family + admin profile for a session whose profile
  /// `handle_new_user` deferred, stamping the S-13 consent after validating
  /// the policy version server-side (S-15 posture). Throws with the server's
  /// PT-BR message on refusal.
  Future<void> completeOauthOnboarding({
    required String fullName,
    required String role,
    required String familyName,
  });

  /// The INVITEE half: the `claim-invitation` Edge Function attaches the
  /// CURRENT session to the invitation's family. Same result vocabulary as
  /// [registerInvitee] — including the S-11 migration question, which the
  /// onboarding screen answers with the same dialog the register form uses.
  Future<InviteeResult> claimInvitation({
    required String token,
    required String fullName,
    bool confirmMigration = false,
  });

  /// The identity providers of the current session (`email`, `google`, …) —
  /// what the profile screen reads to decide between the password card and
  /// the sign-in-method row (the U-21 slice F-57 requires). Empty when there
  /// is no session.
  List<String> authProviders();

  /// The display name the OAuth provider sent with the session, for
  /// prefilling the onboarding form. Null when absent or blank.
  String? sessionDisplayName();

  /// The e-mail of the CURRENT session — what the onboarding screen shows so
  /// "wrong Google account" is identifiable. The display name is not enough:
  /// two accounts of the same person routinely carry the same name, and the
  /// address is the only thing that always differs.
  String? sessionEmail();

  // ── Lote 4: family page, invitations and custom roles (F-41) ──────────────

  /// Every role this family may use: the 21 built-ins plus its own custom
  /// rows. RLS does the narrowing.
  Future<List<Role>> fetchRoles();

  /// Admin-only by DB rule; the rename is audited into `account_logs`.
  Future<void> renameFamily(String name);

  /// Invitations that are neither accepted nor revoked — pending AND expired,
  /// since the page offers a resend for the latter.
  Future<List<FamilyInvitation>> fetchOpenInvitations();

  /// `create_invitation` — which also REVOKES this address's previous open
  /// invitation before counting seats, so a resend never trips its own cap.
  /// That is what makes the call safe to retry. Returns the new row's id.
  ///
  /// F-56: with [profileId] the invitation is FOR that pending member — its
  /// role, its previous open invitation revoked, no seat gate (the placeholder
  /// already holds the seat). A resend of a placeholder's invitation MUST pass
  /// it, or the RPC would issue a placeholder-less invitation for the address.
  Future<int> createInvitation({
    required String email,
    required int roleId,
    int? profileId,
  });

  /// F-56: `add_pending_member` — the admin describes a caregiver who has no
  /// account yet (name, role; colour by the system). With [email] the
  /// invitation goes out in the same transaction. Returns the new profile id
  /// and, when an e-mail was given, the invitation id.
  Future<({int profileId, int? invitationId})> addPendingMember({
    required String fullName,
    required int roleId,
    String? email,
  });

  /// F-56: `remove_pending_member` — deleted outright when nothing references
  /// the placeholder, otherwise an S-11 tombstone (future days cleared, name
  /// kept on the past). Admin only, placeholder only; the RPC refuses the rest.
  Future<void> removePendingMember(int profileId);

  /// F-62: `attach_pending_member` — gives a LEGACY open invitation (one with
  /// no placeholder behind it) its pending member: the invitation's role, a
  /// colour by the system, and the SAME token, so the link already sent keeps
  /// working. Admin only; the RPC refuses accepted, revoked and already
  /// attached invitations. Returns the new profile id.
  Future<int> attachPendingMember({
    required int invitationId,
    required String fullName,
  });

  Future<void> revokeInvitation(int invitationId);

  /// Best-effort: the invitation exists either way, and the copyable link is
  /// the fallback the page always shows. Returns whether the mail went out.
  Future<bool> sendInvitationEmail(int invitationId);

  /// F-41. Server-enforced: admin, Premium, no duplicate (case-insensitive,
  /// against built-ins too). The client pre-checks only length/emoji.
  Future<void> createCustomRole({required String label, String? emoji});

  /// Omitting [emoji] CLEARS it — the RPC nulls a blank value.
  Future<void> updateCustomRole(
      {required int roleId, required String label, String? emoji});

  /// Delete is deliberately NOT Premium-gated (a family that lapses must still
  /// be able to clean up), but the DB refuses a role still in use.
  Future<void> deleteCustomRole(int roleId);

  // ── Lote 4: profile, account and the LGPD export ──────────────────────────

  /// My own name. A plain profile update — RLS bounds it to my row.
  Future<void> updateOwnName(int profileId, String fullName);

  /// Another member's name, admin-only by DB rule.
  Future<void> updateMemberName(int profileId, String fullName);

  /// Admin-only; audited into `account_logs` as `role_changed`.
  Future<void> setMemberRole({required int profileId, required int roleId});

  /// Admin-only AND sudo-gated (`ELEVATION_REQUIRED:`) — granting admin is the
  /// one membership change that hands out powers, so it costs a password.
  Future<void> setMemberAdmin({required int profileId, required bool isAdmin});

  /// Sends the password-reset e-mail to [email]. Used both for "I forgot mine"
  /// and for an admin helping another member.
  ///
  /// [language] is the language of the SCREEN the request was made from, and it
  /// rides along in the redirect (U-13 — see `AuthMail.languageQueryParam`).
  /// It is the reader's language in the case that matters, which is the person
  /// who cannot sign in asking for their own reset; when an admin asks on
  /// someone else's behalf it is the ADMIN's screen, and that is accepted
  /// because it only decides anything for a recipient whose profile declares
  /// no language of its own — an explicit `profiles.language` outranks it.
  Future<void> sendPasswordReset(String email, AppLanguage language);

  /// Starts an e-mail change. GoTrue only APPLIES it once the confirmation
  /// link is clicked, so success here means "link sent", never "changed".
  Future<void> updateOwnEmail(String email);

  Future<void> updateOwnPassword(String password);

  /// The `log_account_action` RPC — a whitelist of three self-actions
  /// (`password_changed`, `email_change_requested`, `data_exported`). The
  /// account log is append-only and family-scoped.
  Future<void> logAccountAction(String action);

  /// F-17: every row RLS lets this member read, for the LGPD export.
  Future<ExportBundle> fetchExportData(int myProfileId);

  // ── Lote 4: leaving, family deletion (S-11) and re-consent (S-15) ─────────

  /// The family's live deletion request and its answers, or null when there is
  /// none. At most one `pending` row can exist (partial unique index).
  Future<PendingFamilyDeletion?> fetchPendingFamilyDeletion();

  /// Sudo-gated. Admin-only, and refused while the family has a single live
  /// member — that person deletes the family by leaving instead.
  Future<void> requestFamilyDeletion();

  /// [agree] null REMOVES my answer (back to "aguardando"). Deliberately NOT
  /// sudo-gated: agreeing is not the destructive act, executing is.
  Future<void> respondFamilyDeletion(bool? agree);

  /// Sudo-gated; the requester's own way out.
  Future<void> withdrawFamilyDeletion();

  /// Sudo-gated. Admin-only and re-checks unanimity server-side; sets the
  /// deadline to now.
  Future<void> executeFamilyDeletion();

  /// Runs the purge immediately after [executeFamilyDeletion] instead of
  /// waiting for the cron. Best-effort: the row is already scheduled.
  Future<void> purgeNow();

  /// S-11: schedules MY exit (30 days). [successorProfileId] is required by the
  /// DB when I am the only admin — it promotes them BEFORE letting me go.
  /// Sudo-gated.
  Future<void> requestAccountDeletion({int? successorProfileId});

  /// Sudo-gated. Refused when the family already filled my seat.
  Future<void> cancelAccountDeletion();

  /// Best-effort account e-mails (`member_left`, `member_returned`,
  /// `family_deletion_requested` and friends) through `send-account-email`.
  Future<void> sendAccountEmail(String emailType, {int? profileId});

  /// S-15: records acceptance of [PolicyVersions.current]. The RPC REFUSES a
  /// version that is not the one `app_settings` declares, so a client that is
  /// behind fails loudly instead of stamping an unconsented version.
  Future<void> acceptCurrentPolicy();

  // ── Lote 4: first-run onboarding (U-23) ───────────────────────────────────

  /// Whether an invitation is still open. Bounded to one row: the checklist
  /// only needs to know THAT one exists.
  Future<bool> hasOpenInvitation();

  /// The two facts only a query can answer. [includeSwapParticipation] is
  /// false whenever the explanation stamp already settles that step, so the
  /// calendar does not pay for a read it cannot use.
  Future<OnboardingFacts> fetchOnboardingFacts({
    required int myProfileId,
    bool includeSwapParticipation = true,
  });

  /// Writes one of the three U-23 stamps on MY profile row. Idempotent: a
  /// stamp that already exists is left alone, so "seen" keeps its first date.
  Future<void> stampOnboarding(OnboardingStamp stamp);

  /// Reopening the checklist from the profile clears the dismissal.
  Future<void> clearChecklistDismissal();

  // ── Lote 6: reports (audit trail reads) ───────────────────────────────────
  // All family-scoped by RLS; the client only READS here — every audit row is
  // written by a trigger or a definer RPC.

  /// Every `care_schedules` row of the period, date-ascending — the Resumo
  /// screen and the F-33 document read the same way (mirror of
  /// `CustodyService.GetSchedulesForPeriodAsync`).
  Future<List<CareSchedule>> fetchSchedulesForPeriod(
      DateTime start, DateTime end);

  /// The newest page of calendar changes ("Recentes" tab). One page is
  /// [auditPageSize] rows; a FULL page means "there may be more".
  Future<List<ActivityLog>> fetchRecentActivityLogs({int offset = 0});

  /// Every calendar change whose AFFECTED DATE falls in the period — the
  /// month/year tabs and the F-33 document both read this way (the web filters
  /// on `affected_date`, not on when the change was made).
  Future<List<ActivityLog>> fetchActivityLogsForPeriod(
      DateTime start, DateTime end);

  /// S-10: the newest page of account operations ("Conta" tab).
  Future<List<AccountLog>> fetchAccountLogs({int offset = 0});

  /// F-61: every account operation of the given kinds, OLDEST first and
  /// unpaged — section 2 of the F-33 document reads a family's whole trail
  /// of caregiver events (`caregiverTimelineActions`). Enrichment: a failure
  /// costs the section's lines, never the document.
  Future<List<AccountLog>> fetchAccountLogsByAction(List<String> actions);

  /// F-45: batch reverse lookup — which swap request produced each of these
  /// log rows (keyed by `resolution_log_id`, stamped by the DB on both
  /// resolution paths). Enrichment only: a failure costs the origin line, never
  /// the timeline.
  Future<Map<int, SwapOrigin>> fetchResolutionOrigins(List<int> logIds);
}

/// The three U-23 stamps, named rather than passed as column strings.
enum OnboardingStamp {
  swapExplained('onboarding_swap_explained_at'),
  tourSeen('onboarding_tour_seen_at'),
  dismissed('onboarding_dismissed_at');

  const OnboardingStamp(this.column);

  final String column;
}

class OnboardingFacts {
  /// At least one row in `care_schedules`, ANY date — someone who planned
  /// August in July has done that step.
  final bool hasAnyPlannedDay;

  /// This member requested, or was asked to approve, a swap.
  final bool hasTakenPartInASwap;

  const OnboardingFacts({
    this.hasAnyPlannedDay = false,
    this.hasTakenPartInASwap = false,
  });
}

/// The family-deletion request together with the answers to it — they are
/// always read as a pair, and the panel needs both to say anything true.
class PendingFamilyDeletion {
  final FamilyDeletionRequest request;
  final List<FamilyDeletionResponse> responses;

  const PendingFamilyDeletion(this.request, this.responses);
}

/// The raw material of the F-17 export. Assembling it into the published JSON
/// shape is a pure step (`ExportService.buildPayload`), so the payload can be
/// asserted without a backend.
class ExportBundle {
  final List<CareSchedule> schedules;
  final List<SwapRequest> swapRequests;
  final List<AppNotification> notifications;

  /// The audit trail, still untyped: the audit MODEL arrives with the reports
  /// slice (lote 6). Carrying the rows through as maps keeps the export
  /// COMPLETE meanwhile — an LGPD export missing a category would be the
  /// wrong thing to defer.
  final List<Map<String, dynamic>> activityLog;

  const ExportBundle({
    this.schedules = const [],
    this.swapRequests = const [],
    this.notifications = const [],
    this.activityLog = const [],
  });
}

/// A sign-up refusal, already translated to a catalog KEY (GoTrue answers in
/// English whatever the reader's language).
class SignUpFailure implements Exception {
  final String errorKey;

  const SignUpFailure(this.errorKey);

  @override
  String toString() => 'SignUpFailure($errorKey)';
}

/// How the invitee branch ended.
sealed class InviteeResult {
  const InviteeResult();
}

/// The account exists and is confirmed — the caller signs in immediately.
class InviteeRegistered extends InviteeResult {
  const InviteeRegistered();
}

/// S-11 cross-family migration: this address already belongs to another
/// family, and joining this one DELETES that registration. The Edge Function
/// refuses until the visitor confirms, so this is a question, not an error.
class InviteeNeedsMigration extends InviteeResult {
  final String? previousFamilyName;

  const InviteeNeedsMigration(this.previousFamilyName);
}

/// A refusal. [message] is the function's own PT-BR text when it sent one —
/// still not localized server-side, so it reaches an English reader in
/// Portuguese (same as the web).
class InviteeFailed extends InviteeResult {
  final String? message;

  const InviteeFailed(this.message);
}

/// F-57: the server refused `complete_oauth_onboarding`. [message] is the
/// RPC's own PT-BR text (stale policy version, invalid role, account already
/// attached) when one arrived — null means unreachable, and the screen shows
/// its generic sentence instead.
class OnboardingRefused implements Exception {
  final String? message;

  const OnboardingRefused(this.message);

  @override
  String toString() => 'OnboardingRefused($message)';
}

/// Why the `elevate` Edge Function refused.
///
/// [serverMessage] is the function's OWN text and is preferred over any
/// client-side guess (pilot lesson 4: never collapse the server's error into a
/// generic one). The flags exist so the local throttle counts only genuine
/// wrong-password answers — a network hiccup must not spend an attempt.
class ElevationRefused implements Exception {
  final String? serverMessage;
  final bool wrongPassword;
  final bool rateLimited;

  /// S-21: the refusal came from the CODE path. Kept apart from
  /// [wrongPassword] because the two have different throttles — the code's
  /// ceiling lives on the server and destroys the code, so counting it locally
  /// as well would punish the same mistake twice.
  final bool wrongCode;

  const ElevationRefused({
    this.serverMessage,
    this.wrongPassword = false,
    this.rateLimited = false,
    this.wrongCode = false,
  });

  @override
  String toString() => 'ElevationRefused(${serverMessage ?? 'no message'})';
}

/// T-39: the `billing-checkout` Edge Function refused.
///
/// [serverMessage] is the function's OWN text and is preferred over any
/// client-side guess (pilot lesson 4: never collapse the server's error into a
/// generic one) — its refusals are written to be read by the payer, e.g. why
/// a card subscription cannot be resumed without paying today.
class BillingRefused implements Exception {
  final String? serverMessage;

  const BillingRefused([this.serverMessage]);

  @override
  String toString() => 'BillingRefused(${serverMessage ?? 'no message'})';
}
