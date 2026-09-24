import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-55 (PR 4) — the agenda speaks.
///
/// * **the creator chooses** who is told (self / the day's carer / the family)
///   and the channel (push and/or in-app, never e-mail);
/// * **a notice never tells its author** what they just did; a reminder goes
///   to everyone chosen, the author included;
/// * **the reminder** is due at the start minus 0/15/30/60 minutes, is sent
///   once, and re-arms when the moment moves;
/// * **downgrade** — a Premium item of a lapsed family is not reminded; the
///   note still is;
/// * **push** — the two types are in the dispatcher's filter, so T-83's
///   per-type switch accepts them.
///
/// The minute cron runs in the shared dev project too, so the assertions read
/// the ROWS, never the function's return count.
void agendaNotifyTests(GateFixture fx) {
  const flag = 'feature.child_agenda';
  final today = saoPauloToday();
  DateTime ahead(int days) => addDays(today, days);
  String br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// São Paulo's wall clock, [minutes] from now (no DST since 2019).
  DateTime spIn(int minutes) => DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 3))
      .add(Duration(minutes: minutes));
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<int> add(
    SupabaseClient who,
    DateTime date,
    String kind, {
    int? childId,
    String? start,
    String? body,
    String notifyTo = 'none',
    bool push = true,
    bool inApp = true,
    int? remind,
  }) async =>
      await who.rpc<dynamic>('add_child_event', params: {
        'p_date': isoDate(date),
        'p_kind': kind,
        'p_child_id': childId,
        'p_start': start,
        'p_body': body,
        'p_notify_to': notifyTo,
        'p_notify_push': push,
        'p_notify_in_app': inApp,
        'p_remind': remind,
      }) as int;

  Future<List<Map<String, dynamic>>> inbox(int profileId, String type) async =>
      List<Map<String, dynamic>>.from(await fx.service
          .from('notifications')
          .select()
          .eq('recipient_profile_id', profileId)
          .eq('type', type)
          .order('id', ascending: true));

  Future<Map<String, dynamic>> eventRow(int id) async => (await fx.service
          .from('child_events')
          .select()
          .eq('id', id)
          .limit(1))
      .single;

  group('F-55 · agenda notices and reminders', () {
    late ThrowawayFamily fam;
    late int child;
    late String flagBefore;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('f55ntf');
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.familyId);
      child = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Bia'}) as int;
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('a notice to the family reaches everyone but its author', () async {
      await add(fam.admin, ahead(3), 'medicine',
          childId: child, start: '14:00', body: '5 ml', notifyTo: 'family');
      expect(await inbox(fam.adminProfile.id, 'agenda_notice'), isEmpty);
      final rows = await inbox(fam.memberProfile.id, 'agenda_notice');
      expect(rows, hasLength(1));
      final n = rows.single;
      expect(n['title'], 'Novo na agenda');
      expect(n['message'],
          'E2E f55ntf Adm adicionou à agenda de ${br(ahead(3))}: 14:00 · Remédio · Bia. 5 ml');
      expect(n['is_read'], isFalse);
      expect(n['params'], {
        'date': isoDate(ahead(3)),
        'kind': 'medicine',
        'time': '14:00',
        'child': 'Bia',
        'name': 'E2E f55ntf Adm',
        'msg': '5 ml',
      });
    });

    test('"only me" sends no notice; "the day\'s carer" finds the carer',
        () async {
      await add(fam.admin, ahead(4), 'note', body: 'só eu', notifyTo: 'self');
      expect(
          (await inbox(fam.memberProfile.id, 'agenda_notice'))
              .where((n) => (n['params'] as Map)['date'] == isoDate(ahead(4))),
          isEmpty);

      await fx.service.from('care_schedules').insert({
        'family_id': fam.familyId,
        'schedule_date': isoDate(ahead(5)),
        'scheduled_parent_id': fam.memberProfile.id,
      });
      await add(fam.admin, ahead(5), 'note',
          body: 'para quem está com ela', notifyTo: 'responsible');
      expect(
          (await inbox(fam.memberProfile.id, 'agenda_notice'))
              .where((n) => (n['params'] as Map)['date'] == isoDate(ahead(5))),
          hasLength(1));
    });

    test('the channel: in-app off is born read and marked; push off is marked',
        () async {
      await add(fam.admin, ahead(6), 'note',
          body: 'só celular', notifyTo: 'family', inApp: false);
      await add(fam.admin, ahead(7), 'note',
          body: 'só app', notifyTo: 'family', push: false);
      final rows = await inbox(fam.memberProfile.id, 'agenda_notice');
      final phoneOnly = rows.singleWhere(
          (n) => (n['params'] as Map)['date'] == isoDate(ahead(6)));
      expect(phoneOnly['is_read'], isTrue);
      expect((phoneOnly['params'] as Map)['in_app'], 'false');
      final appOnly = rows.singleWhere(
          (n) => (n['params'] as Map)['date'] == isoDate(ahead(7)));
      expect(appOnly['is_read'], isFalse);
      expect((appOnly['params'] as Map)['push'], 'false');
    });

    test('the choice is validated on the server', () async {
      await expectRejected(
          () => add(fam.admin, ahead(8), 'note',
              body: 'x', notifyTo: 'family', push: false, inApp: false),
          contains: 'pelo menos um canal');
      await expectRejected(
          () => add(fam.admin, ahead(8), 'note',
              body: 'x', notifyTo: 'family', remind: 15),
          contains: 'precisa do horário de início');
      await expectRejected(
          () => add(fam.admin, ahead(8), 'note',
              body: 'x', start: '10:00', remind: 15),
          contains: 'quem recebe o lembrete');
      await expectRejected(
          () => add(fam.admin, ahead(8), 'note',
              body: 'x', start: '10:00', notifyTo: 'family', remind: 5),
          contains: '15, 30 ou 60');
      await expectRejected(
          () => add(fam.admin, ahead(8), 'note', body: 'x', notifyTo: 'all'),
          contains: 'Destinatário da notificação desconhecido');
    });

    test('the reminder is due at start minus the offset, and sent once',
        () async {
      final at = spIn(10);
      final soon = await add(fam.member, DateTime(at.year, at.month, at.day),
          'medicine',
          childId: child,
          start: hm(at),
          notifyTo: 'family',
          remind: 15);
      final later = await add(fam.member, DateTime(at.year, at.month, at.day),
          'note',
          body: 'ainda não',
          start: hm(at),
          notifyTo: 'family',
          remind: 0);

      await fx.service.rpc<dynamic>('agenda_reminders_due',
          params: {'p_family_id': fam.familyId});
      await fx.service.rpc<dynamic>('agenda_reminders_due',
          params: {'p_family_id': fam.familyId});

      // Both members — the author included — get exactly one.
      for (final p in [fam.adminProfile.id, fam.memberProfile.id]) {
        final rows = (await inbox(p, 'agenda_reminder'))
            .where((n) => (n['params'] as Map)['kind'] == 'medicine')
            .toList();
        expect(rows, hasLength(1), reason: 'profile $p');
        expect(rows.single['title'], 'Lembrete da agenda');
        expect(rows.single['message'],
            '${hm(at)} · Remédio · Bia (${br(DateTime(at.year, at.month, at.day))}).');
      }
      expect((await eventRow(soon))['reminded_at'], isNotNull);
      expect((await eventRow(later))['reminded_at'], isNull);
    });

    test('moving the moment re-arms the reminder', () async {
      final at = spIn(5);
      final day = DateTime(at.year, at.month, at.day);
      final id = await add(fam.admin, day, 'note',
          body: 'rearmar', start: hm(at), notifyTo: 'self', remind: 15);
      await fx.service.rpc<dynamic>('agenda_reminders_due',
          params: {'p_family_id': fam.familyId});
      expect((await eventRow(id))['reminded_at'], isNotNull);

      final moved = spIn(120);
      await fam.admin.rpc<dynamic>('update_child_event', params: {
        'p_event_id': id,
        'p_date': isoDate(DateTime(moved.year, moved.month, moved.day)),
        'p_kind': 'note',
        'p_body': 'rearmar',
        'p_start': hm(moved),
        'p_notify_to': 'self',
        'p_remind': 15,
      });
      expect((await eventRow(id))['reminded_at'], isNull);
    });

    test('downgrade: a Premium item is not reminded; the note still is',
        () async {
      final at = spIn(10);
      final day = DateTime(at.year, at.month, at.day);
      final school = await add(fam.admin, day, 'school',
          childId: child, start: hm(at), notifyTo: 'self', remind: 15);
      final note = await add(fam.admin, day, 'note',
          body: 'nota fica', start: hm(at), notifyTo: 'self', remind: 15);
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', fam.familyId);
      try {
        await fx.service.rpc<dynamic>('agenda_reminders_due',
            params: {'p_family_id': fam.familyId});
        expect((await eventRow(school))['reminded_at'], isNull);
        expect((await eventRow(note))['reminded_at'], isNotNull);
      } finally {
        await fx.service
            .from('families')
            .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', fam.familyId);
      }
    });

    test('a routine sends ONE notice, and its events keep the reminder',
        () async {
      await fx.service.from('care_schedules').insert([
        for (var i = 10; i < 24; i++)
          {
            'family_id': fam.familyId,
            'schedule_date': isoDate(ahead(i)),
            'scheduled_parent_id': fam.adminProfile.id,
          }
      ]);
      final before = (await inbox(fam.memberProfile.id, 'agenda_notice')).length;
      final r = Map<String, dynamic>.from(
          await fam.admin.rpc<dynamic>('save_child_routine', params: {
        'p_routine_id': null,
        'p_from': isoDate(ahead(10)),
        'p_kind': 'activity',
        'p_weekdays': [ahead(10).weekday, ahead(12).weekday],
        'p_child_id': child,
        'p_start': '17:00',
        'p_notify_to': 'family',
        'p_remind': 30,
      }) as Map);
      final rows = await inbox(fam.memberProfile.id, 'agenda_notice');
      expect(rows.length - before, 1);
      expect((rows.last['params'] as Map)['routine'], '1');
      expect(rows.last['message'],
          'E2E f55ntf Adm criou uma rotina na agenda a partir de ${br(ahead(10))}: 17:00 · Atividade · Bia.');
      final events = await fx.service
          .from('child_events')
          .select('remind_minutes, notify_to')
          .eq('batch_id', r['routine_id'] as String);
      expect(events, isNotEmpty);
      expect(events.every((e) => e['remind_minutes'] == 30), isTrue);
      expect(events.every((e) => e['notify_to'] == 'family'), isTrue);
    });

    test('T-83: the per-type push switch accepts the two agenda types',
        () async {
      final before = await readFlag(fx, 'push.disabled_types');
      try {
        await writeFlag(
            fx, 'push.disabled_types', '["agenda_notice", "agenda_reminder"]');
      } finally {
        await writeFlag(fx, 'push.disabled_types', before);
      }
    });
  });
}
