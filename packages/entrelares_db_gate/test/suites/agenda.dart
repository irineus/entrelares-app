import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-55 (PR 2) — the day agenda, where it is actually enforced.
///
/// * **dark by construction** — flag off, every write is refused;
/// * **free = the day's note** — `agenda.free_notes_per_day` notes, and every
///   other kind is Premium (`agenda.premium_only`), refused on the SERVER;
/// * **today on** — a past day is read-only, for everyone;
/// * **downgrade** — a Premium event of a family that lapsed stays readable
///   and is refused to edit or delete; its note stays writable;
/// * **the trail** — a delete is soft (who, when), the row stays;
/// * **the observation** — frozen while the flag is on, converted once by an
///   idempotent function, and the F-47 revert moves no text any more.
///
/// The flag is OFF for the gate run (the entrypoint); these groups turn it on
/// for themselves and put it back.
void agendaTests(GateFixture fx) {
  const flag = 'feature.child_agenda';
  final today = saoPauloToday();
  DateTime ahead(int days) => addDays(today, days);

  Future<void> makeFree(int familyId) => fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', familyId);

  Future<void> makePremium(int familyId) => fx.service
      .from('families')
      .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', familyId);

  Future<int> addEvent(
    SupabaseClient who,
    DateTime date,
    String kind, {
    int? childId,
    String? start,
    String? end,
    String? body,
  }) async =>
      await who.rpc<dynamic>('add_child_event', params: {
        'p_date': isoDate(date),
        'p_kind': kind,
        'p_child_id': childId,
        'p_start': start,
        'p_end': end,
        'p_body': body,
      }) as int;

  Future<Map<String, dynamic>> eventRow(int id) async => (await fx.service
          .from('child_events')
          .select()
          .eq('id', id)
          .limit(1))
      .single;

  group('F-55 · agenda', () {
    late ThrowawayFamily free;
    late ThrowawayFamily prem;
    late int freeChild;
    late int premChild;
    late String flagBefore;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      free = await fx.createFamily('f55free');
      prem = await fx.createFamily('f55prem');
      await makeFree(free.familyId);
      await makePremium(prem.familyId);
      freeChild = await free.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Lia'}) as int;
      premChild = await prem.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Theo'}) as int;
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('with the flag OFF the server refuses the write', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(
            () => addEvent(free.admin, ahead(2), 'note', body: 'x'),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });

    test('a free family writes the day\'s note, trimmed, as any member',
        () async {
      final id = await addEvent(free.member, ahead(2), 'note',
          body: '  levar o casaco  ');
      final r = await eventRow(id);
      expect(r['kind'], 'note');
      expect(r['body'], 'levar o casaco');
      expect(r['child_id'], isNull);
      expect(r['event_date'], isoDate(ahead(2)));
      expect(r['created_by'], free.memberProfile.id);
      expect(r['deleted_at'], isNull);
    });

    test('a free family\'s second note on the same day is refused', () async {
      await expectRejected(
          () => addEvent(free.admin, ahead(2), 'note', body: 'outra'),
          contains: 'nota(s) por dia');
      expect(await addEvent(free.admin, ahead(3), 'note', body: 'outro dia'),
          isPositive);
    });

    test('a free family cannot create a structured event', () async {
      await expectRejected(
          () => addEvent(free.admin, ahead(2), 'school',
              childId: freeChild, start: '07:30'),
          contains: 'recurso Premium');
    });

    test('Premium: a school shift with the child and its hours', () async {
      final id = await addEvent(prem.member, ahead(2), 'school',
          childId: premChild, start: '13:00', end: '18:00', body: 'turma B');
      final r = await eventRow(id);
      expect(r['kind'], 'school');
      expect(r['child_id'], premChild);
      expect(r['start_time'], '13:00:00');
      expect(r['end_time'], '18:00:00');
    });

    test('Premium: notes have no daily limit', () async {
      await addEvent(prem.admin, ahead(4), 'note', body: 'uma');
      expect(await addEvent(prem.admin, ahead(4), 'note', body: 'duas'),
          isPositive);
    });

    test('a structured event without a child is refused', () async {
      await expectRejected(
          () => addEvent(prem.admin, ahead(2), 'medicine', start: '14:00'),
          contains: 'Escolha a criança');
    });

    test('another family\'s child is refused', () async {
      await expectRejected(
          () => addEvent(prem.admin, ahead(2), 'health', childId: freeChild),
          contains: 'Criança não encontrada');
    });

    test('a note needs its text; an end needs a start before it', () async {
      await expectRejected(() => addEvent(prem.admin, ahead(5), 'note'),
          contains: 'texto da nota');
      await expectRejected(
          () => addEvent(prem.admin, ahead(5), 'activity',
              childId: premChild, start: '15:00', end: '14:00'),
          contains: 'depois do início');
      await expectRejected(
          () => addEvent(prem.admin, ahead(5), 'activity',
              childId: premChild, end: '14:00'),
          contains: 'depois do início');
    });

    test('the text limit is the operator key', () async {
      await expectRejected(
          () => addEvent(prem.admin, ahead(5), 'note', body: 'a' * 501),
          contains: 'limitado a 500 caracteres');
      expect(await addEvent(prem.admin, ahead(5), 'note', body: 'a' * 500),
          isPositive);
    });

    test('a past day is refused — even to an admin', () async {
      await expectRejected(
          () => addEvent(prem.admin, addDays(today, -1), 'note', body: 'x'),
          contains: 'de hoje em diante');
      expect(await addEvent(prem.admin, today, 'note', body: 'hoje'),
          isPositive);
    });

    test('the day cap is the operator key', () async {
      final day = ahead(9);
      final before = await readFlag(fx, 'agenda.max_events_per_day');
      await writeFlag(fx, 'agenda.max_events_per_day', '5');
      try {
        for (var i = 0; i < 5; i++) {
          await addEvent(prem.admin, day, 'note', body: 'n$i');
        }
        await expectRejected(
            () => addEvent(prem.admin, day, 'note', body: 'sexta'),
            contains: 'já tem 5 eventos');
      } finally {
        await writeFlag(fx, 'agenda.max_events_per_day', before);
      }
    });

    test('an edit changes the event and says who; a delete is soft', () async {
      final id = await addEvent(prem.admin, ahead(6), 'activity',
          childId: premChild, start: '16:00', body: 'natação');
      await prem.member.rpc<dynamic>('update_child_event', params: {
        'p_event_id': id,
        'p_date': isoDate(ahead(6)),
        'p_kind': 'activity',
        'p_child_id': premChild,
        'p_start': '17:00',
        'p_end': null,
        'p_body': 'natação',
      });
      var r = await eventRow(id);
      expect(r['start_time'], '17:00:00');
      expect(r['updated_by'], prem.memberProfile.id);

      await prem.member
          .rpc<dynamic>('delete_child_event', params: {'p_event_id': id});
      r = await eventRow(id);
      expect(r['deleted_by'], prem.memberProfile.id);
      expect(r['deleted_at'], isNotNull);
      // The row stays, readable by the family: it is the trail.
      final seen =
          await prem.admin.from('child_events').select('id').eq('id', id);
      expect(seen, hasLength(1));
      await expectRejected(
          () => prem.admin
              .rpc<dynamic>('delete_child_event', params: {'p_event_id': id}),
          contains: 'não encontrado');
    });

    test('no client writes the table directly', () async {
      await expectRejected(() async {
        await prem.admin.from('child_events').insert({
          'family_id': prem.familyId,
          'event_date': isoDate(ahead(2)),
          'kind': 'note',
          'body': 'direto',
        });
      });
    });

    test('another family neither reads nor edits the agenda', () async {
      final id = await addEvent(prem.admin, ahead(7), 'note', body: 'nosso');
      expect(await free.admin.from('child_events').select('id').eq('id', id),
          isEmpty);
      await expectRejected(
          () => free.admin
              .rpc<dynamic>('delete_child_event', params: {'p_event_id': id}),
          contains: 'não encontrado');
    });

    test('downgrade: the Premium event is read-only, the note is not',
        () async {
      final down = await fx.createFamily('f55down');
      await makePremium(down.familyId);
      final child = await down.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Nina'}) as int;
      final school = await addEvent(down.admin, ahead(3), 'school',
          childId: child, start: '07:00');
      final note = await addEvent(down.admin, ahead(3), 'note', body: 'ok');
      await makeFree(down.familyId);

      await expectRejected(
          () => down.admin.rpc<dynamic>('delete_child_event',
              params: {'p_event_id': school}),
          contains: 'só para leitura');
      expect((await eventRow(school))['deleted_at'], isNull);
      await down.admin
          .rpc<dynamic>('delete_child_event', params: {'p_event_id': note});
      expect((await eventRow(note))['deleted_at'], isNotNull);
    });
  });

  group('F-55 · the observation', () {
    late ThrowawayFamily fam;
    late String flagBefore;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      fam = await fx.createFamily('f55obs');
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    Future<int> seedDay(DateTime date, String? notes) async => (await fx.service
            .from('care_schedules')
            .insert({
              'family_id': fam.familyId,
              'schedule_date': isoDate(date),
              'scheduled_parent_id': fam.adminProfile.id,
              'notes': notes,
            })
            .select('id'))
        .single['id'] as int;

    test('with the flag ON the notes column cannot change; the row can',
        () async {
      await writeFlag(fx, flag, 'false');
      await seedDay(ahead(11), 'antes');
      await writeFlag(fx, flag, 'true');

      final day = await readDay(fam.member, ahead(11));
      await expectRejected(
          () => saveDay(fam.member, day.copyWith(notes: 'depois')),
          contains: 'virou a agenda');
      // Every client UPDATE sends the whole row: the same notes pass.
      await saveDay(fam.member, await readDay(fam.member, ahead(11)));
      expect((await readDay(fam.member, ahead(11))).notes, 'antes');
    });

    test('the conversion turns each observation into ONE note, once',
        () async {
      await writeFlag(fx, flag, 'false');
      final marker = uniqueMarker();
      final dayId = await seedDay(ahead(12), '  $marker  ');
      final pastId = await seedDay(addDays(today, -3), 'passado $marker');
      await writeFlag(fx, flag, 'true');

      final first = await fx.service
          .rpc<dynamic>('convert_observations_to_agenda') as int;
      expect(first, greaterThanOrEqualTo(2));
      final again = await fx.service
          .rpc<dynamic>('convert_observations_to_agenda') as int;
      expect(again, 0);

      final rows = await fx.service
          .from('child_events')
          .select()
          .inFilter('source_schedule_id', [dayId, pastId]);
      expect(rows, hasLength(2));
      final future = rows.firstWhere((r) => r['source_schedule_id'] == dayId);
      expect(future['kind'], 'note');
      expect(future['body'], marker);
      expect(future['child_id'], isNull);
      expect(future['created_by'], isNull);
      expect(future['event_date'], isoDate(ahead(12)));
      // Past days convert too: they are the record.
      expect(rows.any((r) => r['source_schedule_id'] == pastId), isTrue);
    });

    test('the F-47 revert moves no text while the agenda is on', () async {
      await writeFlag(fx, flag, 'false');
      final dayId = await seedDay(ahead(13), 'A');
      await fx.service
          .from('care_schedules')
          .update({'notes': 'B'}).eq('id', dayId);
      final log = (await fx.service
              .from('activity_logs')
              .select('id')
              .eq('schedule_id', dayId)
              .eq('action', 'UPDATE')
              .order('id', ascending: false)
              .limit(1))
          .single['id'] as int;
      await writeFlag(fx, flag, 'true');

      await fx.service.rpc<dynamic>('restore_pre_edit_state', params: {
        'p_schedule_id': dayId,
        'p_pre_edit_log_id': log,
        'p_restore_notes': true,
      });
      final row = (await fx.service
              .from('care_schedules')
              .select('notes')
              .eq('id', dayId))
          .single;
      expect(row['notes'], 'B');
    });
  });
}
