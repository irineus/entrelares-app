import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../deep_link_urls.dart';
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
import 'analytics_service.dart';
import 'custody_data_source.dart';

/// The real data source. Mirrors `CustodyService.cs`/`ProfileService.cs` reads
/// and the full-row write, plus the `SwapRequestService.cs` workflow (lote 3);
/// Realtime is NATIVE here — the F-29 JS bridge retires in this stack (the
/// F-23 poll survives as a safety net until the socket proves itself under
/// real load, owner decision 19/08/2026).
class SupabaseCustodyDataSource implements CustodyDataSource {
  final SupabaseClient _client;

  /// "[Dev] " on non-production flavors — leads every stored notification
  /// title (deploy marker, deliberately absent from `params`).
  final String environmentPrefix;

  /// T-37: optional by construction — the workflow must work with analytics
  /// off (dev flavor, tests), and an event may never change what is written.
  final AnalyticsService? analytics;

  SupabaseCustodyDataSource(this._client,
      {this.environmentPrefix = '', this.analytics});

  @override
  Future<List<Member>> fetchMembers() async {
    final rows = await _client.from('profiles').select();
    return rows.map(Member.fromJson).toList();
  }

  @override
  Future<Member?> fetchOwnProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? null : Member.fromJson(row);
  }

  @override
  Future<void> updateOwnLanguage(int profileId, String languageCode) async {
    await _client
        .from('profiles')
        .update({'language': languageCode}).eq('id', profileId);
  }

  @override
  Future<void> updateDetectedLanguage(
      int profileId, String languageCode) async {
    await _client
        .from('profiles')
        .update({'language_detected': languageCode}).eq('id', profileId);
  }

  @override
  Future<List<CareSchedule>> fetchMonth(int year, int month) async {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final rows = await _client
        .from('care_schedules')
        .select()
        .gte('schedule_date', CareSchedule.isoDate(first))
        .lte('schedule_date', CareSchedule.isoDate(last))
        .order('schedule_date', ascending: true);
    return rows.map(CareSchedule.fromJson).toList();
  }

  @override
  Future<List<CareSchedule>> fetchUpcoming(DateTime from, int days) async {
    final rows = await _client
        .from('care_schedules')
        .select()
        .gte('schedule_date', CareSchedule.isoDate(from))
        .lte('schedule_date',
            CareSchedule.isoDate(from.add(Duration(days: days))))
        .order('schedule_date', ascending: true);
    return rows.map(CareSchedule.fromJson).toList();
  }

  @override
  Future<Family?> fetchOwnFamily() async {
    // Same shape as the web's GetMyFamilyAsync: a plain RLS-scoped select,
    // first row or null — never the is_premium() RPC (the mirror exists so
    // no extra round-trip is needed).
    final rows = await _client.from('families').select().limit(1);
    return rows.isEmpty ? null : Family.fromJson(rows.first);
  }

  @override
  Future<Map<String, String>> fetchPublicSettings() async {
    final rows = await _client.from('app_settings').select('key, value');
    return {
      for (final row in rows)
        (row['key'] as String): (row['value'] as String? ?? ''),
    };
  }

  @override
  Future<Subscription?> fetchSubscription() async {
    // Fail closed like the web's GetSubscriptionAsync: a read that blows up
    // (RLS, offline, a shape we do not know) becomes "no subscription", which
    // sends the Premium section to the waitlist/offer — never to a management
    // panel for a row we could not confirm.
    try {
      final rows = await _client.from('subscriptions').select().limit(1);
      return rows.isEmpty ? null : Subscription.fromJson(rows.first);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<BillingHistoryEntry>> fetchBillingHistory() async {
    // Admin-only by DB rule; a non-admin never reaches here because the UI
    // does not offer the panel, and if it did the RPC would refuse.
    final data = await _client.rpc('get_billing_history');
    final rows = (data as List?) ?? const [];
    return rows
        .map((row) =>
            BillingHistoryEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> hasRegisteredPremiumInterest() async {
    final rows = await _client.from('premium_interest').select('id').limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<void> registerPremiumInterest({String? feature}) async {
    final tag = feature?.trim();
    await _client.rpc('register_premium_interest',
        params: tag == null || tag.isEmpty ? null : {'p_feature': tag});
  }

  @override
  Future<String> startCheckout(String cycle) =>
      _invokeBillingForUrl({'action': 'checkout', 'cycle': cycle});

  @override
  Future<String> startAvulso(String cycle) =>
      _invokeBillingForUrl({'action': 'avulso', 'cycle': cycle});

  @override
  Future<void> verifyStorePurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      await _client.functions.invoke('billing-store-verify', body: {
        'product_id': productId,
        'purchase_token': purchaseToken,
      });
    } on FunctionException catch (e) {
      throw BillingRefused(_functionErrorText(e));
    }
  }

  @override
  Future<void> cancelSubscription() => _invokeBilling({'action': 'cancel'});

  @override
  Future<void> reactivateSubscription() =>
      _invokeBilling({'action': 'reactivate'});

  /// The `billing-checkout` function, which owns every money action. Calls
  /// stay OUTSIDE any retry by construction (the web says it plainly: starting
  /// a checkout twice on a retry would create two payment links, and a retried
  /// reactivate would schedule two subscriptions).
  Future<void> _invokeBilling(Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke('billing-checkout', body: body);
    } on FunctionException catch (e) {
      throw BillingRefused(_functionErrorText(e));
    }
  }

  /// The checkout variants, which answer with a payment URL. A success with no
  /// `url` is a refusal too: sending the family nowhere is worse than saying
  /// the attempt failed.
  Future<String> _invokeBillingForUrl(Map<String, dynamic> body) async {
    try {
      final response =
          await _client.functions.invoke('billing-checkout', body: body);
      final data = response.data;
      if (data is Map && data['url'] is String) {
        final url = (data['url'] as String).trim();
        if (url.isNotEmpty) return url;
      }
      throw const BillingRefused();
    } on FunctionException catch (e) {
      throw BillingRefused(_functionErrorText(e));
    }
  }

  @override
  Future<CareSchedule?> fetchDay(DateTime date) async {
    final row = await _client
        .from('care_schedules')
        .select()
        .eq('schedule_date', CareSchedule.isoDate(date))
        .maybeSingle();
    return row == null ? null : CareSchedule.fromJson(row);
  }

  @override
  Future<void> insertDay(CareSchedule day) async {
    await _client.from('care_schedules').insert(day.toInsertJson());
  }

  @override
  Future<void> updateDay(CareSchedule day) async {
    await _client
        .from('care_schedules')
        .update(day.toUpdateJson())
        .eq('id', day.id);
  }

  @override
  Future<void> deleteDay(int id) async {
    await _client.from('care_schedules').delete().eq('id', id);
  }

  @override
  Future<int> bulkInsertNewDays(List<CareSchedule> days,
      {void Function(int percent)? onProgress}) async {
    if (days.isEmpty) return 0;
    final dates = days.map((d) => d.scheduleDate).toList()
      ..sort((a, b) => a.compareTo(b));
    final first = dates.first;
    final last = dates.last;

    Future<Set<String>> existingDates() async {
      final rows = await _client
          .from('care_schedules')
          .select('schedule_date')
          .gte('schedule_date', CareSchedule.isoDate(first))
          .lte('schedule_date', CareSchedule.isoDate(last));
      return {for (final r in rows) r['schedule_date'] as String};
    }

    final existing = await existingDates();
    onProgress?.call(20);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final toInsert = [
      for (final d in days)
        // Past days are immutable; already-assigned days are kept.
        if (!d.scheduleDate.isBefore(today) &&
            !existing.contains(CareSchedule.isoDate(d.scheduleDate)))
          d,
    ];
    onProgress?.call(30);
    if (toInsert.isEmpty) {
      onProgress?.call(100);
      return 0;
    }

    // T-33: another member may create one of these days between the check and
    // the batch INSERT — on the UNIQUE(family, date) collision, re-fetch,
    // drop the collided days and retry the remainder once (web mirror).
    Future<int> insertBatch(List<CareSchedule> batch) async {
      try {
        await _client
            .from('care_schedules')
            .insert([for (final d in batch) d.toInsertJson()]);
        return batch.length;
      } catch (e) {
        if (!isUniqueDayConflict(e.toString())) rethrow;
        final fresh = await existingDates();
        final remainder = [
          for (final d in batch)
            if (!fresh.contains(CareSchedule.isoDate(d.scheduleDate))) d,
        ];
        if (remainder.isEmpty) return 0;
        await _client
            .from('care_schedules')
            .insert([for (final d in remainder) d.toInsertJson()]);
        return remainder.length;
      }
    }

    const batchSize = 10;
    final totalBatches = (toInsert.length + batchSize - 1) ~/ batchSize;
    var inserted = 0;
    var batchesDone = 0;
    for (var i = 0; i < toInsert.length; i += batchSize) {
      final end =
          i + batchSize > toInsert.length ? toInsert.length : i + batchSize;
      inserted += await insertBatch(toInsert.sublist(i, end));
      batchesDone++;
      onProgress?.call(30 + (batchesDone * 70 ~/ totalBatches));
    }
    return inserted;
  }

  /// Channel topics must be unique per subscription — two subscribers on the
  /// same name would collide in the Realtime client.
  int _channelSeq = 0;

  void Function(RealtimeSubscribeStatus, Object?)? _statusCallback(
          void Function(bool connected)? onStatus) =>
      onStatus == null
          ? null
          : (status, _) =>
              onStatus(status == RealtimeSubscribeStatus.subscribed);

  @override
  Future<void Function()> watchChanges(void Function() onChange,
      {void Function(bool connected)? onStatus}) async {
    final channel = _client
        .channel('care_schedules_changes_${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'care_schedules',
          callback: (_) => onChange(),
        )
        .subscribe(_statusCallback(onStatus));
    return () => _client.removeChannel(channel);
  }

  // ── Lote 3: swap-approval workflow (mirror of SwapRequestService.cs) ──────

  static String _nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  @override
  Future<List<SwapRequest>> fetchFrozenRequestsForMonth(
      int year, int month) async {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);

    // NEVER shortcut a month for being in the past. An open request OUTLIVES
    // its day — that is the ATRASADO state the whole workflow models, and the
    // day-protection trigger exempts the request's target precisely so it can
    // still be completed. A guard here blanked a whole month the moment it
    // ended: the ⏳/🔔 badge, the frozen panel on tap and the resolve sheet's
    // count all come from this list, so a request pending across the turn of
    // the month became unapprovable and uncancellable from the calendar
    // (found in production on 01/09/2026, on a request for 31/08).
    //
    // Filter server-side: months with a long history hold many resolved
    // requests — only the open (frozen) ones matter here.
    final rows = await _client
        .from('swap_requests')
        .select()
        .gte('schedule_date', CareSchedule.isoDate(first))
        .lte('schedule_date', CareSchedule.isoDate(last))
        .inFilter('status', ['pending', 'revert_pending']);
    return rows.map(SwapRequest.fromJson).toList();
  }

  @override
  Future<List<SwapRequest>> fetchPendingForMe(int myProfileId) async {
    // Server-side filter: this backs the nav badge, so it must return only
    // the handful of open requests, not the full history.
    final rows = await _client
        .from('swap_requests')
        .select()
        .eq('target_profile_id', myProfileId)
        .inFilter('status', ['pending', 'revert_pending']).order('created_at',
            ascending: false, nullsFirst: false);
    return rows.map(SwapRequest.fromJson).toList();
  }

  @override
  Future<List<SwapRequest>> fetchSentRequests(int myProfileId) async {
    final rows = await _client
        .from('swap_requests')
        .select()
        .eq('requesting_profile_id', myProfileId)
        .order('created_at', ascending: false, nullsFirst: false)
        .limit(100);
    return rows.map(SwapRequest.fromJson).toList();
  }

  Future<SwapRequest> _fetchRequest(int id) async {
    final row =
        await _client.from('swap_requests').select().eq('id', id).maybeSingle();
    if (row == null) throw StateError('Solicitação não encontrada.');
    return SwapRequest.fromJson(row);
  }

  /// The revert links back to the swap it undoes: the most recently resolved
  /// approved request on that date.
  Future<SwapRequest?> _approvedRequestForDate(DateTime date) async {
    final rows = await _client
        .from('swap_requests')
        .select()
        .eq('schedule_date', CareSchedule.isoDate(date))
        .eq('status', 'approved')
        .order('resolved_at', ascending: false, nullsFirst: false)
        .limit(1);
    return rows.isEmpty ? null : SwapRequest.fromJson(rows.first);
  }

  /// The newest activity_logs row for a date is the one just written by the
  /// base-schedule upsert that precedes [createSwapRequest], so its old_data
  /// is the day's pre-edit snapshot (id is a monotonic identity).
  Future<int?> _latestLogIdForDate(DateTime date) async {
    final rows = await _client
        .from('activity_logs')
        .select('id')
        .eq('affected_date', CareSchedule.isoDate(date))
        .order('id', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<Object?> _fetchOldData(int logId) async {
    final row = await _client
        .from('activity_logs')
        .select('old_data')
        .eq('id', logId)
        .maybeSingle();
    return row?['old_data'];
  }

  /// Inserts the drafts WITHOUT representation (the SELECT policy restricts
  /// each user to their own notifications — returning the row inserted for
  /// the other parent would raise RLS 42501). Best-effort drafts (the F-28
  /// family fan-out) swallow their own failures.
  Future<void> _insertNotifications(
      List<NotificationDraft> drafts, int swapRequestId) async {
    for (final d in drafts) {
      final row = {
        'recipient_profile_id': d.recipientProfileId,
        'type': d.type,
        'title': d.title,
        'message': d.message,
        'params': d.params,
        'swap_request_id': swapRequestId,
        'is_read': false,
        'created_at': _nowUtcIso(),
      };
      if (d.bestEffort) {
        try {
          await _client.from('notifications').insert(row);
        } catch (_) {/* informational only */}
      } else {
        await _client.from('notifications').insert(row);
      }
    }
  }

  /// F-20: no urgency in the payload — the Edge Function computes the
  /// priority tag at SEND time from the request itself. Best-effort: e-mail
  /// failures never fail the workflow.
  Future<void> _sendSwapEmail(int swapRequestId, String emailType) async {
    try {
      await _client.functions.invoke('send-swap-email', body: {
        'swapRequestId': swapRequestId,
        'emailType': emailType,
        'environmentPrefix': environmentPrefix,
      });
    } catch (_) {/* best-effort */}
  }

  @override
  Future<void> createSwapRequest({
    required CareSchedule schedule,
    required int proposedActualParentId,
    String? proposedHandoffTime,
    String? requestMessage,
    required Member myProfile,
    required List<Member> allProfiles,
  }) async {
    final message = normalizeFreeText(requestMessage);

    // F-28: scenario-C gate — the DB does not hold this one (two-party
    // approval principle), so the mirror must refuse exactly like the web.
    if (!requesterParticipates(
        requesterId: myProfile.id,
        scheduledParentId: schedule.scheduledParentId,
        proposedActualParentId: proposedActualParentId)) {
      throw StateError(
          'Somente o responsável planejado do dia ou quem se propõe a assumir pode abrir a troca.');
    }

    // The approver is always the party that is NOT the requester.
    final approverId = myProfile.id == schedule.scheduledParentId
        ? proposedActualParentId
        : schedule.scheduledParentId;
    final target = allProfiles.where((p) => p.id == approverId).firstOrNull;
    if (target == null) {
      throw StateError('Perfil do responsável para aprovação não encontrado.');
    }

    // Tag at this instant — only for the point-in-time notification title;
    // display badges stay dynamic (F-20).
    final creationTag = computePriorityTag(
        schedule.scheduleDate, proposedHandoffTime, DateTime.now());

    // Snapshot reference (F-26): the base schedule was just upserted by the
    // caller, so the newest audit log for this date holds the pre-edit
    // old_data used to fully restore the day if this swap is later reverted.
    final preEditLogId = await _latestLogIdForDate(schedule.scheduleDate);

    final now = _nowUtcIso();
    final inserted = await _client
        .from('swap_requests')
        .insert({
          'schedule_date': CareSchedule.isoDate(schedule.scheduleDate),
          'schedule_id': schedule.id == 0 ? null : schedule.id,
          'requesting_profile_id': myProfile.id,
          'target_profile_id': approverId,
          'previous_actual_parent_id': schedule.actualParentId,
          'proposed_actual_parent_id': proposedActualParentId,
          'proposed_handoff_time': proposedHandoffTime,
          'status': 'pending',
          'request_message': message,
          'pre_edit_log_id': preEditLogId,
          'created_at': now,
          'updated_at': now,
        })
        .select('id')
        .single();
    final requestId = inserted['id'] as int;

    final drafts = composeSwapCreated(
      scheduleDate: schedule.scheduleDate,
      requesterId: myProfile.id,
      requesterName: myProfile.fullName,
      targetId: target.id,
      targetName: target.fullName,
      targetIsProposed: approverId == proposedActualParentId,
      creationTag: creationTag,
      requestMessage: message,
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, requestId);
    await _sendSwapEmail(requestId, 'swap_requested');

    // T-37: core-engagement signal (no PII — only the scenario). Fired AFTER
    // the workflow completed, and never awaited: analytics can neither delay
    // nor break a swap.
    unawaited(analytics?.trackEvent('swap_requested', props: {
          'scenario': approverId == proposedActualParentId ? 'A' : 'B',
        }) ??
        Future<void>.value());
  }

  @override
  Future<void> approveSwap(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);

    // Apply the change to care_schedules — full-row update so the T-33/T-35
    // echo travels with it.
    final scheduleId = request.scheduleId;
    if (scheduleId != null) {
      final row = await _client
          .from('care_schedules')
          .select()
          .eq('id', scheduleId)
          .maybeSingle();
      if (row != null) {
        final updated = CareSchedule.fromJson(row).copyWith(
          actualParentId: request.proposedActualParentId,
          handoffTime: request.proposedHandoffTime,
        );
        await _client
            .from('care_schedules')
            .update(updated.toUpdateJson())
            .eq('id', scheduleId);
      }
    }

    final note = normalizeFreeText(approvalNote); // F-44
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'approved',
      'approval_note': note,
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeSwapApproved(
      scheduleDate: request.scheduleDate,
      requestingProfileId: request.requestingProfileId,
      targetProfileId: request.targetProfileId,
      proposedActualParentId: request.proposedActualParentId,
      approvalNote: note,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'approved');
  }

  @override
  Future<void> rejectSwap(int swapRequestId,
      {String? reason, required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'rejected',
      'rejection_reason': reason,
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeSwapRejected(
      scheduleDate: request.scheduleDate,
      requestingProfileId: request.requestingProfileId,
      targetProfileId: request.targetProfileId,
      reason: reason,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'rejected');
  }

  @override
  Future<void> cancelSwap(int swapRequestId,
      {required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'cancelled',
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeSwapCancelled(
      scheduleDate: request.scheduleDate,
      targetProfileId: request.targetProfileId,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'cancelled');
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
    final message = normalizeFreeText(requestMessage);

    // The approver is always the party that is NOT the requester.
    final approverId = myProfile.id == scheduledParentId
        ? currentActualProfileId
        : scheduledParentId;
    final approver = allProfiles.where((p) => p.id == approverId).firstOrNull;
    if (approver == null) {
      throw StateError('Perfil do responsável para aprovação não encontrado.');
    }

    // Find the approved swap for this date to link back (F-26) and read the
    // day's current handoff time for the urgency tag.
    final approvedRequest = await _approvedRequestForDate(scheduleDate);
    String? currentHandoffTime;
    final approvedScheduleId = approvedRequest?.scheduleId;
    if (approvedScheduleId != null) {
      final row = await _client
          .from('care_schedules')
          .select('handoff_time')
          .eq('id', approvedScheduleId)
          .maybeSingle();
      currentHandoffTime = row?['handoff_time'] as String?;
    }

    final creationTag =
        computePriorityTag(scheduleDate, currentHandoffTime, DateTime.now());

    final now = _nowUtcIso();
    final inserted = await _client
        .from('swap_requests')
        .insert({
          'schedule_date': CareSchedule.isoDate(scheduleDate),
          'schedule_id': approvedRequest?.scheduleId,
          'requesting_profile_id': myProfile.id,
          'target_profile_id': approverId,
          'previous_actual_parent_id': currentActualProfileId,
          'proposed_actual_parent_id': scheduledParentId,
          'proposed_handoff_time': currentHandoffTime,
          'status': 'revert_pending',
          'request_message': message,
          // F-47: the requester's answer travels with the request — the
          // restore runs later and on the other side.
          'revert_notes': restoreNotes,
          'pre_edit_log_id': approvedRequest?.preEditLogId,
          'created_at': now,
          'updated_at': now,
        })
        .select('id')
        .single();
    final requestId = inserted['id'] as int;

    final drafts = composeRevertRequested(
      scheduleDate: scheduleDate,
      requesterId: myProfile.id,
      requesterName: myProfile.fullName,
      approverId: approver.id,
      approverName: approver.fullName,
      creationTag: creationTag,
      requestMessage: message,
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, requestId);
    await _sendSwapEmail(requestId, 'revert_requested');
  }

  /// Restores the day to the full snapshot captured before the swap edit
  /// (F-26). The branching is the pure [revertRestorePlan]; this only
  /// executes it.
  Future<void> _restorePreEditState(SwapRequest request) async {
    final scheduleId = request.scheduleId;
    if (scheduleId == null) return;
    final row = await _client
        .from('care_schedules')
        .select()
        .eq('id', scheduleId)
        .maybeSingle();
    if (row == null) return;
    final schedule = CareSchedule.fromJson(row);

    final preEditLogId = request.preEditLogId;
    final oldData =
        preEditLogId == null ? null : await _fetchOldData(preEditLogId);
    final plan = revertRestorePlan(
      hasPreEditLogId: preEditLogId != null,
      oldData: oldData,
      revertNotes: request.revertNotes,
    );

    switch (plan) {
      case RevertClearActualOnly():
        final updated = schedule.copyWith(actualParentId: null);
        await _client
            .from('care_schedules')
            .update(updated.toUpdateJson())
            .eq('id', scheduleId);
      case RevertDeleteDay():
        await _client.from('care_schedules').delete().eq('id', scheduleId);
      case RevertRestoreFields():
        final updated = schedule.copyWith(
          scheduledParentId:
              plan.scheduledParentId ?? schedule.scheduledParentId,
          actualParentId: plan.actualParentId,
          handoffTime: plan.handoffTime,
          notes: plan.restoreNotes ? plan.notes : schedule.notes,
        );
        await _client
            .from('care_schedules')
            .update(updated.toUpdateJson())
            .eq('id', scheduleId);
    }
  }

  @override
  Future<void> approveRevert(int swapRequestId,
      {String? approvalNote, required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);

    if (request.scheduleId != null) {
      await _restorePreEditState(request);
    }

    final note = normalizeFreeText(approvalNote); // F-44
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'revert_approved',
      'approval_note': note,
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeRevertApproved(
      scheduleDate: request.scheduleDate,
      requestingProfileId: request.requestingProfileId,
      targetProfileId: request.targetProfileId,
      proposedActualParentId: request.proposedActualParentId,
      approvalNote: note,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'revert_approved');
  }

  @override
  Future<void> rejectRevert(int swapRequestId,
      {String? reason, required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'revert_rejected',
      'rejection_reason': reason,
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeRevertRejected(
      scheduleDate: request.scheduleDate,
      requestingProfileId: request.requestingProfileId,
      targetProfileId: request.targetProfileId,
      reason: reason,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'revert_rejected');
  }

  @override
  Future<void> cancelRevert(int swapRequestId,
      {required List<Member> allProfiles}) async {
    final request = await _fetchRequest(swapRequestId);
    final now = _nowUtcIso();
    await _client.from('swap_requests').update({
      'status': 'revert_cancelled',
      'resolved_at': now,
      'updated_at': now,
    }).eq('id', swapRequestId);

    final drafts = composeRevertCancelled(
      scheduleDate: request.scheduleDate,
      targetProfileId: request.targetProfileId,
      allProfiles: [for (final p in allProfiles) p.toView()],
      environmentPrefix: environmentPrefix,
    );
    await _insertNotifications(drafts, swapRequestId);
    await _sendSwapEmail(swapRequestId, 'revert_cancelled');
  }

  @override
  Future<PreEditNotes?> fetchPreEditNotes(DateTime scheduleDate) async {
    final approvedRequest = await _approvedRequestForDate(scheduleDate);
    final preEditLogId = approvedRequest?.preEditLogId;
    if (preEditLogId == null) return null;
    final snapshot = PreEditSnapshot.parse(await _fetchOldData(preEditLogId));
    if (snapshot == null) return null;
    return PreEditNotes(snapshot.notes);
  }

  @override
  Future<List<AppNotification>> fetchNotifications(int myProfileId) async {
    // Newest 100 — the history tab is a recent-activity view (web parity).
    final rows = await _client
        .from('notifications')
        .select()
        .eq('recipient_profile_id', myProfileId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromJson).toList();
  }

  @override
  Future<void> markAllNotificationsRead(int myProfileId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_profile_id', myProfileId)
        .eq('is_read', false);
  }

  @override
  Future<void> registerPushToken({
    required int myProfileId,
    required String token,
    required String platform,
    String? deviceLabel,
  }) async {
    // `onConflict: 'token'` and not the primary key: the UNIQUE constraint is
    // on the token, and the row that already holds it may belong to another
    // profile (the same phone, a different sign-in). Upserting re-points it,
    // which is exactly what must happen — the alternative is a 23505 the caller
    // would have to interpret, or a stale row still receiving the previous
    // account's notices.
    //
    // The re-point across profiles is the DATABASE's, not this statement's: a
    // `DO UPDATE` over someone else's row is refused by RLS, correctly, and for
    // a whole day in production it was. The `push_subscriptions_claim_token`
    // trigger clears the previous holder before the INSERT, so this call never
    // reaches the UPDATE branch unless the row is already yours.
    await _client.from('push_subscriptions').upsert({
      'profile_id': myProfileId,
      'token': token,
      'platform': platform,
      'device_label': ?deviceLabel,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  @override
  Future<void> deletePushToken(String token) async {
    await _client.from('push_subscriptions').delete().eq('token', token);
  }

  @override
  Future<bool> isDeviceRegistered({
    required int myProfileId,
    required String token,
  }) async {
    // Both columns, though RLS already hides another profile's row: a filter
    // that only works because a policy is doing half of it breaks the day the
    // policy is read as redundant and simplified away.
    final rows = await _client
        .from('push_subscriptions')
        .select('id')
        .eq('profile_id', myProfileId)
        .eq('token', token)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<void Function()> watchWorkflowChanges(void Function() onChange,
      {void Function(bool connected)? onStatus}) async {
    final channel = _client
        .channel('workflow_changes_${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'swap_requests',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => onChange(),
        )
        .subscribe(_statusCallback(onStatus));
    return () => _client.removeChannel(channel);
  }

  // ── Lote 4: sudo elevation (S-10) ─────────────────────────────────────────

  @override
  Future<String?> elevate(String password) async {
    // Pilot QA round 2 (console): a STALE access token makes `elevate` answer
    // 401 no matter how right the password is, and the user reads "senha
    // incorreta" while typing the correct one. Refresh first, best-effort —
    // if the refresh itself fails the call below reports the real problem.
    try {
      await _client.auth.refreshSession();
    } catch (_) {/* the invoke below surfaces a dead session honestly */}

    try {
      final response = await _client.functions
          .invoke('elevate', body: {'password': password});
      final data = response.data;
      if (data is Map && data['elevated_until'] is String) {
        return data['elevated_until'] as String;
      }
      return null;
    } on FunctionException catch (e) {
      throw ElevationRefused(
        // Pilot lesson 4: the function's own PT-BR text, never a guess.
        serverMessage: _functionErrorText(e),
        wrongPassword: e.status == 401,
        rateLimited: e.status == 429,
      );
    }
  }

  // ── Lote 4: sign-up and invitations ───────────────────────────────────────

  @override
  Future<InviteInfo?> fetchInviteInfo(String token) async {
    // A malformed token is answered here: sending it would make the RPC fail
    // on the uuid cast instead of answering "not valid", and the screen wants
    // the same dead end for every unusable token.
    if (!InviteFormRules.isTokenShaped(token)) return null;
    try {
      final data =
          await _client.rpc('get_invite_info', params: {'p_token': token});
      // The RPC returns SETOF — PostgREST hands back a list or a bare object
      // depending on the shape; tolerate both, as the web does.
      final row = data is List ? (data.isEmpty ? null : data.first) : data;
      if (row is! Map) return null;
      return InviteInfo.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      // An unusable token must look identical to an unreachable server here:
      // the screen shows "this invitation is not valid" either way.
      return null;
    }
  }

  @override
  Future<void> signUpFounder({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String familyName,
    required String languageCode,
  }) async {
    final AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: DeepLinkUrls.login,
        // Everything `handle_new_user` needs to build family + profile in ONE
        // transaction. `policy_version` is the S-13 evidence of what was
        // accepted; `language` is what the confirmation e-mail is written in.
        data: {
          'full_name': fullName,
          'role': role,
          'invite_token': '',
          'family_name': familyName,
          'policy_version': PolicyVersions.current,
          'language': languageCode,
        },
      );
    } on AuthException catch (e) {
      throw SignUpFailure(RegisterRules.signUpErrorKey(e.message));
    } catch (_) {
      throw const SignUpFailure(K.authErrConnection);
    }

    if (RegisterRules.isSilentDuplicate(
        hasUser: response.user != null,
        identityCount: response.user?.identities?.length ?? 0)) {
      throw const SignUpFailure(K.authErrAlreadyRegistered);
    }
  }

  @override
  Future<InviteeResult> registerInvitee({
    required String token,
    required String fullName,
    required String password,
    bool confirmMigration = false,
  }) async {
    try {
      await _client.functions.invoke('register-invitee', body: {
        'token': token,
        'fullName': fullName,
        'password': password,
        'confirmMigration': confirmMigration,
        'policyVersion': PolicyVersions.current,
      });
      return const InviteeRegistered();
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        // S-11: not a failure — a question the visitor must answer.
        if (details['needsMigration'] == true) {
          return InviteeNeedsMigration(
              details['previousFamilyName'] as String?);
        }
      }
      return InviteeFailed(_functionErrorText(e));
    } catch (_) {
      return const InviteeFailed(null);
    }
  }

  // ── F-57: social-login onboarding (deferred profile) ─────────────────────

  @override
  Future<void> completeOauthOnboarding({
    required String fullName,
    required String role,
    required String familyName,
  }) async {
    try {
      await _client.rpc<void>('complete_oauth_onboarding', params: {
        'p_full_name': fullName,
        'p_role': role,
        'p_family_name': familyName,
        // S-13/S-15: the version the consent checkbox referred to — the RPC
        // refuses a mismatch, so a stale client can never stamp a consent it
        // did not display.
        'p_policy_version': PolicyVersions.current,
      });
    } on PostgrestException catch (e) {
      // The RPC's refusals are PT-BR user text by design — propagate the
      // server's own words (pilot lesson 4), never collapse them.
      throw OnboardingRefused(e.message);
    } catch (_) {
      throw const OnboardingRefused(null);
    }
  }

  @override
  Future<InviteeResult> claimInvitation({
    required String token,
    required String fullName,
    bool confirmMigration = false,
  }) async {
    try {
      await _client.functions.invoke('claim-invitation', body: {
        'token': token,
        'fullName': fullName,
        'confirmMigration': confirmMigration,
        'policyVersion': PolicyVersions.current,
      });
      return const InviteeRegistered();
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        // S-11: not a failure — a question the visitor must answer.
        if (details['needsMigration'] == true) {
          return InviteeNeedsMigration(
              details['previousFamilyName'] as String?);
        }
      }
      return InviteeFailed(_functionErrorText(e));
    } catch (_) {
      return const InviteeFailed(null);
    }
  }

  @override
  List<String> authProviders() {
    final providers = _client.auth.currentUser?.appMetadata['providers'];
    return providers is List
        ? providers.whereType<String>().toList()
        : const [];
  }

  @override
  String? sessionEmail() {
    final email = _client.auth.currentUser?.email?.trim();
    return (email == null || email.isEmpty) ? null : email;
  }

  @override
  String? sessionDisplayName() {
    final meta = _client.auth.currentUser?.userMetadata;
    // Google sends `full_name` AND `name`; our own sign-ups set `full_name`.
    final name = (meta?['full_name'] ?? meta?['name']);
    if (name is! String) return null;
    final trimmed = name.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ── Lote 4: family page, invitations and custom roles (F-41) ─────────────

  @override
  Future<List<Role>> fetchRoles() async {
    final rows = await _client.from('roles').select().order('id');
    return rows.map(Role.fromJson).toList();
  }

  @override
  Future<void> renameFamily(String name) async {
    await _client.rpc('rename_family', params: {'p_name': name.trim()});
  }

  @override
  Future<List<FamilyInvitation>> fetchOpenInvitations() async {
    final rows = await _client
        .from('family_invitations')
        .select()
        .isFilter('accepted_at', null)
        .isFilter('revoked_at', null)
        .order('created_at', ascending: true);
    return rows.map(FamilyInvitation.fromJson).toList();
  }

  @override
  Future<int> createInvitation({
    required String email,
    required int roleId,
    int? profileId,
  }) async {
    final data = await _client.rpc('create_invitation', params: {
      'p_email': email.trim(),
      'p_role_id': roleId,
      'p_profile_id': ?profileId,
    });
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    return row is Map ? (row['invitation_id'] as int? ?? 0) : 0;
  }

  @override
  Future<({int profileId, int? invitationId})> addPendingMember({
    required String fullName,
    required int roleId,
    String? email,
  }) async {
    final clean = email?.trim() ?? '';
    final data = await _client.rpc('add_pending_member', params: {
      'p_full_name': fullName.trim(),
      'p_role_id': roleId,
      if (clean.isNotEmpty) 'p_email': clean,
    });
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    if (row is! Map) {
      throw StateError('add_pending_member returned no row: $data');
    }
    return (
      profileId: row['profile_id'] as int,
      invitationId: row['invitation_id'] as int?,
    );
  }

  @override
  Future<void> removePendingMember(int profileId) async {
    await _client
        .rpc('remove_pending_member', params: {'p_profile_id': profileId});
  }

  @override
  Future<void> revokeInvitation(int invitationId) async {
    await _client
        .rpc('revoke_invitation', params: {'p_invitation_id': invitationId});
  }

  @override
  Future<bool> sendInvitationEmail(int invitationId) async {
    try {
      await _client.functions.invoke('send-swap-email', body: {
        'emailType': 'invitation',
        'invitationId': invitationId,
        'environmentPrefix': environmentPrefix,
      });
      return true;
    } catch (_) {
      // The invitation exists regardless; the page falls back to the link.
      return false;
    }
  }

  @override
  Future<void> createCustomRole({required String label, String? emoji}) async {
    final params = <String, dynamic>{'p_label': label.trim()};
    // Omitted rather than blank: the RPC's default is NULL, and sending an
    // empty string would store one.
    final clean = (emoji ?? '').trim();
    if (clean.isNotEmpty) params['p_emoji'] = clean;
    await _client.rpc('create_custom_role', params: params);
  }

  @override
  Future<void> updateCustomRole(
      {required int roleId, required String label, String? emoji}) async {
    final params = <String, dynamic>{
      'p_role_id': roleId,
      'p_label': label.trim(),
    };
    // Same shape as create — and here the omission is what CLEARS an emoji.
    final clean = (emoji ?? '').trim();
    if (clean.isNotEmpty) params['p_emoji'] = clean;
    await _client.rpc('update_custom_role', params: params);
  }

  @override
  Future<void> deleteCustomRole(int roleId) async {
    await _client.rpc('delete_custom_role', params: {'p_role_id': roleId});
  }

  // ── Lote 4: profile, account and the LGPD export ─────────────────────────

  @override
  Future<void> updateOwnName(int profileId, String fullName) async {
    await _client
        .from('profiles')
        .update({'full_name': fullName.trim()}).eq('id', profileId);
  }

  @override
  Future<void> updateMemberName(int profileId, String fullName) async {
    await _client.rpc('update_member_name',
        params: {'p_profile_id': profileId, 'p_full_name': fullName.trim()});
  }

  @override
  Future<void> setMemberRole(
      {required int profileId, required int roleId}) async {
    await _client.rpc('set_member_role',
        params: {'p_profile_id': profileId, 'p_role_id': roleId});
  }

  @override
  Future<void> setMemberAdmin(
      {required int profileId, required bool isAdmin}) async {
    // Raises `ELEVATION_REQUIRED:` without a live sudo window — the caller
    // wraps this in runWithSudo, which retries once after the prompt.
    await _client.rpc('set_member_admin',
        params: {'p_profile_id': profileId, 'p_is_admin': isAdmin});
  }

  @override
  Future<void> sendPasswordReset(String email, AppLanguage language) async {
    await _client.auth.resetPasswordForEmail(email.trim(),
        redirectTo: DeepLinkUrls.updatePasswordFor(language));
  }

  @override
  Future<void> updateOwnEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email.trim()),
        emailRedirectTo: DeepLinkUrls.login);
  }

  @override
  Future<void> updateOwnPassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> logAccountAction(String action) async {
    await _client.rpc('log_account_action', params: {'p_action': action});
  }

  @override
  Future<ExportBundle> fetchExportData(int myProfileId) async {
    // All four reads are RLS-scoped: the export can only ever contain what
    // this member is already allowed to see in the app.
    final results = await Future.wait([
      _client.from('care_schedules').select().order('schedule_date'),
      _client.from('swap_requests').select().order('created_at'),
      _client
          .from('notifications')
          .select()
          .eq('recipient_profile_id', myProfileId)
          .order('created_at'),
      _client.from('activity_logs').select().order('created_at'),
    ]);
    return ExportBundle(
      schedules: (results[0]).map(CareSchedule.fromJson).toList(),
      swapRequests: (results[1]).map(SwapRequest.fromJson).toList(),
      notifications: (results[2]).map(AppNotification.fromJson).toList(),
      activityLog: (results[3]).map(Map<String, dynamic>.from).toList(),
    );
  }

  // ── Lote 4: leaving, family deletion (S-11) and re-consent (S-15) ────────

  @override
  Future<PendingFamilyDeletion?> fetchPendingFamilyDeletion() async {
    final rows = await _client
        .from('family_deletion_requests')
        .select()
        .eq('status', 'pending')
        .limit(1);
    if (rows.isEmpty) return null;
    final request = FamilyDeletionRequest.fromJson(rows.first);
    final answers = await _client
        .from('family_deletion_responses')
        .select()
        .eq('request_id', request.id);
    return PendingFamilyDeletion(
        request, answers.map(FamilyDeletionResponse.fromJson).toList());
  }

  @override
  Future<void> requestFamilyDeletion() async {
    await _client.rpc('request_family_deletion');
  }

  @override
  Future<void> respondFamilyDeletion(bool? agree) async {
    // A null answer DELETES my row server-side — "aguardando" is the absence
    // of a response, not a third value.
    await _client.rpc('respond_family_deletion', params: {'p_agree': agree});
  }

  @override
  Future<void> withdrawFamilyDeletion() async {
    await _client.rpc('withdraw_family_deletion');
  }

  @override
  Future<void> executeFamilyDeletion() async {
    await _client.rpc('execute_family_deletion');
  }

  @override
  Future<void> purgeNow() async {
    try {
      await _client.functions.invoke('purge-deleted');
    } catch (_) {
      // The row is already scheduled for now; the cron finishes the job.
    }
  }

  @override
  Future<void> requestAccountDeletion({int? successorProfileId}) async {
    final params = <String, dynamic>{};
    // Omitted rather than null: the RPC's own default decides whether a
    // successor is even required.
    if (successorProfileId != null) {
      params['p_new_admin_id'] = successorProfileId;
    }
    await _client.rpc('request_account_deletion', params: params);
  }

  @override
  Future<void> cancelAccountDeletion() async {
    await _client.rpc('cancel_account_deletion');
  }

  @override
  Future<void> sendAccountEmail(String emailType, {int? profileId}) async {
    try {
      await _client.functions.invoke('send-account-email', body: {
        'emailType': emailType,
        'profileId': ?profileId,
        'environmentPrefix': environmentPrefix,
      });
    } catch (_) {/* best-effort, as in the web */}
  }

  @override
  Future<void> acceptCurrentPolicy() async {
    await _client.rpc('accept_current_policy',
        params: {'p_version': PolicyVersions.current});
  }

  // ── Lote 4: first-run onboarding (U-23) ──────────────────────────────────

  @override
  Future<bool> hasOpenInvitation() async {
    final rows = await _client
        .from('family_invitations')
        .select('id')
        .isFilter('accepted_at', null)
        .isFilter('revoked_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<OnboardingFacts> fetchOnboardingFacts({
    required int myProfileId,
    bool includeSwapParticipation = true,
  }) async {
    // Both reads are `limit(1)`: the question is existence, never a count.
    final planned =
        await _client.from('care_schedules').select('id').limit(1);
    if (!includeSwapParticipation) {
      return OnboardingFacts(hasAnyPlannedDay: planned.isNotEmpty);
    }
    final asRequester = await _client
        .from('swap_requests')
        .select('id')
        .eq('requesting_profile_id', myProfileId)
        .limit(1);
    final asTarget = asRequester.isNotEmpty
        ? const []
        : await _client
            .from('swap_requests')
            .select('id')
            .eq('target_profile_id', myProfileId)
            .limit(1);
    return OnboardingFacts(
      hasAnyPlannedDay: planned.isNotEmpty,
      hasTakenPartInASwap: asRequester.isNotEmpty || asTarget.isNotEmpty,
    );
  }

  @override
  Future<void> stampOnboarding(OnboardingStamp stamp) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    // Idempotent by filter: only an unstamped row is written, so the first
    // date survives.
    await _client
        .from('profiles')
        .update({stamp.column: DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .isFilter(stamp.column, null);
  }

  @override
  Future<void> clearChecklistDismissal() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('profiles')
        .update({OnboardingStamp.dismissed.column: null}).eq('user_id', uid);
  }

  // ── Lote 6: reports (audit trail reads) ───────────────────────────────────

  @override
  Future<List<CareSchedule>> fetchSchedulesForPeriod(
      DateTime start, DateTime end) async {
    final rows = await _client
        .from('care_schedules')
        .select()
        .gte('schedule_date', CareSchedule.isoDate(start))
        .lte('schedule_date', CareSchedule.isoDate(end))
        .order('schedule_date');
    return rows.map(CareSchedule.fromJson).toList();
  }

  @override
  Future<List<ActivityLog>> fetchRecentActivityLogs({int offset = 0}) async {
    final rows = await _client
        .from('activity_logs')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + auditPageSize - 1);
    return rows.map(ActivityLog.fromJson).toList();
  }

  @override
  Future<List<ActivityLog>> fetchActivityLogsForPeriod(
      DateTime start, DateTime end) async {
    // The web filters on `affected_date` — the DAY the change is about, not
    // when it was made — and orders newest-first for the timeline; the F-33
    // document re-sorts oldest-first in core.
    final rows = await _client
        .from('activity_logs')
        .select()
        .gte('affected_date', CareSchedule.isoDate(start))
        .lte('affected_date', CareSchedule.isoDate(end))
        .order('created_at', ascending: false);
    return rows.map(ActivityLog.fromJson).toList();
  }

  @override
  Future<List<AccountLog>> fetchAccountLogs({int offset = 0}) async {
    final rows = await _client
        .from('account_logs')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + auditPageSize - 1);
    return rows.map(AccountLog.fromJson).toList();
  }

  @override
  Future<Map<int, SwapOrigin>> fetchResolutionOrigins(List<int> logIds) async {
    if (logIds.isEmpty) return const {};
    final rows = await _client
        .from('swap_requests')
        .select()
        .inFilter('resolution_log_id', logIds);

    final origins = <int, SwapOrigin>{};
    for (final row in rows) {
      final request = SwapRequest.fromJson(row);
      final logId = request.resolutionLogId;
      // First wins, as the web's GroupBy().First() does — one log can only
      // have been produced by one resolution.
      if (logId != null && !origins.containsKey(logId)) {
        origins[logId] = SwapOrigin(
          requestingProfileId: request.requestingProfileId,
          targetProfileId: request.targetProfileId,
          status: request.status,
          resolvedBy: request.resolvedBy,
          requestMessage: request.requestMessage,
          approvalNote: request.approvalNote,
        );
      }
    }
    return origins;
  }

  /// The `error` field an Edge Function puts in its body, when there is one.
  static String? _functionErrorText(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      final text = (details['error'] as String).trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
