import 'dart:convert';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';

/// T-18 — what the calendar last read of the CURRENT month, as the device keeps
/// it for a morning with no signal.
///
/// Exactly what the calendar screen and its today card paint, and nothing
/// else: the members and roles (legend, names), the month's days and open
/// requests (grid, ⏳ badges), the reader's own profile and the upcoming
/// window (today card). Rows are kept in the shape PostgREST returned them
/// (`toRowJson` / `fromJson`), so the cache can never hold a field the
/// server did not send.
class OfflineCalendarSnapshot {
  /// When the server last confirmed this content — what the strip names.
  final DateTime savedAt;

  /// The month the days and requests belong to (first day, local).
  final DateTime month;

  final List<Member> members;
  final List<Role> roles;
  final List<CareSchedule> days;
  final List<SwapRequest> frozen;
  final Member? ownProfile;
  final List<CareSchedule> upcoming;

  const OfflineCalendarSnapshot({
    required this.savedAt,
    required this.month,
    required this.members,
    required this.roles,
    required this.days,
    required this.frozen,
    required this.ownProfile,
    required this.upcoming,
  });

  bool isFor(DateTime otherMonth) =>
      month.year == otherMonth.year && month.month == otherMonth.month;
}

/// T-18 — where [OfflineCache] puts its bytes (see `offline_cache_store.dart`
/// for why that is a file in the cache directory and never the preferences).
abstract interface class OfflineCacheStore {
  Future<String?> read(String account);
  Future<void> write(String account, String contents);
  Future<void> delete(String account);
  Future<void> deleteAll();
}

/// T-18 — the device's copy of the calendar. **Android only, by decision**
/// (owner, 14/09/2026): on the web the only storage is `localStorage`,
/// readable by anyone who sits at a shared computer after the reader, and the
/// web channel cannot open offline anyway (its service worker is a tombstone),
/// so a copy there would buy nothing and expose a family's plan. There the
/// calendar keeps only what it holds in memory.
///
/// One copy per signed-in account, and every copy is wiped the moment the app
/// leaves the authenticated phase — sign-out, inactivity, a refused session —
/// because what it holds is somebody's family. §9 of the privacy policy names
/// this storage.
class OfflineCache {
  /// Bumped when the stored shape changes; an older copy is ignored, never
  /// half-read.
  static const int formatVersion = 1;

  final OfflineCacheStore _store;

  /// Who is signed in at the moment of each call — never captured once, so a
  /// copy can only ever be read back by the account that wrote it.
  final String? Function() userId;

  /// False on the web (see the class comment): save and read are then no-ops.
  final bool enabled;

  OfflineCache(this._store, {required this.userId, required this.enabled});

  /// Keeps [snapshot] for the signed-in account, replacing the previous copy.
  ///
  /// Never throws: the calendar fires it unawaited, where a failure is an
  /// uncaught error (T-77), and a copy that could not be written costs only
  /// the next offline boot — the online calendar already has the data.
  Future<void> save(OfflineCalendarSnapshot snapshot) async {
    if (!enabled) return;
    final uid = userId();
    if (uid == null) return;
    try {
      await _store.write(
          uid,
          jsonEncode({
            'v': formatVersion,
            'savedAt': snapshot.savedAt.toUtc().toIso8601String(),
            'month': CareSchedule.isoDate(snapshot.month),
            'members': [for (final m in snapshot.members) m.toRowJson()],
            'roles': [for (final r in snapshot.roles) r.toRowJson()],
            'days': [for (final d in snapshot.days) d.toRowJson()],
            'frozen': [for (final r in snapshot.frozen) r.toRowJson()],
            'ownProfile': snapshot.ownProfile?.toRowJson(),
            'upcoming': [for (final d in snapshot.upcoming) d.toRowJson()],
          }));
    } catch (_) {/* see above: no copy this time */}
  }

  /// The signed-in account's copy, or null — disabled, nobody signed in,
  /// nothing kept, another format, or a copy that no longer parses (which is
  /// removed: a cache that throws on every offline boot is worse than none).
  Future<OfflineCalendarSnapshot?> read() async {
    if (!enabled) return null;
    final uid = userId();
    if (uid == null) return null;
    try {
      final body = await _store.read(uid);
      if (body == null) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['v'] != formatVersion) return null;
      List<Map<String, dynamic>> rows(String key) =>
          (json[key] as List).cast<Map<String, dynamic>>();
      final ymd = (json['month'] as String).split('-').map(int.parse).toList();
      final own = json['ownProfile'] as Map<String, dynamic>?;
      return OfflineCalendarSnapshot(
        savedAt: DateTime.parse(json['savedAt'] as String).toLocal(),
        month: DateTime(ymd[0], ymd[1], ymd[2]),
        members: rows('members').map(Member.fromJson).toList(),
        roles: rows('roles').map(Role.fromJson).toList(),
        days: rows('days').map(CareSchedule.fromJson).toList(),
        frozen: rows('frozen').map(SwapRequest.fromJson).toList(),
        ownProfile: own == null ? null : Member.fromJson(own),
        upcoming: rows('upcoming').map(CareSchedule.fromJson).toList(),
      );
    } catch (_) {
      try {
        await _store.delete(uid);
      } catch (_) {/* nothing more to lose */}
      return null;
    }
  }

  /// Removes every copy on this device, whoever it belonged to. Runs whether or
  /// not the cache is [enabled], and never throws: it sits on the sign-out
  /// path, which must not wait on it or fail because of it.
  Future<void> clear() async {
    try {
      await _store.deleteAll();
    } catch (_) {/* the OS may already have emptied the cache directory */}
  }
}
