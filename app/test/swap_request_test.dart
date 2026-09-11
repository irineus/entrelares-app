// The swap_requests / notifications row models: wire parsing, the F-20
// resolved-at freeze feed, the F-24 auto badge predicate and the U-13
// paramsJson bridge into the NotificationRenderer.
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';

void main() {
  group('SwapRequest.fromJson', () {
    test('parses the full row, date-only schedule_date', () {
      final r = SwapRequest.fromJson({
        'id': 7,
        'schedule_date': '2026-09-05',
        'schedule_id': 40,
        'requesting_profile_id': 1,
        'target_profile_id': 2,
        'previous_actual_parent_id': null,
        'proposed_actual_parent_id': 2,
        'proposed_handoff_time': '18:00:00',
        'status': 'pending',
        'request_message': 'Tenho consulta',
        'pre_edit_log_id': 99,
        'revert_notes': true,
        'resolved_by': null,
      });
      expect(r.id, 7);
      expect(r.scheduleDate, DateTime(2026, 9, 5));
      expect(r.scheduleId, 40);
      expect(r.proposedHandoffTime, '18:00:00');
      expect(r.requestMessage, 'Tenho consulta');
      expect(r.preEditLogId, 99);
      expect(r.revertNotes, isTrue);
      expect(r.resolvedAtLocal, isNull);
    });

    test('resolvedAtLocal converts the UTC instant to local time', () {
      final r = SwapRequest.fromJson({
        'id': 1,
        'schedule_date': '2026-09-05',
        'requesting_profile_id': 1,
        'target_profile_id': 2,
        'proposed_actual_parent_id': 2,
        'status': 'approved',
        'resolved_at': '2026-09-04T15:00:00+00:00',
      });
      final local = r.resolvedAtLocal;
      expect(local, isNotNull);
      expect(local!.isUtc, isFalse);
      expect(local.toUtc(), DateTime.utc(2026, 9, 4, 15));
    });

    test('isAutoResolved: system + approved flavors only (F-24)', () {
      SwapRequest req(String status, String? by) => SwapRequest(
            id: 1,
            scheduleDate: DateTime(2026, 9, 5),
            requestingProfileId: 1,
            targetProfileId: 2,
            proposedActualParentId: 2,
            status: status,
            resolvedBy: by,
          );
      expect(req('approved', 'system').isAutoResolved, isTrue);
      expect(req('revert_approved', 'system').isAutoResolved, isTrue);
      expect(req('approved', 'user').isAutoResolved, isFalse);
      expect(req('rejected', 'system').isAutoResolved, isFalse);
    });

    test('toView carries what the pure rules need', () {
      final view = SwapRequest.fromJson({
        'id': 3,
        'schedule_date': '2026-09-05',
        'requesting_profile_id': 1,
        'target_profile_id': 2,
        'proposed_actual_parent_id': 2,
        'proposed_handoff_time': '12:00:00',
        'status': 'revert_pending',
      }).toView();
      expect(view.id, 3);
      expect(view.scheduleDate, DateTime(2026, 9, 5));
      expect(view.isRevertPending, isTrue);
      expect(view.proposedHandoffTime, '12:00:00');
    });
  });

  group('AppNotification', () {
    test('parses the row and bridges params into paramsJson', () {
      final n = AppNotification.fromJson({
        'id': 5,
        'recipient_profile_id': 1,
        'type': 'swap_requested',
        'title': 'Nova solicitação de troca',
        'message': 'Ana solicitou…',
        'params': {'date': '2026-09-05', 'name': 'Ana', 'proposed': 'target'},
        'swap_request_id': 7,
        'is_read': false,
      });
      expect(n.paramsJson,
          '{"date":"2026-09-05","name":"Ana","proposed":"target"}');
      expect(n.swapRequestId, 7);
      expect(n.isRead, isFalse);
    });

    test('legacy rows (params null) keep paramsJson null for the renderer '
        'fallback', () {
      final n = AppNotification.fromJson({
        'id': 6,
        'recipient_profile_id': 1,
        'type': 'swap_sent',
        'title': 't',
        'message': 'm',
        'params': null,
      });
      expect(n.paramsJson, isNull);
    });
  });
}
