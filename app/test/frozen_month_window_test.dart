// Regression, found in production on 01/09/2026 (F-12 + F-24).
//
// `fetchFrozenRequestsForMonth` short-circuited any month whose LAST day was
// already past, before touching the network. A request that stayed pending
// across the turn of the month therefore disappeared from the calendar
// overnight: `_frozenByIso` feeds the ⏳/🔔 cell badge, the tap that opens the
// frozen panel instead of the editor, and the resolve sheet's count — so the
// day became impossible to approve or to cancel from the calendar, while the
// row was untouched in the database and the 48h cron still owned it.
//
// An open request OUTLIVES its day: that is the ATRASADO state the workflow
// models, and `enforce_day_protection` exempts the request's target from the
// past-day rule precisely so an overdue workflow can still be completed. The
// month is a QUERY WINDOW, never a filter on what is still open.
//
// The suite stayed green through the defect because the widget tests' fake
// data source reimplements this method without the guard — so these run the
// REAL data source, over a stubbed PostgREST.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:entrelares_app/services/supabase_custody_data_source.dart';

/// One pending row, shaped as PostgREST answers it.
List<Map<String, Object?>> _pendingRow(DateTime date) => [
      {
        'id': 32,
        'schedule_date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'schedule_id': 232,
        'requesting_profile_id': 1,
        'target_profile_id': 2,
        'proposed_actual_parent_id': 2,
        'status': 'pending',
      }
    ];

void main() {
  late List<Uri> requests;

  SupabaseCustodyDataSource dataSourceAnswering(DateTime pendingDay) {
    requests = [];
    return SupabaseCustodyDataSource(SupabaseClient(
      'https://stub.supabase.test',
      'stub-key',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        return http.Response(jsonEncode(_pendingRow(pendingDay)), 200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    ));
  }

  /// The last day of the month BEFORE this one — a day that is always in the
  /// past, in a month that has always already ended.
  final lastDayOfLastMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 0);
  }();

  test('a month that already ENDED is still queried, and its open request '
      'comes back', () async {
    final ds = dataSourceAnswering(lastDayOfLastMonth);

    final frozen = await ds.fetchFrozenRequestsForMonth(
        lastDayOfLastMonth.year, lastDayOfLastMonth.month);

    expect(requests, isNotEmpty,
        reason: 'the fetcher must not decide by itself that a month which has '
            'ended holds no open request — that is what hid a pending 31/08 '
            'from the calendar on 01/09');
    expect(frozen.single.id, 32);
    expect(frozen.single.scheduleDate, lastDayOfLastMonth);
  });

  test('the query window spans the whole month, first day to last', () async {
    final ds = dataSourceAnswering(lastDayOfLastMonth);

    await ds.fetchFrozenRequestsForMonth(
        lastDayOfLastMonth.year, lastDayOfLastMonth.month);

    final month = lastDayOfLastMonth.month.toString().padLeft(2, '0');
    final query = Uri.decodeFull(requests.single.query);
    expect(query, contains('schedule_date=gte.${lastDayOfLastMonth.year}-$month-01'));
    expect(
        query,
        contains('schedule_date=lte.${lastDayOfLastMonth.year}-$month-'
            '${lastDayOfLastMonth.day.toString().padLeft(2, '0')}'));
    expect(query, contains('status=in.("pending","revert_pending")'),
        reason: 'only OPEN requests freeze a day; the status filter stays '
            'server-side because old months carry a long resolved history');
  });
}
