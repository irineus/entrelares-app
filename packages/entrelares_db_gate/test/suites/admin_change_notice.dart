import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-81 — an admin's DIRECT change of a day tells the caregivers it affects:
/// ONE `day_admin_change` notification per action and recipient, written at
/// COMMIT by `flush_admin_change_notices()` from what
/// `stage_admin_change_notice()` queued for the transaction.
///
/// What only the database can prove:
///   · WHO — the day's planned and real carer before and after the write,
///     with an account, active, not a viewer and not the actor; an uninvolved
///     caregiver, a pending member and one who left hear nothing;
///   · WHICH writes — an admin's, outside the two-party workflow: a member's
///     own edit and a target applying an approval write no such row;
///   · ONE PER ACTION — a range RPC (clear month, wizard replace, handoff
///     range) and a multi-row request each write ONE row per recipient, with
///     the period and the count, never one per day;
///   · nothing about another family, and a queue no client can read.
///
/// Every scenario runs in throwaway families: the shared family's members
/// would otherwise collect notices under every other suite's day edits.
void adminChangeNoticeTests(GateFixture fx) {
  const type = 'day_admin_change';
  const viewersFlag = 'feature.viewers';
  final today = saoPauloToday();

  late ThrowawayFamily fam;
  late Member third;
  late Member viewerProfile;
  late int pending;

  Future<Member> profileByEmail(int familyId, String email) async =>
      Member.fromJson(
        (await fx.service
                .from('profiles')
                .select()
                .eq('family_id', familyId)
                .eq('email', email.toLowerCase())
                .limit(1))
            .single,
      );

  Future<Member> inviteCaregiver(ThrowawayFamily f, String tag) async {
    final email = fx.testEmail(tag);
    final token = await GateFixture.createInvitation(
      f.admin,
      email,
      fx.roleId('grandmother'),
    );
    await fx.createInvitedUser(email, token, fullName: 'E2E F81 $tag');
    return profileByEmail(f.familyId, email);
  }

  /// A day written by the SERVICE: no actor, so seeding never notifies.
  Future<CareSchedule> seed(
    ThrowawayFamily f,
    int plannedId,
    DateTime date, {
    int? actualId,
  }) async => CareSchedule.fromJson(
    (await fx.service.from('care_schedules').insert({
      'schedule_date': isoDate(date),
      'scheduled_parent_id': plannedId,
      'actual_parent_id': ?actualId,
      'family_id': f.familyId,
    }).select()).single,
  );

  /// Every `day_admin_change` row [profileId] has, oldest first.
  Future<List<AppNotification>> noticesOf(int profileId) async => [
    for (final row
        in await fx.service
            .from('notifications')
            .select()
            .eq('recipient_profile_id', profileId)
            .eq('type', type)
            .order('id', ascending: true))
      AppNotification.fromJson(row),
  ];

  /// The rows [action] added for each of [who], by profile id.
  Future<Map<int, List<AppNotification>>> added(
    List<int> who,
    Future<void> Function() action,
  ) async {
    final before = {for (final id in who) id: (await noticesOf(id)).length};
    await action();
    return {
      for (final id in who) id: (await noticesOf(id)).sublist(before[id]!),
    };
  }

  String br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  group('F-81 · admin change notice', () {
    setUpAll(() async {
      fam = await fx.createFamily('f81-a');
      await fx.service.rpc<dynamic>(
        'set_family_plan',
        params: {'p_family_id': fam.familyId, 'p_plan': 'premium'},
      );

      // The fourth seat (premium caps caregivers at 4, pending included) goes
      // to the placeholder; the third caregiver is also the one who LEAVES,
      // later — after leaving it is still an uninvolved profile.
      third = await inviteCaregiver(fam, 'f81-third');

      final row = await fam.admin.rpc<dynamic>(
        'add_pending_member',
        params: {
          'p_full_name': 'E2E F81 Pending',
          'p_role_id': fx.roleId('grandmother'),
        },
      );
      pending = ((row is List ? row.first : row) as Map)['profile_id'] as int;

      final flagBefore = await readFlag(fx, viewersFlag);
      await writeFlag(fx, viewersFlag, 'true');
      try {
        final email = fx.testEmail('f81-viewer');
        final invite = await fam.admin.rpc<dynamic>(
          'create_viewer_invitation',
          params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')},
        );
        final token = (invite as List).single['token'] as String;
        await fx.createInvitedUser(email, token, fullName: 'E2E F81 Viewer');
        viewerProfile = await profileByEmail(fam.familyId, email);
      } finally {
        await writeFlag(fx, viewersFlag, flagBefore);
      }
    });

    List<int> everyone() => [
      fam.adminProfile.id,
      fam.memberProfile.id,
      third.id,
      viewerProfile.id,
      pending,
    ];

    test(
      'a single admin change notifies the other affected caregiver only',
      () async {
        final date = fx.nextFutureDate();
        final day = await seed(fam, fam.memberProfile.id, date);

        final got = await added(everyone(), () async {
          final fresh = await readDayById(fam.admin, day.id);
          await saveDay(
            fam.admin,
            fresh.copyWith(scheduledParentId: fam.adminProfile.id),
          );
        });

        final notice = got[fam.memberProfile.id]!.single;
        expect(notice.params, {
          'kind': 'single',
          'date': isoDate(date),
          'name': fam.adminProfile.fullName,
        });
        expect(notice.title, 'Dia alterado no calendário');
        expect(
          notice.message,
          '${fam.adminProfile.fullName} alterou o dia ${br(date)} no calendário.',
        );
        for (final id in [
          fam.adminProfile.id, // the actor
          third.id, // uninvolved
          viewerProfile.id,
          pending,
        ]) {
          expect(got[id], isEmpty, reason: 'profile $id was notified');
        }
      },
    );

    test('both columns, before and after: the planned and the real carer of '
        'a corrected past day', () async {
      final date = addDays(today, -1);
      final day = await seed(
        fam,
        fam.memberProfile.id,
        date,
        actualId: third.id,
      );

      final got = await added(everyone(), () async {
        final fresh = await readDayById(fam.admin, day.id);
        await saveDay(
          fam.admin,
          fresh.copyWith(actualParentId: fam.adminProfile.id),
        );
      });

      expect(got[fam.memberProfile.id]!.single.params!['date'], isoDate(date));
      expect(
        got[third.id]!.single.params!['kind'],
        'single',
        reason: 'the real carer the correction removed is affected too',
      );
      expect(got[fam.adminProfile.id], isEmpty);
      expect(got[viewerProfile.id], isEmpty);
    });

    test(
      'a pending member and one who left hear nothing; the new carer does',
      () async {
        final departed = third;
        final dates = [fx.nextFutureDate(), fx.nextFutureDate()];
        final ofPending = await seed(fam, pending, dates[0]);
        final ofDeparted = await seed(fam, departed.id, dates[1]);
        await fx.service
            .from('profiles')
            .update({'left_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', departed.id);

        for (final day in [ofPending, ofDeparted]) {
          final got = await added(everyone(), () async {
            final fresh = await readDayById(fam.admin, day.id);
            await saveDay(
              fam.admin,
              fresh.copyWith(scheduledParentId: fam.memberProfile.id),
            );
          });
          expect(
            got[fam.memberProfile.id]!.single.params!['date'],
            isoDate(day.scheduleDate),
          );
          expect(got[pending], isEmpty);
          expect(got[departed.id], isEmpty);
          expect(got[third.id], isEmpty);
        }
      },
    );

    test(
      "a member's own edit and the swap workflow write no such notice",
      () async {
        // The member changes the handoff time of the ADMIN's day — not an
        // admin's act, whoever the day belongs to.
        final adminDay = await seed(
          fam,
          fam.adminProfile.id,
          fx.nextFutureDate(),
        );
        var got = await added(everyone(), () async {
          final fresh = await readDayById(fam.member, adminDay.id);
          await saveDay(fam.member, fresh.copyWith(handoffTime: '17:00:00'));
        });
        expect(got.values.every((rows) => rows.isEmpty), isTrue);

        // The member asks for another admin day; the admin, as the TARGET,
        // applies the approval and resolves it — the two-party workflow.
        final date = fx.nextFutureDate();
        final day = await seed(fam, fam.adminProfile.id, date);
        got = await added(everyone(), () async {
          final request = SwapRequest.fromJson(
            (await fam.member.from('swap_requests').insert({
              'schedule_date': isoDate(date),
              'schedule_id': day.id,
              'requesting_profile_id': fam.memberProfile.id,
              'target_profile_id': fam.adminProfile.id,
              'previous_actual_parent_id': null,
              'proposed_actual_parent_id': fam.memberProfile.id,
              'status': 'pending',
            }).select()).single,
          );
          final fresh = await readDayById(fam.admin, day.id);
          await saveDay(
            fam.admin,
            fresh.copyWith(actualParentId: request.proposedActualParentId),
          );
          await fam.admin
              .from('swap_requests')
              .update({
                'status': 'approved',
                'resolved_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', request.id);
        });
        expect(
          got.values.every((rows) => rows.isEmpty),
          isTrue,
          reason: 'the workflow notifies on its own',
        );
      },
    );

    test(
      'a handoff-only admin change still notifies the carer of the day',
      () async {
        // A gap before the day: no D-1 means a transition (T-27), so the
        // time is kept — next to a day of the same carer the trigger parks it
        // and nothing of substance changes (no notice, rightly).
        final date = fx.nextFutureDates(2).last;
        final day = await seed(fam, fam.memberProfile.id, date);

        final got = await added(everyone(), () async {
          final fresh = await readDayById(fam.admin, day.id);
          await saveDay(fam.admin, fresh.copyWith(handoffTime: '18:00:00'));
        });

        expect((await readDayById(fam.admin, day.id)).handoffTime, '18:00:00');
        expect(
          got[fam.memberProfile.id]!.single.params,
          containsPair('kind', 'single'),
        );
        expect(got[third.id], isEmpty);
      },
    );

    test('clear_schedule_range writes ONE notice per recipient, with the '
        'period and the count', () async {
      final block = fx.nextFutureDates(4);
      for (final d in block.take(3)) {
        await seed(fam, fam.memberProfile.id, d);
      }
      await seed(fam, fam.adminProfile.id, block[3]);

      final got = await added(everyone(), () async {
        await fam.admin.rpc<dynamic>(
          'clear_schedule_range',
          params: {'p_from': isoDate(block.first), 'p_to': isoDate(block.last)},
        );
      });

      final notice = got[fam.memberProfile.id]!.single;
      expect(notice.params, {
        'kind': 'batch',
        'date': isoDate(block[0]),
        'to': isoDate(block[2]),
        'count': '3',
        'name': fam.adminProfile.fullName,
      });
      expect(notice.title, 'Dias alterados no calendário');
      expect(
        notice.message,
        '${fam.adminProfile.fullName} alterou 3 dias entre '
        '${br(block[0])} e ${br(block[2])} no calendário.',
      );
      expect(got[fam.adminProfile.id], isEmpty);
      expect(got[third.id], isEmpty);
    });

    test('replace_schedule_range: the days a carer loses and gains are ONE '
        'notice', () async {
      final block = fx.nextFutureDates(4);
      await seed(fam, fam.memberProfile.id, block[0]);
      await seed(fam, fam.memberProfile.id, block[1]);

      final carers = [
        fam.adminProfile.id,
        fam.adminProfile.id,
        fam.memberProfile.id,
        fam.memberProfile.id,
      ];
      final got = await added(everyone(), () async {
        await fam.admin.rpc<dynamic>(
          'replace_schedule_range',
          params: {
            'p_from': isoDate(block.first),
            'p_to': isoDate(block.last),
            'p_days': [
              for (var i = 0; i < block.length; i++)
                {
                  'schedule_date': isoDate(block[i]),
                  'scheduled_parent_id': carers[i],
                  'handoff_time': null,
                  'notes': null,
                },
            ],
          },
        );
      });

      expect(got[fam.memberProfile.id]!.single.params, {
        'kind': 'batch',
        'date': isoDate(block[0]),
        'to': isoDate(block[3]),
        'count': '4',
        'name': fam.adminProfile.fullName,
      });
      expect(got[fam.adminProfile.id], isEmpty);
    });

    test(
      'set_handoff_time_range is one notice too, over the days it wrote',
      () async {
        // A gap on both sides, so every carer change inside is a transition.
        final block = fx.nextFutureDates(5);
        await seed(fam, fam.memberProfile.id, block[1]);
        await seed(fam, fam.adminProfile.id, block[2]);
        await seed(fam, fam.memberProfile.id, block[3]);

        final got = await added(everyone(), () async {
          await fam.admin.rpc<dynamic>(
            'set_handoff_time_range',
            params: {
              'p_from': isoDate(block[1]),
              'p_to': isoDate(block[3]),
              'p_time': '18:00:00',
            },
          );
        });

        expect(got[fam.memberProfile.id]!.single.params, {
          'kind': 'batch',
          'date': isoDate(block[1]),
          'to': isoDate(block[3]),
          'count': '2',
          'name': fam.adminProfile.fullName,
        });
      },
    );

    test('several days in ONE request (no batch id) are one notice', () async {
      final block = fx.nextFutureDates(3);
      final got = await added(everyone(), () async {
        await fam.admin.from('care_schedules').insert([
          for (final d in block)
            {
              'schedule_date': isoDate(d),
              'scheduled_parent_id': fam.memberProfile.id,
            },
        ]);
      });

      final params = got[fam.memberProfile.id]!.single.params!;
      expect(params['kind'], 'batch');
      expect(params['count'], '3');
      expect(params['date'], isoDate(block.first));
      expect(params['to'], isoDate(block.last));
    });

    test("another family's admin change reaches only that family, and names "
        'nothing of anyone else', () async {
      final other = await fx.createFamily('f81-b');
      final day = await seed(
        other,
        other.memberProfile.id,
        fx.nextFutureDate(),
      );

      final got = await added(
        [...everyone(), other.memberProfile.id, other.adminProfile.id],
        () async {
          final fresh = await readDayById(other.admin, day.id);
          await saveDay(
            other.admin,
            fresh.copyWith(scheduledParentId: other.adminProfile.id),
          );
        },
      );

      final notice = got[other.memberProfile.id]!.single;
      expect(notice.params!.keys.toSet(), {'kind', 'date', 'name'});
      expect(notice.params!['name'], other.adminProfile.fullName);
      for (final id in everyone()) {
        expect(got[id], isEmpty, reason: 'family A profile $id was notified');
      }

      // And family A's own notices never name family B's people.
      for (final row in await noticesOf(fam.memberProfile.id)) {
        expect(row.params!['name'], fam.adminProfile.fullName);
        expect(
          row.params!.keys.toSet().difference({
            'kind',
            'date',
            'to',
            'count',
            'name',
            'child',
          }),
          isEmpty,
        );
      }
    });

    test(
      'the queue is readable by no client and empty after every commit',
      () async {
        await expectRejected(
          () async => fam.admin.from('admin_change_notice_queue').select(),
        );
        await expectRejected(
          () async => fam.member.from('admin_change_notice_queue').select(),
        );
        final left = await fx.service
            .from('admin_change_notice_queue')
            .select('id')
            .eq('family_id', fam.familyId);
        expect(left, isEmpty, reason: 'the flush empties what it staged');
      },
    );
  });
}
