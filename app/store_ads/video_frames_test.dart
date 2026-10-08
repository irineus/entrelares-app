// T-102 (video v2) — the phone screens the ad video animates over, rendered
// from the app's REAL widgets with T-97's fictional demo family, in PT-BR.
//
// ON DEMAND, NEVER IN CI (this directory sits outside `test/`):
//
//     cd app && fvm flutter test store_ads/video_frames_test.dart
//
// writes `store/ads/video/src/<state>.png` — a bare 360×740 dp phone screen at
// 3× (1080×2220), no frame and no caption — and `store/ads/video/build.mjs`
// composes the animation on top of them (captions, phone outline, the tap on
// Aprovar, the cut from the pending request to the swapped day). Nothing on a
// phone is drawn by hand: a state the app cannot reach is not in this list.
//
// Every state shows FREE screens (two caregivers, the calendar, a swap, the
// notifications); the words of the video live in build.mjs under the same
// rules as the images (S-15, U-57, U-31).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store_screenshots/demo_family.dart';
import '../store_screenshots/store_frame.dart'
    show capture, loadBundleFonts, phone, canvasPixelRatio;
import '../test/calendar_slice_test.dart' show FakeCustodyDataSource;

/// One state of the phone: how to reach it.
class PhoneState {
  final String name;
  final FakeCustodyDataSource Function(DemoTexts t) source;
  final ShellTab tab;
  final Future<void> Function(WidgetTester tester, Localization l)? interact;

  const PhoneState(
    this.name, {
    required this.source,
    this.tab = ShellTab.calendar,
    this.interact,
  });
}

Future<void> _goToMonth(WidgetTester tester, Localization l, int month) async {
  var steps = (month - today.month) % 12;
  while (steps-- > 0) {
    await tester.tap(find.byTooltip(l[K.calNextMonth]));
    await tester.pumpAndSettle();
  }
}

Future<void> _openDay(WidgetTester tester, Localization l, DateTime date) async {
  if (date.month != today.month) await _goToMonth(tester, l, date.month);
  final cell = find
      .descendant(of: find.byType(PageView), matching: find.text('${date.day}'))
      .last;
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

/// The plan with [requestedSaturday] already swapped to Bruno — what the
/// calendar shows once Ana approves his request.
List<CareSchedule> _planAfterApproval() {
  final sunday = requestedSaturday.add(const Duration(days: 1));
  return [
    for (final row in plan())
      if (row.scheduleDate == requestedSaturday)
        CareSchedule.fromJson({
          ...row.toRowJson(),
          'actual_parent_id': bruno.id,
          'handoff_time': '18:00',
          'revision': 2,
        })
      else if (row.scheduleDate == sunday)
        CareSchedule.fromJson({...row.toRowJson(), 'handoff_time': '08:00'})
      else
        row,
  ];
}

String _iso(DateTime d) => CareSchedule.isoDate(d);

/// What Ana received lately: Bruno's aviso of today, his swap request and a
/// relato — three FREE notification kinds, rendered by the app's own
/// renderer in the reader's language.
List<AppNotification> _inbox(DemoTexts t) => [
  AppNotification.fromJson({
    'id': 31,
    'recipient_profile_id': ana.id,
    'type': 'day_notice',
    'title': 'Aviso de imprevisto',
    'message': '',
    'params': {
      'date': _iso(today),
      'name': bruno.fullName,
      'kind': 'info',
      'reason': 'atraso',
      'eta': '15',
    },
    'is_read': false,
    'created_at': now.subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
  }),
  AppNotification.fromJson({
    'id': 30,
    'recipient_profile_id': ana.id,
    'type': 'swap_requested',
    'title': 'Nova solicitação de troca',
    'message': '',
    'params': {
      'date': _iso(requestedSaturday),
      'name': bruno.fullName,
      'proposed': 'requester',
      'msg': t.swapMessage,
    },
    'swap_request_id': 10,
    'is_read': true,
    'created_at': now.subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
  }),
  AppNotification.fromJson({
    'id': 29,
    'recipient_profile_id': ana.id,
    'type': 'day_account',
    'title': 'Relato do dia',
    'message': '',
    'params': {'date': _iso(day(-1)), 'name': bruno.fullName, 'kind': 'new'},
    'is_read': true,
    'created_at': now.subtract(const Duration(days: 1, hours: 3)).toUtc().toIso8601String(),
  }),
];

final states = <PhoneState>[
  // The month, today's carer on top, Bruno's request pending.
  PhoneState(
    'cal',
    source: (t) =>
        familySource(premium: false)..frozenRequests = [pendingRequest(t)],
  ),

  // The request, open in the day sheet, awaiting Ana.
  PhoneState(
    'sheet',
    source: (t) => familySource(premium: false)
      ..frozenRequests = [pendingRequest(t)]
      ..pendingForMe = [pendingRequest(t)],
    interact: (tester, l) => _openDay(tester, l, requestedSaturday),
  ),

  // The month after the approval: the Saturday is Bruno's, marked as swapped.
  PhoneState(
    'cal-after',
    source: (t) =>
        FakeCustodyDataSource(members: const [ana, bruno], days: _planAfterApproval())
          ..family = familySource(premium: false).family
          ..roles = familySource(premium: false).roles
          ..children = familySource(premium: false).children
          ..publicSettings = productionFlags
          ..chatActorId = ana.id
          ..expenseActorId = ana.id,
  ),

  // The notifications, on "Todas": the aviso of today on top.
  PhoneState(
    'notif',
    source: (t) => familySource(premium: false)..notifications = _inbox(t),
    tab: ShellTab.communication,
    interact: (tester, l) async {
      await tester.tap(find.text(l[K.notifTabHistory]));
      await tester.pumpAndSettle();
    },
  ),
];

const _out = '../store/ads/video/src';

void main() {
  final l = Localization(AppLanguage.ptBr);
  const texts = DemoTexts(false);

  setUpAll(loadBundleFonts);

  for (final state in states) {
    testWidgets('phone ${state.name}', (tester) async {
      tester.view.physicalSize = phone * canvasPixelRatio;
      tester.view.devicePixelRatio = canvasPixelRatio;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: shellApp(
            state.source(texts),
            language: AppLanguage.ptBr,
            tab: state.tab,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await state.interact?.call(tester, l);
      await tester.pumpAndSettle();
      await capture(tester, boundary, '$_out/${state.name}.png');
    });
  }
}
