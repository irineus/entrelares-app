import 'dart:math';

import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

/// Asserts that [action] is REJECTED by the database, optionally naming a
/// fragment of the message the user would see.
///
/// The C# suite spelled this `AssertRejectedAsync`, and it is worth keeping the
/// message check: several of these rules exist to produce a specific PT-BR
/// sentence the client turns into a screen, and a rule that fires with the
/// wrong reason is a different bug from one that does not fire at all.
///
/// It deliberately catches ANY error rather than `PostgrestException` alone: a
/// rejection can arrive from PostgREST (RLS, a trigger's RAISE) or from the RPC
/// layer, and which one it is is not part of the rule under test.
Future<void> expectRejected(
  Future<void> Function() action, {
  String? contains,
  bool caseInsensitive = false,
}) async {
  Object? caught;
  try {
    await action();
  } catch (error) {
    caught = error;
  }
  expect(caught, isNotNull, reason: 'the operation was NOT rejected');
  if (contains != null) {
    final message = caught.toString();
    final haystack = caseInsensitive ? message.toLowerCase() : message;
    final needle = caseInsensitive ? contains.toLowerCase() : contains;
    expect(haystack, stringContainsInOrder([needle]),
        reason: 'rejected, but not for the expected reason: $message');
  }
}

/// A per-assertion marker, so a row this run wrote can be told apart from
/// everything the shared QA project has ever accumulated.
String uniqueMarker() {
  final rng = Random.secure();
  return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
}

/// The day at [date], as [who] sees it.
Future<CareSchedule> readDay(SupabaseClient who, DateTime date) async =>
    CareSchedule.fromJson((await who
            .from('care_schedules')
            .select()
            .eq('schedule_date', isoDate(date)))
        .single);

/// The day with [id], as [who] sees it.
///
/// Re-reading before every write is not ceremony. The T-35 echo is only valid
/// for the `revision_token` the LAST read returned, so a stale object in a test
/// variable is exactly the payload the guard exists to reject — which would
/// make the test fail for a reason that has nothing to do with its rule.
Future<CareSchedule> readDayById(SupabaseClient who, int id) async =>
    CareSchedule.fromJson(
        (await who.from('care_schedules').select().eq('id', id)).single);

/// The full-row UPDATE the client really sends — `revision` as read and
/// `submitted_token` echoing the token that came with it. Anything less is
/// rejected by the T-35 guard before the rule under test is ever reached.
Future<void> saveDay(SupabaseClient who, CareSchedule day) async {
  await who.from('care_schedules').update(day.toUpdateJson()).eq('id', day.id);
}

/// T-84 — a phase-6 `feature.*` flag, read and written on the shared dev
/// project. The entrypoint turns `feature.child_agenda` OFF for the whole run
/// (with it on, the F-55 guard freezes `care_schedules.notes`, which older
/// suites edit as their generic field) and each agenda suite turns it ON for
/// its own groups only.
Future<String> readFlag(GateFixture fx, String key) async => (await fx.service
        .from('app_settings')
        .select('value')
        .eq('key', key))
    .single['value'] as String;

Future<void> writeFlag(GateFixture fx, String key, String value) =>
    fx.service.from('app_settings').update({'value': value}).eq('key', key);
