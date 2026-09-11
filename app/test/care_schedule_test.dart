// The wire contract of the T-33/T-35 write path — the part of the slice that
// must never drift from the server triggers.
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';

void main() {
  final read = CareSchedule.fromJson(const {
    'id': 7,
    'schedule_date': '2026-08-20',
    'handoff_time': '18:00:00',
    'scheduled_parent_id': 1,
    'actual_parent_id': null,
    'notes': 'levar mochila',
    'created_at': '2026-08-01T00:00:00Z',
    'updated_at': '2026-08-10T00:00:00Z',
    'revision': 3,
    'revision_token': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  });

  test('update payload echoes the token that was read (T-35)', () {
    final json = read.copyWith(scheduledParentId: 2).toUpdateJson();
    expect(json['submitted_token'], 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    expect(json['revision'], 3);
    expect(json['scheduled_parent_id'], 2);
    expect(json['schedule_date'], '2026-08-20');
    // Full row: the T-35 note is explicit that a column-list UPDATE from an
    // authenticated client is rejected.
    expect(json.containsKey('notes'), isTrue);
    expect(json.containsKey('handoff_time'), isTrue);
  });

  test('insert payload has no id/tokens/family_id (server-stamped)', () {
    final json = CareSchedule(
      id: 0,
      scheduleDate: DateTime(2026, 8, 21),
      scheduledParentId: 1,
    ).toInsertJson();
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('revision'), isFalse);
    expect(json.containsKey('submitted_token'), isFalse);
    expect(json.containsKey('revision_token'), isFalse);
    expect(json.containsKey('family_id'), isFalse);
    expect(json['schedule_date'], '2026-08-21');
  });

  test('dates stay ISO 8601 on the wire regardless of display', () {
    expect(CareSchedule.isoDate(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('effective parent falls back from actual to scheduled (T-27)', () {
    expect(read.effectiveParentId, 1);
    final swapped = CareSchedule.fromJson(const {
      'id': 8,
      'schedule_date': '2026-08-22',
      'scheduled_parent_id': 1,
      'actual_parent_id': 2,
    });
    expect(swapped.effectiveParentId, 2);
  });
}
