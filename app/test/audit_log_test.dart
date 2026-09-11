// The wire contract of the audit rows (lote 6). They are READ-only for the
// client — what matters here is that the jsonb snapshots survive the trip into
// the pure diff, and that the timestamps land where the timeline expects them.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/activity_log.dart';

void main() {
  group('ActivityLog.fromJson', () {
    final log = ActivityLog.fromJson(const {
      'id': 42,
      'schedule_id': 7,
      'affected_date': '2026-08-20',
      'action': 'UPDATE',
      'old_data': {'actual_parent_id': null, 'notes': 'levar mochila'},
      'new_data': {'actual_parent_id': 2, 'notes': ''},
      'performed_by_id': 1,
      'created_at': '2026-08-19T13:45:00Z',
    });

    test('carries the snapshots as maps the pure diff can read', () {
      expect(log.oldData!['notes'], 'levar mochila');
      expect(log.newData!['actual_parent_id'], 2);
    });

    test('a row without snapshots parses to nulls, not to empty maps', () {
      final insert = ActivityLog.fromJson(const {
        'id': 43,
        'affected_date': '2026-08-21',
        'action': 'INSERT',
        'created_at': '2026-08-19T13:45:00Z',
      });
      expect(insert.oldData, isNull);
      expect(insert.newData, isNull);
      expect(insert.performedById, isNull);
    });

    test('created_at is UTC on the model and LOCAL on the rule view', () {
      expect(log.createdAt.isUtc, isTrue);
      expect(log.view.createdAtLocal, log.createdAt.toLocal());
      expect(log.view.id, 42);
      expect(log.view.action, 'UPDATE');
    });

    test('the view feeds the diff mirror end to end', () {
      final changes = computeAuditDiff(
        log: log.view,
        profiles: const [MemberView(id: 2, fullName: 'Bruno Prado')],
        l: Localization(AppLanguage.ptBr),
      );
      expect(changes.map((c) => c.to), ['Bruno Prado', '—']);
    });
  });

  group('AccountLog.fromJson', () {
    test('parses the S-10 row, values included', () {
      final log = AccountLog.fromJson(const {
        'id': 9,
        'family_id': 3,
        'actor_profile_id': 1,
        'target_profile_id': 2,
        'action': 'role_changed',
        'old_value': 'Mother',
        'new_value': 'Grandmother',
        'created_at': '2026-08-18T10:00:00Z',
      });

      expect(log.action, 'role_changed');
      expect(log.oldValue, 'Mother');
      expect(log.newValue, 'Grandmother');
      expect(log.createdAt.isUtc, isTrue);
    });

    test('a system row has no actor', () {
      final log = AccountLog.fromJson(const {
        'id': 10,
        'family_id': 3,
        'action': 'plan_free_overdue',
        'created_at': '2026-08-18T10:00:00Z',
      });
      expect(log.actorProfileId, isNull);
      expect(log.targetProfileId, isNull);
      expect(log.oldValue, isNull);
    });
  });
}
