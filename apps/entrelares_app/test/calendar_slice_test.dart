// The slice against a fake data source: grid painting, the day sheet's write
// path (insert and full-row update), conflict translation, the Realtime
// callback triggering a reload — and, since the U-13 port, that an English
// session renders the same slice in English.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/activity_log.dart';
import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/family_invitation.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

class FakeCustodyDataSource implements CustodyDataSource {
  final List<Member> members;
  List<CareSchedule> days;
  final List<CareSchedule> inserted = [];
  final List<CareSchedule> updated = [];
  final List<int> deleted = [];
  Family? family;
  Object? throwOnFamily;
  Map<String, String> publicSettings = const {};
  Object? throwOnWrite;
  void Function()? realtimeCallback;
  int monthFetches = 0;

  FakeCustodyDataSource({required this.members, required this.days});

  /// Lote 6: a roster read that fails — the reports screen maps it through the
  /// same central rules every other screen uses.
  Object? throwOnMembers;

  @override
  Future<List<Member>> fetchMembers() async {
    if (throwOnMembers != null) throw throwOnMembers!;
    return members;
  }

  @override
  Future<Member?> fetchOwnProfile() async => members.firstOrNull;

  @override
  Future<List<CareSchedule>> fetchUpcoming(DateTime from, int days) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = start.add(Duration(days: days));
    return this
        .days
        .where((d) =>
            !d.scheduleDate.isBefore(start) && !d.scheduleDate.isAfter(end))
        .toList();
  }

  @override
  Future<Family?> fetchOwnFamily() async {
    if (throwOnFamily != null) throw throwOnFamily!;
    return family;
  }

  @override
  Future<Map<String, String>> fetchPublicSettings() async => publicSettings;

  // ── Lote 5: billing reads. Default to the shape of a family that never
  // started a checkout — the state every screen outside the Premium section
  // is written against.
  Subscription? subscription;
  Object? throwOnSubscription;
  List<BillingHistoryEntry> billingHistory = const [];
  Object? throwOnBillingHistory;
  bool premiumInterest = false;
  int billingHistoryFetches = 0;

  @override
  Future<Subscription?> fetchSubscription() async {
    // Mirrors the real source's fail-closed contract: the failure becomes
    // "no subscription", it does not escape to the screen.
    if (throwOnSubscription != null) return null;
    return subscription;
  }

  @override
  Future<List<BillingHistoryEntry>> fetchBillingHistory() async {
    billingHistoryFetches++;
    if (throwOnBillingHistory != null) throw throwOnBillingHistory!;
    return billingHistory;
  }

  @override
  Future<bool> hasRegisteredPremiumInterest() async => premiumInterest;

  final List<String?> registeredInterest = [];
  int cancelCalls = 0;
  int reactivateCalls = 0;
  Object? throwOnBillingAction;

  @override
  Future<void> registerPremiumInterest({String? feature}) async {
    if (throwOnBillingAction != null) throw throwOnBillingAction!;
    registeredInterest.add(feature);
    premiumInterest = true;
  }

  final List<({String action, String cycle})> checkouts = [];
  String checkoutUrl = 'https://pagamento.example/abc';

  @override
  Future<String> startCheckout(String cycle) async {
    if (throwOnBillingAction != null) throw throwOnBillingAction!;
    checkouts.add((action: 'checkout', cycle: cycle));
    return checkoutUrl;
  }

  @override
  Future<String> startAvulso(String cycle) async {
    if (throwOnBillingAction != null) throw throwOnBillingAction!;
    checkouts.add((action: 'avulso', cycle: cycle));
    return checkoutUrl;
  }

  final List<({String productId, String token})> verifiedPurchases = [];
  Object? throwOnVerify;

  @override
  Future<void> verifyStorePurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    if (throwOnVerify != null) throw throwOnVerify!;
    verifiedPurchases.add((productId: productId, token: purchaseToken));
  }

  @override
  Future<void> cancelSubscription() async {
    if (throwOnBillingAction != null) throw throwOnBillingAction!;
    cancelCalls++;
  }

  @override
  Future<void> reactivateSubscription() async {
    if (throwOnBillingAction != null) throw throwOnBillingAction!;
    reactivateCalls++;
  }

  @override
  Future<void> updateOwnLanguage(int profileId, String languageCode) async {}

  @override
  Future<void> updateDetectedLanguage(
      int profileId, String languageCode) async {}

  @override
  Future<List<CareSchedule>> fetchMonth(int year, int month) async {
    monthFetches++;
    return days
        .where((d) =>
            d.scheduleDate.year == year && d.scheduleDate.month == month)
        .toList();
  }

  @override
  Future<CareSchedule?> fetchDay(DateTime date) async {
    for (final d in days) {
      if (CareSchedule.isoDate(d.scheduleDate) == CareSchedule.isoDate(date)) {
        return d;
      }
    }
    return null;
  }

  @override
  Future<void> insertDay(CareSchedule day) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    inserted.add(day);
  }

  @override
  Future<void> deleteDay(int id) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    deleted.add(id);
    days = days.where((d) => d.id != id).toList();
  }

  @override
  Future<int> bulkInsertNewDays(List<CareSchedule> newDays,
      {void Function(int percent)? onProgress}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    final existing = {for (final d in days) CareSchedule.isoDate(d.scheduleDate)};
    final now = DateTime.now();
    final todayFloor = DateTime(now.year, now.month, now.day);
    var created = 0;
    for (final d in newDays) {
      if (d.scheduleDate.isBefore(todayFloor)) continue;
      if (existing.contains(CareSchedule.isoDate(d.scheduleDate))) continue;
      inserted.add(d);
      days = [...days, d];
      created++;
    }
    onProgress?.call(100);
    return created;
  }

  @override
  Future<void> updateDay(CareSchedule day) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    updated.add(day);
  }

  void Function(bool connected)? statusCallback;

  @override
  Future<void Function()> watchChanges(void Function() onChange,
      {void Function(bool connected)? onStatus}) async {
    realtimeCallback = onChange;
    statusCallback = onStatus;
    return () => realtimeCallback = null;
  }

  // ── Lote 3: swap workflow ──────────────────────────────────────────────────

  List<SwapRequest> frozenRequests = [];
  List<SwapRequest> pendingForMe = [];
  List<SwapRequest> sentRequests = [];
  List<AppNotification> notifications = [];
  PreEditNotes? preEditNotes;
  final List<Map<String, Object?>> createdSwapRequests = [];
  final List<Map<String, Object?>> revertRequests = [];
  final List<({int id, String? note})> approvedSwaps = [];
  final List<({int id, String? reason})> rejectedSwaps = [];
  final List<int> cancelledSwaps = [];
  final List<({int id, String? note})> approvedReverts = [];
  final List<({int id, String? reason})> rejectedReverts = [];
  final List<int> cancelledReverts = [];
  int markAllReadCalls = 0;

  @override
  Future<List<SwapRequest>> fetchFrozenRequestsForMonth(
          int year, int month) async =>
      frozenRequests
          .where((r) =>
              r.scheduleDate.year == year && r.scheduleDate.month == month)
          .toList();

  @override
  Future<List<SwapRequest>> fetchPendingForMe(int myProfileId) async =>
      pendingForMe;

  @override
  Future<List<SwapRequest>> fetchSentRequests(int myProfileId) async =>
      sentRequests;

  @override
  Future<void> createSwapRequest({
    required CareSchedule schedule,
    required int proposedActualParentId,
    String? proposedHandoffTime,
    String? requestMessage,
    required Member myProfile,
    required List<Member> allProfiles,
  }) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    createdSwapRequests.add({
      'date': CareSchedule.isoDate(schedule.scheduleDate),
      'proposed': proposedActualParentId,
      'handoff': proposedHandoffTime,
      'message': requestMessage,
      'requester': myProfile.id,
    });
  }

  @override
  Future<void> approveSwap(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    approvedSwaps.add((id: swapRequestId, note: approvalNote));
  }

  @override
  Future<void> rejectSwap(int swapRequestId,
      {String? reason, required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    rejectedSwaps.add((id: swapRequestId, reason: reason));
  }

  @override
  Future<void> cancelSwap(int swapRequestId,
      {required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    cancelledSwaps.add(swapRequestId);
  }

  @override
  Future<void> requestRevert({
    required DateTime scheduleDate,
    required int currentActualProfileId,
    required int scheduledParentId,
    String? requestMessage,
    bool restoreNotes = false,
    required Member myProfile,
    required List<Member> allProfiles,
  }) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    revertRequests.add({
      'date': CareSchedule.isoDate(scheduleDate),
      'currentActual': currentActualProfileId,
      'scheduled': scheduledParentId,
      'message': requestMessage,
      'restoreNotes': restoreNotes,
      'requester': myProfile.id,
    });
  }

  @override
  Future<void> approveRevert(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    approvedReverts.add((id: swapRequestId, note: approvalNote));
  }

  @override
  Future<void> rejectRevert(int swapRequestId,
      {String? reason, required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    rejectedReverts.add((id: swapRequestId, reason: reason));
  }

  @override
  Future<void> cancelRevert(int swapRequestId,
      {required List<Member> allProfiles}) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    cancelledReverts.add(swapRequestId);
  }

  @override
  Future<PreEditNotes?> fetchPreEditNotes(DateTime scheduleDate) async =>
      preEditNotes;

  @override
  Future<List<AppNotification>> fetchNotifications(int myProfileId) async =>
      notifications;

  @override
  Future<void> markAllNotificationsRead(int myProfileId) async {
    markAllReadCalls++;
    notifications = [
      for (final n in notifications)
        AppNotification(
          id: n.id,
          recipientProfileId: n.recipientProfileId,
          type: n.type,
          title: n.title,
          message: n.message,
          params: n.params,
          swapRequestId: n.swapRequestId,
          isRead: true,
          createdAt: n.createdAt,
        ),
    ];
  }

  /// More than one subscriber (calendar + badge) — all get poked.
  final List<void Function()> workflowCallbacks = [];

  void Function()? get workflowCallback =>
      workflowCallbacks.isEmpty ? null : _fireAllWorkflow;

  void _fireAllWorkflow() {
    for (final cb in List.of(workflowCallbacks)) {
      cb();
    }
  }

  @override
  Future<void Function()> watchWorkflowChanges(void Function() onChange,
      {void Function(bool connected)? onStatus}) async {
    workflowCallbacks.add(onChange);
    return () => workflowCallbacks.remove(onChange);
  }

  // ── Lote 4: sudo elevation (S-10) ──
  /// Passwords the fake accepts; anything else answers like the real 401.
  String? sudoPassword;

  /// What [elevate] reports as `elevated_until`; null exercises the local
  /// 5-minute fallback.
  String? sudoElevatedUntil;

  /// Set to answer with a transport failure instead of a verdict.
  Object? throwOnElevate;

  final List<String> elevateAttempts = [];

  @override
  Future<String?> elevate(String password) async {
    elevateAttempts.add(password);
    if (throwOnElevate != null) throw throwOnElevate!;
    if (sudoPassword != null && password == sudoPassword) {
      return sudoElevatedUntil;
    }
    throw const ElevationRefused(
        serverMessage: 'Senha incorreta.', wrongPassword: true);
  }

  // ── S-21: the second proof ────────────────────────────────────────────────

  /// Codes asked for, in order. `null` entries are impossible: the sheet never
  /// asks without a session.
  int codeRequests = 0;
  final List<String> codeAttempts = [];

  /// The code this fake will accept. Null means every code is refused.
  String? sudoCode;

  /// Set to make the request itself fail — a throttle (429) or an outage.
  ElevationRefused? throwOnRequestCode;

  @override
  Future<int> requestElevationCode() async {
    codeRequests++;
    if (throwOnRequestCode != null) throw throwOnRequestCode!;
    return SudoRules.codeTtl.inMinutes;
  }

  @override
  Future<String?> elevateWithCode(String code) async {
    codeAttempts.add(code);
    if (sudoCode != null && code == sudoCode) return sudoElevatedUntil;
    throw const ElevationRefused(
        serverMessage: 'Código incorreto.', wrongCode: true);
  }

  // ── Lote 4: sign-up and invitations ──
  /// What [fetchInviteInfo] resolves to; null makes every token invalid.
  InviteInfo? inviteInfo;

  /// Refuses the founder branch with this catalog key.
  String? signUpFailureKey;

  /// What [registerInvitee] answers; defaults to success.
  InviteeResult inviteeResult = const InviteeRegistered();

  final List<Map<String, Object?>> signUps = [];
  final List<Map<String, Object?>> inviteeRegistrations = [];

  @override
  Future<InviteInfo?> fetchInviteInfo(String token) async =>
      InviteFormRules.isTokenShaped(token) ? inviteInfo : null;

  @override
  Future<void> signUpFounder({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String familyName,
    required String languageCode,
  }) async {
    signUps.add({
      'email': email,
      'fullName': fullName,
      'role': role,
      'familyName': familyName,
      'language': languageCode,
    });
    if (signUpFailureKey != null) throw SignUpFailure(signUpFailureKey!);
  }

  @override
  Future<InviteeResult> registerInvitee({
    required String token,
    required String fullName,
    required String password,
    bool confirmMigration = false,
  }) async {
    inviteeRegistrations.add({
      'token': token,
      'fullName': fullName,
      'confirmMigration': confirmMigration,
    });
    return inviteeResult;
  }

  // ── F-57: social-login onboarding ──
  /// Refuses [completeOauthOnboarding] with this server text when set.
  String? onboardingRefusalMessage;

  /// What [claimInvitation] answers; defaults to success.
  InviteeResult claimResult = const InviteeRegistered();

  /// What [authProviders] reports — password-only by default.
  List<String> providers = const ['email'];

  /// What [sessionDisplayName] prefills.
  String? displayName;

  /// What [sessionEmail] reports — the address the onboarding screen shows so
  /// a wrong Google account is identifiable.
  String? sessionEmailValue;

  final List<Map<String, Object?>> onboardings = [];
  final List<Map<String, Object?>> claims = [];

  @override
  Future<void> completeOauthOnboarding({
    required String fullName,
    required String role,
    required String familyName,
  }) async {
    onboardings.add({
      'fullName': fullName,
      'role': role,
      'familyName': familyName,
    });
    if (onboardingRefusalMessage != null) {
      throw OnboardingRefused(onboardingRefusalMessage);
    }
  }

  @override
  Future<InviteeResult> claimInvitation({
    required String token,
    required String fullName,
    bool confirmMigration = false,
  }) async {
    claims.add({
      'token': token,
      'fullName': fullName,
      'confirmMigration': confirmMigration,
    });
    return claimResult;
  }

  @override
  List<String> authProviders() => providers;

  @override
  String? sessionDisplayName() => displayName;

  @override
  String? sessionEmail() => sessionEmailValue;

  // ── Lote 4: family page, invitations and custom roles ──
  List<Role> roles = const [];
  List<FamilyInvitation> invitations = const [];

  /// Thrown by whichever family/invitation/role write is exercised next.
  Object? throwOnFamilyWrite;

  /// Whether [sendInvitationEmail] reports success.
  bool inviteEmailSucceeds = true;

  final List<String> renames = [];
  final List<Map<String, Object?>> createdInvitations = [];
  final List<int> revokedInvitations = [];
  final List<int> mailedInvitations = [];
  final List<Map<String, Object?>> customRoleWrites = [];
  final List<int> deletedRoles = [];

  @override
  Future<List<Role>> fetchRoles() async => roles;

  @override
  Future<void> renameFamily(String name) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    renames.add(name);
    family = Family(id: family?.id ?? 1, name: name, plan: family?.plan ?? 'free');
  }

  @override
  Future<List<FamilyInvitation>> fetchOpenInvitations() async => invitations;

  @override
  Future<int> createInvitation({
    required String email,
    required int roleId,
    int? profileId,
  }) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    createdInvitations
        .add({'email': email, 'roleId': roleId, 'profileId': profileId});
    return 42;
  }

  /// F-56: what the page asked `add_pending_member` for, in order.
  final List<Map<String, Object?>> addedPending = [];
  final List<int> removedPending = [];

  @override
  Future<({int profileId, int? invitationId})> addPendingMember({
    required String fullName,
    required int roleId,
    String? email,
  }) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    addedPending.add({'fullName': fullName, 'roleId': roleId, 'email': email});
    final clean = email?.trim() ?? '';
    return (profileId: 500 + addedPending.length, invitationId: clean.isEmpty ? null : 42);
  }

  @override
  Future<void> removePendingMember(int profileId) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    removedPending.add(profileId);
  }

  /// F-62: what the page asked `attach_pending_member` for, in order.
  final List<Map<String, Object?>> attachedPending = [];

  @override
  Future<int> attachPendingMember({
    required int invitationId,
    required String fullName,
  }) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    attachedPending.add({'invitationId': invitationId, 'fullName': fullName});
    return 600 + attachedPending.length;
  }

  @override
  Future<void> revokeInvitation(int invitationId) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    revokedInvitations.add(invitationId);
  }

  @override
  Future<bool> sendInvitationEmail(int invitationId) async {
    mailedInvitations.add(invitationId);
    return inviteEmailSucceeds;
  }

  @override
  Future<void> createCustomRole({required String label, String? emoji}) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    customRoleWrites.add({'label': label, 'emoji': emoji, 'id': null});
  }

  @override
  Future<void> updateCustomRole(
      {required int roleId, required String label, String? emoji}) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    customRoleWrites.add({'label': label, 'emoji': emoji, 'id': roleId});
  }

  @override
  Future<void> deleteCustomRole(int roleId) async {
    if (throwOnFamilyWrite != null) throw throwOnFamilyWrite!;
    deletedRoles.add(roleId);
  }

  // ── Lote 4: profile, account and the LGPD export ──
  ExportBundle exportBundle = const ExportBundle();

  /// Thrown by whichever profile/account write is exercised next.
  Object? throwOnProfileWrite;

  final List<Map<String, Object?>> nameUpdates = [];
  final List<Map<String, Object?>> roleUpdates = [];
  final List<Map<String, Object?>> adminUpdates = [];
  final List<String> passwordResets = [];
  final List<String> emailUpdates = [];
  final List<String> passwordUpdates = [];
  final List<String> accountActions = [];
  int exportFetches = 0;

  @override
  Future<void> updateOwnName(int profileId, String fullName) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    nameUpdates.add({'id': profileId, 'name': fullName, 'own': true});
  }

  @override
  Future<void> updateMemberName(int profileId, String fullName) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    nameUpdates.add({'id': profileId, 'name': fullName, 'own': false});
  }

  @override
  Future<void> setMemberRole(
      {required int profileId, required int roleId}) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    roleUpdates.add({'id': profileId, 'roleId': roleId});
  }

  @override
  Future<void> setMemberAdmin(
      {required int profileId, required bool isAdmin}) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    adminUpdates.add({'id': profileId, 'isAdmin': isAdmin});
  }

  @override
  Future<void> sendPasswordReset(String email, AppLanguage language) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    passwordResets.add(email);
  }

  @override
  Future<void> updateOwnEmail(String email) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    emailUpdates.add(email);
  }

  @override
  Future<void> updateOwnPassword(String password) async {
    if (throwOnProfileWrite != null) throw throwOnProfileWrite!;
    passwordUpdates.add(password);
  }

  @override
  Future<void> logAccountAction(String action) async {
    accountActions.add(action);
  }

  @override
  Future<ExportBundle> fetchExportData(int myProfileId) async {
    exportFetches++;
    return exportBundle;
  }

  // ── Lote 4: leaving, family deletion (S-11) and re-consent (S-15) ──
  PendingFamilyDeletion? pendingDeletion;

  /// Thrown by whichever lifecycle write is exercised next.
  Object? throwOnLifecycle;

  int deletionRequests = 0;
  int withdrawals = 0;
  int executions = 0;
  int purges = 0;
  int policyAccepts = 0;
  int cancelledExits = 0;
  final List<bool?> deletionResponses = [];
  final List<int?> accountDeletions = [];
  final List<String> accountEmails = [];

  @override
  Future<PendingFamilyDeletion?> fetchPendingFamilyDeletion() async =>
      pendingDeletion;

  @override
  Future<void> requestFamilyDeletion() async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    deletionRequests++;
  }

  @override
  Future<void> respondFamilyDeletion(bool? agree) async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    deletionResponses.add(agree);
  }

  @override
  Future<void> withdrawFamilyDeletion() async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    withdrawals++;
  }

  @override
  Future<void> executeFamilyDeletion() async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    executions++;
  }

  @override
  Future<void> purgeNow() async => purges++;

  @override
  Future<void> requestAccountDeletion({int? successorProfileId}) async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    accountDeletions.add(successorProfileId);
  }

  @override
  Future<void> cancelAccountDeletion() async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    cancelledExits++;
  }

  @override
  Future<void> sendAccountEmail(String emailType, {int? profileId}) async {
    accountEmails.add(emailType);
  }

  @override
  Future<void> acceptCurrentPolicy() async {
    if (throwOnLifecycle != null) throw throwOnLifecycle!;
    policyAccepts++;
  }

  // ── Lote 4: first-run onboarding (U-23) ──
  bool openInvitationExists = false;
  OnboardingFacts onboardingFacts = const OnboardingFacts();
  final List<OnboardingStamp> stamps = [];
  int dismissalsCleared = 0;

  /// Records whether the caller asked for the second (optional) read.
  final List<bool> onboardingFactReads = [];

  @override
  Future<bool> hasOpenInvitation() async => openInvitationExists;

  @override
  Future<OnboardingFacts> fetchOnboardingFacts({
    required int myProfileId,
    bool includeSwapParticipation = true,
  }) async {
    onboardingFactReads.add(includeSwapParticipation);
    return onboardingFacts;
  }

  @override
  Future<void> stampOnboarding(OnboardingStamp stamp) async {
    stamps.add(stamp);
  }

  @override
  Future<void> clearChecklistDismissal() async => dismissalsCleared++;

  // ── Lote 6: reports (audit trail reads) ──
  List<ActivityLog> activityLogs = const [];
  List<AccountLog> accountLogs = const [];
  Map<int, SwapOrigin> resolutionOrigins = const {};
  Object? throwOnOrigins;

  /// Every (offset) the timeline asked for — "Carregar mais" is paging, and a
  /// test that cannot see the offsets cannot prove it.
  final List<int> activityOffsets = [];
  final List<int> accountOffsets = [];
  final List<List<int>> originLookups = [];

  /// Every (start, end) a report asked for — a screen that reloads on filter
  /// change can only be proven by the periods it queried.
  final List<(DateTime, DateTime)> periodReads = [];

  @override
  Future<List<CareSchedule>> fetchSchedulesForPeriod(
      DateTime start, DateTime end) async {
    periodReads.add((start, end));
    return days
        .where((d) =>
            !d.scheduleDate.isBefore(start) && !d.scheduleDate.isAfter(end))
        .toList();
  }

  @override
  Future<List<ActivityLog>> fetchRecentActivityLogs({int offset = 0}) async {
    activityOffsets.add(offset);
    return activityLogs.skip(offset).take(auditPageSize).toList();
  }

  /// Every (start, end) the Histórico asked the trail for.
  final List<(DateTime, DateTime)> periodLogReads = [];

  @override
  Future<List<ActivityLog>> fetchActivityLogsForPeriod(
      DateTime start, DateTime end) async {
    periodLogReads.add((start, end));
    return activityLogs
        .where((l) =>
            !l.affectedDate.isBefore(start) && !l.affectedDate.isAfter(end))
        .toList();
  }

  @override
  Future<List<AccountLog>> fetchAccountLogs({int offset = 0}) async {
    accountOffsets.add(offset);
    return accountLogs.skip(offset).take(auditPageSize).toList();
  }

  /// F-61: every action list the document asked the trail for.
  final List<List<String>> accountActionLookups = [];
  Object? throwOnAccountActions;

  @override
  Future<List<AccountLog>> fetchAccountLogsByAction(
      List<String> actions) async {
    accountActionLookups.add(actions);
    if (throwOnAccountActions != null) throw throwOnAccountActions!;
    return [
      for (final log in accountLogs)
        if (actions.contains(log.action)) log
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<Map<int, SwapOrigin>> fetchResolutionOrigins(List<int> logIds) async {
    originLookups.add(logIds);
    if (throwOnOrigins != null) throw throwOnOrigins!;
    return {
      for (final id in logIds)
        if (resolutionOrigins.containsKey(id)) id: resolutionOrigins[id]!,
    };
  }

  // ── F-09 (unused by the calendar slice, recorded so the fake stays honest) ──
  /// The registry, keyed the way the real table is: on the TOKEN. A device
  /// appears at most once however many times it registers, which is the
  /// UNIQUE constraint the server carries — a fake that allowed the same
  /// token twice would make a repair look like a leak.
  final List<String> registeredPushTokens = [];

  /// Every token [isDeviceRegistered] was asked about, in order. Recorded so a
  /// suite can pin WHICH question was asked: "is this device registered?" and
  /// "does this profile have any device?" are answered identically on the
  /// first phone and differently on the second.
  final List<String> deviceChecks = [];

  @override
  Future<void> registerPushToken({
    required int myProfileId,
    required String token,
    required String platform,
    String? deviceLabel,
  }) async {
    if (!registeredPushTokens.contains(token)) registeredPushTokens.add(token);
  }

  @override
  Future<void> deletePushToken(String token) async {
    registeredPushTokens.remove(token);
  }

  /// Keyed on the token alone: this fake serves one profile, and the server's
  /// own answer for another profile's device is `false` either way — RLS hides
  /// the row, so there is nothing to model.
  @override
  Future<bool> isDeviceRegistered({
    required int myProfileId,
    required String token,
  }) async {
    deviceChecks.add(token);
    return registeredPushTokens.contains(token);
  }
}

const ana = Member(id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1');
const bruno = Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2');

DateTime get today => DateTime.now();
DateTime dayOfMonth(int day) => DateTime(today.year, today.month, day);

CareSchedule row(int id, DateTime date, int scheduled,
        {int? actual, int revision = 1, String? handoffTime}) =>
    CareSchedule.fromJson({
      'id': id,
      'schedule_date': CareSchedule.isoDate(date),
      'scheduled_parent_id': scheduled,
      'actual_parent_id': actual,
      'revision': revision,
      'revision_token': 'tok-$id',
      'handoff_time': ?handoffTime,
    });

Widget app(FakeCustodyDataSource ds,
        {AppLanguage language = AppLanguage.ptBr, AdminMode? adminMode}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
            dataSource: ds,
            adminMode: adminMode ?? AdminMode(),
            ),
      ),
    );

/// Tomorrow, unless the month ends today (then the write tests short-circuit
/// — the fixed today of a CI clock never hits it two runs in a row).
int? get futureDay {
  final lastDay = DateTime(today.year, today.month + 1, 0).day;
  return today.day == lastDay ? null : today.day + 1;
}

Future<void> openDay(WidgetTester tester, int day) async {
  final finder = find.text('$day').last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The full editor is taller than the sheet's viewport — scroll the target
/// into view before tapping.
Future<void> tapSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets the save/clear SnackBar's dismiss timer fire so none outlives a test.
Future<void> settleSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 9));
  await tester.pumpAndSettle();
}

/// U-28 QA: the month bar capitalises the heading — `formatMonthYear` lowercases
/// because its output usually sits inside a sentence.
String monthHeading(Localization l, DateTime month) {
  final text = l.formatMonthYear(month.year, month.month);
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

DateTime _monthAfter(DateTime d) => DateTime(d.year, d.month + 1, 1);
DateTime _monthBefore(DateTime d) => DateTime(d.year, d.month - 1, 1);

void main() {
  testWidgets('legend shows active members and the grid paints initials',
      (tester) async {
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(10), 1), row(2, dayOfMonth(11), 1, actual: 2)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Trocado'), findsOneWidget);
    // Day 10 belongs to Ana ("A"); day 11 is swapped to Bruno ("B").
    expect(find.text('A'), findsWidgets);
    expect(find.text('B'), findsWidgets);
  });

  testWidgets('unassigned future day: sheet inserts with the chosen parent',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final day = futureDay;
    if (day == null) return;
    await openDay(tester, day);
    // Since lote 2 the sheet is the FULL editor — the planned-parent label
    // (U-29 moved the "(Planejado)" explainer into the label's info tip).
    expect(find.text(Localization(AppLanguage.ptBr)[K.editorScheduledParent]),
        findsOneWidget);

    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Bruno'));
    await tapSheet(tester, find.text('Salvar'));

    expect(ds.inserted, hasLength(1));
    expect(ds.inserted.single.scheduledParentId, 2);
    expect(ds.inserted.single.scheduleDate, dayOfMonth(day));
    expect(ds.updated, isEmpty);

    // The save confirmation SnackBar (web: Toast.ShowSuccess(K.ToastSaved)).
    expect(find.text('Salvo com sucesso'), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets(
      'assigned future day: sheet updates the FULL row with the token echo',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(5, dayOfMonth(day), 1, revision: 4)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    // S-09 (lote 2): the planned parent of an assigned day is locked for
    // non-admins — the note is the editable surface that triggers the update.
    await tester.enterText(find.byType(TextField), 'Trocar mochila');
    await tapSheet(tester, find.text('Salvar'));

    expect(ds.updated, hasLength(1));
    final sent = ds.updated.single;
    expect(sent.id, 5);
    expect(sent.scheduledParentId, 1);
    expect(sent.notes, 'Trocar mochila');
    final json = sent.toUpdateJson();
    expect(json['submitted_token'], 'tok-5', reason: 'T-35 echo must survive');
    expect(json['revision'], 4, reason: 'T-33 revision as read');

    await settleSnack(tester);
  });

  testWidgets('day conflict shows the "salvou primeiro" message',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(5, dayOfMonth(day), 1)],
    )..throwOnWrite = Exception(
        '{"code":"23505","message":"duplicate key value violates unique '
        'constraint \\"care_schedules_family_schedule_date_key\\""}');
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    await tester.enterText(find.byType(TextField), 'Nota qualquer');
    await tapSheet(tester, find.text('Salvar'));

    expect(
        find.textContaining('salvou este dia primeiro'), findsOneWidget);
  });

  testWidgets('past days are read-only (day-protection mirror)',
      (tester) async {
    // Run this one only when the month has a past day (i.e. not on the 1st).
    if (today.day == 1) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(9, dayOfMonth(1), 1)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final finder = find.text('1').last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    // The amber readonly banner (web: .readonly-banner / K.editorPastReadonly).
    expect(
        find.text('🔒 Dia passado — apenas visualização'), findsOneWidget);
    expect(find.text('Salvar'), findsNothing);
  });

  testWidgets('a Realtime event reloads the visible month', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final before = ds.monthFetches;

    ds.realtimeCallback!();
    await tester.pumpAndSettle();
    expect(ds.monthFetches, greaterThan(before));
  });

  // U-13/U-24 — the proof the pilot never gave: the SAME slice, English
  // session. Words come from the catalog, the day sheet question included;
  // names stay user data; the swapped legend translates.
  testWidgets('an English session renders the slice in English',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1, actual: 2)],
    );
    await tester.pumpWidget(app(ds, language: AppLanguage.en));
    await tester.pumpAndSettle();

    expect(find.text('Swapped'), findsOneWidget);
    expect(find.text('Trocado'), findsNothing);
    expect(find.text('Ana'), findsOneWidget, reason: 'names never translate');

    await openDay(tester, day);
    expect(find.text('Planned caregiver'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    // U-28 QA: the redundant "Responsável: X (swapped)" line is gone; the fact
    // it carried now rides as a badge on the field that owns it.
    expect(find.text('Swapped'), findsWidgets);
  });

  // ── U-28: the month bar ────────────────────────────────────────────────────

  testWidgets('the month name sits above the grid, not in the app bar',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final l = Localization(AppLanguage.ptBr);
    final month = monthHeading(l, today);
    expect(find.text(month), findsOneWidget);
    // The app bar names the TAB now — five actions up there were what
    // truncated the month to "agosto de..." for an admin.
    expect(find.text(l[K.navCalendar]), findsOneWidget);
    expect(
        tester.getTopLeft(find.text(month)).dy >
            tester.getTopLeft(find.text(l[K.navCalendar])).dy,
        isTrue,
        reason: 'the month must sit below the app bar, against its own grid');
  });

  testWidgets('the arrows step the month in both directions', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final l = Localization(AppLanguage.ptBr);
    final next = DateTime(today.year, today.month + 1, 1);
    final previous = DateTime(today.year, today.month - 1, 1);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text(monthHeading(l, next)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text(monthHeading(l, previous)),
        findsOneWidget);
  });

  testWidgets('the calendar app bar carries the account button and nothing else',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    // The language picker and the logout icon moved into the account menu;
    // logout living only here is the defect U-28 closes.
    expect(find.byIcon(Icons.language), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
    // The calendar's OWN actions stay with the calendar.
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(find.byIcon(Icons.event_repeat), findsOneWidget);
  });

  testWidgets('U-28: every assigned cell prints the carer initial',
      (tester) async {
    // This is the non-chromatic vector that lets the active slots drop their
    // hatch (see no_color_literal_test). If a cell ever stops printing the
    // initial, colour becomes the only way to tell two carers apart.
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(GridView), matching: find.text('A')),
        findsWidgets);
  });

  testWidgets('U-28: a handoff day shows the TIME, not an anonymous arrow',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1, handoffTime: '18:00')],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(find.text('18:00'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });

  testWidgets('U-28 QA: the legend names the role and never scrolls sideways',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1, actual: 2)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    // It WRAPS. "Fernanda (Mãe)" is ~100 dp with its swatch, so four carers
    // plus the swap key is ~490 dp against a 360 dp phone — one line was never
    // going to hold them, and a sideways scroll hides the fourth carer behind
    // a gesture nobody knows is there.
    final l = Localization(AppLanguage.ptBr);
    expect(
        find.ancestor(
            of: find.text(l[K.calSwapped]), matching: find.byType(Wrap)),
        findsWidgets);
    // This fixture carries no roles, so the key is the bare first name; the
    // role suffix is exercised where the roles exist (family_page_test).
    expect(find.text('Ana'), findsWidgets);
  });

  // U-18 parity, in two tests and not one: pumping a second CalendarScreen of
  // the same type reuses the State, so the second data source would never be
  // read and the assertion would pass for the wrong reason.
  testWidgets('U-18 parity: a month with no swap has no swap key',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    // The key would be explaining something that is not on screen, and it costs
    // the grid the width of its own label.
    await tester.pumpWidget(app(FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1)],
    )));
    await tester.pumpAndSettle();
    expect(find.text(Localization(AppLanguage.ptBr)[K.calSwapped]), findsNothing);
  });

  testWidgets('U-18 parity: one swapped day brings the key back',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await tester.pumpWidget(app(FakeCustodyDataSource(
      members: [ana, bruno],
      days: [row(1, dayOfMonth(day), 1, actual: 2)],
    )));
    await tester.pumpAndSettle();
    expect(
        find.text(Localization(AppLanguage.ptBr)[K.calSwapped]), findsOneWidget);
  });

  testWidgets('U-28 QA: the month name is not truncated by the actions',
      (tester) async {
    final l = Localization(AppLanguage.ptBr);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    // The calendar's actions moved up to the app bar; sharing the month row
    // with them is what put "agosto de 20…" on screen.
    final month = find.text(monthHeading(l, today));
    expect(month, findsOneWidget);
    final text = tester.widget<Text>(month);
    expect(text.overflow, TextOverflow.ellipsis);
    final rendered = tester.renderObject<RenderBox>(month);
    expect(rendered.size.width, greaterThan(120),
        reason: 'the month owns the middle of its own bar now');
  });

  testWidgets('U-28 QA: legend keys are pills that sit side by side',
      (tester) async {
    // The regression this pins: a Container WITH an `alignment` expands to fill
    // whatever it is offered, so every key took a full row of the Wrap and the
    // legend became a stack of banners.
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final first = tester.getRect(find.text('Ana'));
    final second = tester.getRect(find.text('Bruno'));
    expect(first.top, second.top,
        reason: 'two carers must share a row, not stack');
    expect(second.left, greaterThan(first.right),
        reason: 'and the second sits beside the first');
  });

  testWidgets('U-28 QA: the way back to today is a chip in the month bar',
      (tester) async {
    final l = Localization(AppLanguage.ptBr);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    // On the current month there is nothing to go back from.
    expect(find.text(l[K.calToday]), findsNothing);

    // Looking at the FUTURE: today is behind, so the chip stands to the LEFT
    // of the month and its arrow points back.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text(l[K.calToday]), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(tester.getRect(find.text(l[K.calToday])).right,
        lessThan(tester.getRect(find.text(monthHeading(l, _monthAfter(today)))).left));

    await tester.tap(find.text(l[K.calToday]));
    await tester.pumpAndSettle();
    expect(find.text(monthHeading(l, today)), findsOneWidget);
    expect(find.text(l[K.calToday]), findsNothing);

    // Looking at the PAST: today is ahead, so the chip crosses to the RIGHT
    // and its arrow turns around.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(tester.getRect(find.text(l[K.calToday])).left,
        greaterThan(
            tester.getRect(find.text(monthHeading(l, _monthBefore(today)))).right));
  });

  testWidgets('U-28 QA: the today chip keeps its distance from the arrows',
      (tester) async {
    // A chip a thumb's width from "next month" is a mis-tap waiting to happen,
    // and the two do opposite things.
    final l = Localization(AppLanguage.ptBr);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    final chip = tester.getRect(find.text(l[K.calToday]));
    final nextArrow = tester.getRect(find.byIcon(Icons.chevron_right));
    expect(nextArrow.left - chip.right, greaterThan(16),
        reason: 'the chip must not sit against the month arrow');
  });
}
