// T-18 PR 2 — the device's copy of the calendar, on the real class.
//
// `OfflineCache` is driven over the real file store in a temporary directory,
// and the rows go through the real `fromJson`/`toRowJson` of the
// contracts package — no fake reimplements what is under test (the 01/09/2026
// trap). The one thing a round trip cannot catch is a column added to
// `fromJson` and forgotten in `toRowJson`: the fixture would simply not have
// it. So the last group reads the model SOURCES and compares the two key sets.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/services/offline_cache.dart';
import 'package:entrelares_app/services/offline_cache_store_io.dart';

/// Every column each model reads, populated — so a round trip compares all of
/// them. Timestamps are written the way `toIso8601String` writes a UTC instant.
final memberRow = <String, dynamic>{
  'id': 7,
  'family_id': 3,
  'full_name': 'Ana Souza',
  'color_slot': 2,
  'user_id': 'u-ana',
  'left_at': null,
  'language': 'pt-BR',
  'language_detected': 'pt-BR',
  'is_admin': true,
  'role_id': 1,
  'email': 'ana@example.com',
  'deletion_scheduled_for': '2026-10-01T03:00:00.000Z',
  'joined_via_invite': true,
  'consent_policy_version': '2026-08-20',
  'consent_accepted_at': '2026-08-21T12:00:00.000Z',
  'onboarding_swap_explained_at': '2026-08-22T12:00:00.000Z',
  'onboarding_tour_seen_at': '2026-08-23T12:00:00.000Z',
  'onboarding_dismissed_at': '2026-08-24T12:00:00.000Z',
  'created_at': '2026-08-01T12:00:00.000Z',
};

final roleRow = <String, dynamic>{
  'id': 4,
  'role': 'Madrinha',
  'family_id': 3,
  'emoji': '🌻',
};

final dayRow = <String, dynamic>{
  'id': 11,
  'schedule_date': '2026-09-15',
  'handoff_time': '18:30:00',
  'scheduled_parent_id': 7,
  'actual_parent_id': 8,
  'notes': 'Levar a mochila',
  'created_at': '2026-09-01T10:00:00+00:00',
  'updated_at': '2026-09-02T10:00:00+00:00',
  'revision': 3,
  'revision_token': 'tok-11',
};

final requestRow = <String, dynamic>{
  'id': 21,
  'schedule_date': '2026-09-20',
  'schedule_id': 11,
  'requesting_profile_id': 8,
  'target_profile_id': 7,
  'previous_actual_parent_id': 7,
  'proposed_actual_parent_id': 8,
  'proposed_handoff_time': '09:00:00',
  'status': 'pending',
  'rejection_reason': null,
  'request_message': 'Posso ficar com eles?',
  'approval_note': null,
  'pre_edit_log_id': 99,
  'resolution_log_id': null,
  'revert_notes': true,
  'resolved_by': null,
  'reminder_sent_at': '2026-09-14T09:00:00.000Z',
  'created_at': '2026-09-13T10:00:00+00:00',
  'updated_at': '2026-09-13T10:00:00+00:00',
  'resolved_at': null,
};

OfflineCalendarSnapshot snapshot({DateTime? savedAt, String notes = 'x'}) =>
    OfflineCalendarSnapshot(
      savedAt: savedAt ?? DateTime(2026, 9, 14, 8, 12),
      month: DateTime(2026, 9, 1),
      members: [Member.fromJson(memberRow)],
      roles: [Role.fromJson(roleRow)],
      days: [CareSchedule.fromJson({...dayRow, 'notes': notes})],
      frozen: [SwapRequest.fromJson(requestRow)],
      ownProfile: Member.fromJson(memberRow),
      upcoming: [CareSchedule.fromJson(dayRow)],
    );

void main() {
  group('toRowJson gives back the row fromJson read', () {
    test('Member', () {
      expect(Member.fromJson(memberRow).toRowJson(), memberRow);
    });
    test('Role', () {
      expect(Role.fromJson(roleRow).toRowJson(), roleRow);
    });
    test('CareSchedule — the concurrency token survives, for the T-35 echo',
        () {
      expect(CareSchedule.fromJson(dayRow).toRowJson(), dayRow);
    });
    test('SwapRequest', () {
      expect(SwapRequest.fromJson(requestRow).toRowJson(), requestRow);
    });
  });

  group('OfflineCache over the real file store', () {
    late Directory root;
    String? signedIn = 'u-ana';

    setUp(() async {
      root = await Directory.systemTemp.createTemp('t18-cache-');
      signedIn = 'u-ana';
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    FileOfflineCacheStore store() =>
        FileOfflineCacheStore(root: () async => root);

    OfflineCache cache({bool enabled = true}) =>
        OfflineCache(store(), userId: () => signedIn, enabled: enabled);

    Directory copies() => Directory('${root.path}/offline_calendar');

    test('what is saved reads back, dated by the save', () async {
      await cache().save(snapshot());
      final back = (await cache().read())!;

      expect(back.savedAt, DateTime(2026, 9, 14, 8, 12));
      expect(back.isFor(DateTime(2026, 9, 30)), isTrue);
      expect(back.isFor(DateTime(2026, 10, 1)), isFalse);
      expect(back.members.single.fullName, 'Ana Souza');
      expect(back.roles.single.emoji, '🌻');
      expect(back.days.single.revisionToken, 'tok-11');
      expect(back.frozen.single.requestMessage, 'Posso ficar com eles?');
      expect(back.ownProfile!.isAdmin, isTrue);
      expect(back.upcoming.single.handoffTime, '18:30:00');
    });

    test('it lives under the CACHE directory handed to it — never prefs',
        () async {
      // Android Auto Backup copies the preferences file to the user's Google
      // account; the cache directory is the one place it never copies.
      await cache().save(snapshot());
      expect(File('${copies().path}/u-ana.json').existsSync(), isTrue);
      expect(File('${copies().path}/u-ana.json.partial').existsSync(), isFalse);
    });

    test('a newer save replaces the copy', () async {
      await cache().save(snapshot());
      await cache().save(
          snapshot(savedAt: DateTime(2026, 9, 14, 10, 2), notes: 'mudou'));
      final back = (await cache().read())!;
      expect(back.savedAt, DateTime(2026, 9, 14, 10, 2));
      expect(back.days.single.notes, 'mudou');
    });

    test('a copy is read back only by the account that wrote it', () async {
      await cache().save(snapshot());
      signedIn = 'u-bruno';
      expect(await cache().read(), isNull);
      signedIn = null;
      expect(await cache().read(), isNull);
    });

    test('disabled (the web) writes nothing and reads nothing', () async {
      await cache(enabled: false).save(snapshot());
      expect(copies().existsSync(), isFalse);
      await cache().save(snapshot());
      expect(await cache(enabled: false).read(), isNull);
    });

    test('clear removes every account\'s copy, even where disabled', () async {
      await cache().save(snapshot());
      signedIn = 'u-bruno';
      await cache().save(snapshot());

      await cache(enabled: false).clear();

      expect(copies().existsSync(), isFalse);
      signedIn = 'u-ana';
      expect(await cache().read(), isNull);
    });

    test('clear with nothing kept does not throw', () async {
      await cache().clear();
    });

    test('a copy that no longer parses is dropped, not thrown', () async {
      await cache().save(snapshot());
      File('${copies().path}/u-ana.json').writeAsStringSync('{"v":1,"days":');

      expect(await cache().read(), isNull);
      expect(File('${copies().path}/u-ana.json').existsSync(), isFalse);
    });

    test('a copy in another format is ignored', () async {
      await cache().save(snapshot());
      final file = File('${copies().path}/u-ana.json');
      file.writeAsStringSync(
          file.readAsStringSync().replaceFirst('"v":1', '"v":0'));

      expect(await cache().read(), isNull);
    });

    test('an account id that is not a UUID never becomes a path', () async {
      signedIn = '../../escape';
      // The store refuses it; save and read both turn that into "no copy".
      await cache().save(snapshot());
      expect(await cache().read(), isNull);
      expect(Directory('${root.path}/escape').existsSync(), isFalse);
    });

    // T-77 (16/09/2026): the Android E2E lane died with `PathNotFoundException:
    // Cannot rename file to …/<account>.json, path = …/<account>.json.partial`.
    // The calendar fires `save` unawaited on every load of the current month,
    // and two loads close together (the reload after approving a swap) put two
    // writes on the SAME `.partial`: the first rename took it, the second found
    // nothing. Unawaited, that is an uncaught error in the app's zone.
    test('saves fired together never race — no throw, the last one wins',
        () async {
      final c = cache();
      await Future.wait([
        for (var i = 0; i < 6; i++) c.save(snapshot(notes: 'n$i')),
      ]);
      expect((await c.read())!.days.single.notes, 'n5');
      expect(File('${copies().path}/u-ana.json.partial').existsSync(), isFalse);
    });

    test('a clear that arrives during a save leaves no copy behind', () async {
      // Sign-out wipes the copies; a save already in flight must not write the
      // family's plan back afterwards.
      final c = cache();
      final saving = c.save(snapshot());
      await c.clear();
      await saving;
      expect(copies().existsSync(), isFalse);
    });

    test('save never throws — it is fired unawaited from the calendar',
        () async {
      // A root that cannot hold a directory: every file operation fails.
      final blocker = File('${root.path}/not-a-dir')..writeAsStringSync('');
      final broken = OfflineCache(
          FileOfflineCacheStore(root: () async => Directory(blocker.path)),
          userId: () => signedIn,
          enabled: true);
      await broken.save(snapshot());
      expect(await broken.read(), isNull);
    });
  });

  group('no column can vanish from the cache (source guard)', () {
    // Read in fromJson ⇔ written in toRowJson, for every model the cache keeps.
    Set<String> keysIn(String source, String startMarker, RegExp key) {
      final start = source.indexOf(startMarker);
      expect(start, isNonNegative, reason: 'missing $startMarker');
      final end = source.indexOf('\n\n', start);
      return key
          .allMatches(source.substring(start, end))
          .map((m) => m.group(1)!)
          .toSet();
    }

    for (final (file, model) in [
      ('member.dart', 'Member'),
      ('role.dart', 'Role'),
      ('care_schedule.dart', 'CareSchedule'),
      ('swap_request.dart', 'SwapRequest'),
    ]) {
      test(model, () {
        final source = File(
                '../packages/entrelares_db_contracts/lib/models/$file')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        final read = keysIn(source, 'factory $model.fromJson',
            RegExp(r"json\['([a-z_]+)'\]"));
        final written = keysIn(source, 'Map<String, dynamic> toRowJson()',
            RegExp(r"^\s*'([a-z_]+)':", multiLine: true));

        expect(read, isNotEmpty);
        expect(written, read);
      });
    }
  });
}
