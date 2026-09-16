import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// T-31 Suite C — F-24 auto-approval. The Edge Function is a thin wrapper over
/// the `auto_approve_expired()` RPC, which is the real logic, so these call the
/// RPC directly through the service client: deterministic, no e-mails, no
/// waiting on a clock.
///
/// Requests are seeded with a BACKDATED `schedule_date` so their handoff expiry
/// is a controlled number of hours in the past — the system context bypasses the
/// day-protection trigger, which is what makes seeding a past day possible at
/// all.
///
/// Port of `db-gate/Entrelares.IntegrationTests/AutoApprovalTests.cs`.
void autoApprovalTests(GateFixture fx) {
  /// The RPC computes expiry as `schedule_date + handoff` in
  /// `America/Sao_Paulo` (fixed UTC-3). Build a date/handoff pair whose expiry
  /// is [hoursAgo] in the past, so the seed lands precisely in the reminder
  /// (24–48 h) or auto-approve (>48 h) window whatever the wall clock says.
  (DateTime date, String handoff) expiryAt(double hoursAgo) {
    final sp = DateTime.now()
        .toUtc()
        .subtract(Duration(minutes: (3 * 60 + hoursAgo * 60).round()));
    return (DateTime(sp.year, sp.month, sp.day), isoTime(sp));
  }

  Future<int> seedPendingSwap({required double expiryHoursAgo}) async {
    final (date, handoff) = expiryAt(expiryHoursAgo);

    final schedule = CareSchedule.fromJson((await fx.service
            .from('care_schedules')
            .insert({
              'schedule_date': isoDate(date),
              'scheduled_parent_id': fx.founderProfile.id,
            })
            .select())
        .single);

    final request = SwapRequest.fromJson((await fx.service
            .from('swap_requests')
            .insert({
              'schedule_date': isoDate(date),
              'schedule_id': schedule.id,
              'requesting_profile_id': fx.memberProfile.id,
              'target_profile_id': fx.founderProfile.id,
              'previous_actual_parent_id': null,
              'proposed_actual_parent_id': fx.memberProfile.id,
              'proposed_handoff_time': handoff,
              'status': 'pending',
            })
            .select())
        .single);

    return request.id;
  }

  Future<void> runAutoApproval() => fx.service
      .rpc<dynamic>('auto_approve_expired', params: {'p_env_prefix': '[Dev] '});

  Future<SwapRequest> reload(int id) async => SwapRequest.fromJson(
      (await fx.service.from('swap_requests').select().eq('id', id)).single);

  group('AutoApprovalTests', () {
    test('a request expired past 48 h is auto-approved as the system', () async {
      final requestId = await seedPendingSwap(expiryHoursAgo: 60);

      await runAutoApproval();

      final request = await reload(requestId);
      expect(request.status, 'approved');
      expect(request.resolvedBy, 'system');

      // And the calendar change is applied, exactly like a manual approval.
      final schedule = CareSchedule.fromJson((await fx.service
              .from('care_schedules')
              .select()
              .eq('id', request.scheduleId!))
          .single);
      expect(schedule.actualParentId, fx.memberProfile.id);
    });

    test('a request expired between 24 h and 48 h gets a reminder, not approval',
        () async {
      final requestId = await seedPendingSwap(expiryHoursAgo: 36);

      await runAutoApproval();

      final request = await reload(requestId);
      expect(request.status, 'pending');
      expect(request.reminderSentAt, isNotNull);

      // U-13: the reminder's render payload is asserted HERE rather than in the
      // notification-params suite. The reminder only fires 24–48 h before now, a
      // window barely two calendar days wide that this suite's 36 h and 60 h
      // cases already occupy — a second suite adding its own seed there lands
      // within 24 h of one of them and collides on
      // (family_id, schedule_date). Asserting on an existing seed is the only
      // stable place for it.
      final reminder = AppNotification.fromJson((await fx.service
              .from('notifications')
              .select()
              .eq('swap_request_id', requestId)
              .eq('type', 'auto_reminder'))
          .single);

      expect(reminder.paramsJson, isNotNull,
          reason: 'the reminder was written without params — '
              'the client cannot localize it');
      // U-24: `params.date` is ISO 8601, NOT a formatted date. That is the whole
      // point — the reader's device decides how the day is written, so an
      // English reader is not shown `05/08` and told the wrong month. The PT-BR
      // sentence in `message` keeps its own format, as the fallback record of
      // what was sent.
      expect(reminder.paramsJson, contains(isoDate(request.scheduleDate)));

      // F-60: and it carries the INSTANT it will be approved at — the day's
      // expiry plus 48 h, as a `YYYY-MM-DDTHH:MM` wall clock of
      // America/Sao_Paulo. Without it the client renders the sentence with no
      // deadline at all, which is the pre-F-60 copy minus its wrong number.
      final expiry = DateTime(
        request.scheduleDate.year,
        request.scheduleDate.month,
        request.scheduleDate.day,
        int.parse(request.proposedHandoffTime!.substring(0, 2)),
        int.parse(request.proposedHandoffTime!.substring(3, 5)),
      );
      final deadline = expiry.add(const Duration(hours: 48));
      final expected = '${isoDate(deadline)}T'
          '${deadline.hour.toString().padLeft(2, '0')}:'
          '${deadline.minute.toString().padLeft(2, '0')}';
      expect(reminder.paramsJson, contains('"deadline":"$expected"'),
          reason: 'the reminder must name the instant it promises, not a '
              'window measured from the request (F-60)');

      // The stored PT-BR sentence is the fallback record, and it says the same
      // instant — a reader whose row predates the client update must not be
      // told a number that was never true.
      expect(reminder.message, contains(' será aprovada automaticamente em '));
      for (final window in ['24h', '48h', '24 horas', '48 horas']) {
        expect(reminder.message, isNot(contains(window)),
            reason: 'the reminder quotes a window again');
      }
    });

    test('auto-approval fans out to the uninvolved caregiver', () async {
      // F-28: requester = member, target = founder, so the third caregiver is
      // uninvolved and gets an explicit-name family-info message.
      final third = await fx.ensureThirdMember();
      // 84 h, not 60 h: a full day away from the case above, so the backdated
      // schedule_date never collides on UNIQUE (family_id, schedule_date).
      final requestId = await seedPendingSwap(expiryHoursAgo: 84);

      await runAutoApproval();

      final info = AppNotification.fromJson((await fx.service
              .from('notifications')
              .select()
              .eq('swap_request_id', requestId)
              .eq('type', 'swap_family_info'))
          .single);

      expect(info.recipientProfileId, third.id);
      // Explicit name — the day lands on the proposed parent (the member).
      expect(info.message, contains(fx.memberProfile.fullName));
    });
  });
}
