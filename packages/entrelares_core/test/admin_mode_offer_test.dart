import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  // Monday 21/09/2026 — free reach 7 days (14/09), Premium 6 months (21/03).
  final today = DateTime(2026, 9, 21);

  AdminModeOfferKind offer(
    AdminModeAction action, {
    bool isAdmin = true,
    bool active = false,
    bool? isPremium = true,
    Iterable<DateTime> dates = const [],
  }) =>
      adminModeOfferFor(
        action: action,
        isAdmin: isAdmin,
        adminModeActive: active,
        today: today,
        isPremium: isPremium,
        overrideFreeDays: 7,
        overridePremiumMonths: 6,
        dates: dates,
      );

  group('who is asked', () {
    for (final action in AdminModeAction.values) {
      test('${action.name}: a non-admin never sees the question', () {
        expect(offer(action, isAdmin: false), AdminModeOfferKind.none);
        expect(
            offer(action, isAdmin: false, dates: [DateTime(2026, 9, 20)]),
            AdminModeOfferKind.none);
      });

      test('${action.name}: nothing to offer once the mode is on', () {
        expect(offer(action, active: true), AdminModeOfferKind.none);
      });

      test('${action.name}: an admin with the mode off is asked', () {
        expect(offer(action), AdminModeOfferKind.offer);
        expect(offer(action, isPremium: false), AdminModeOfferKind.offer);
      });
    }
  });

  group('F-40 window on the past', () {
    test('Premium: inside six months is offered, the floor included', () {
      expect(
          offer(AdminModeAction.editPastDay, dates: [DateTime(2026, 9, 20)]),
          AdminModeOfferKind.offer);
      expect(
          offer(AdminModeAction.editPastDay, dates: [DateTime(2026, 3, 21)]),
          AdminModeOfferKind.offer);
    });

    test('Premium: beyond six months is the limit sentence, no question', () {
      expect(
          offer(AdminModeAction.editPastDay, dates: [DateTime(2026, 3, 20)]),
          AdminModeOfferKind.outOfWindow);
    });

    test('Free: inside seven days is offered, the floor included', () {
      expect(
          offer(AdminModeAction.editPastDay,
              isPremium: false, dates: [DateTime(2026, 9, 14)]),
          AdminModeOfferKind.offer);
    });

    test('Free: beyond seven days but inside Premium reach is the gate', () {
      expect(
          offer(AdminModeAction.editPastDay,
              isPremium: false, dates: [DateTime(2026, 9, 13)]),
          AdminModeOfferKind.gate);
    });

    test('Free: beyond every tier is the limit sentence', () {
      expect(
          offer(AdminModeAction.editPastDay,
              isPremium: false, dates: [DateTime(2026, 3, 20)]),
          AdminModeOfferKind.outOfWindow);
    });

    test('unknown entitlement offers and lets the trigger answer', () {
      expect(
          offer(AdminModeAction.editPastDay,
              isPremium: null, dates: [DateTime(2025, 1, 1)]),
          AdminModeOfferKind.offer);
    });

    test('today and future dates are not bound by the window', () {
      expect(
          offer(AdminModeAction.clearDay,
              isPremium: false, dates: [today, DateTime(2026, 12, 1)]),
          AdminModeOfferKind.offer);
    });

    test('several dates: one the mode unlocks is reason enough to ask', () {
      expect(
          offer(AdminModeAction.bulkOverwrite,
              isPremium: false,
              dates: [DateTime(2026, 8, 1), DateTime(2026, 9, 18)]),
          AdminModeOfferKind.offer);
      expect(
          offer(AdminModeAction.bulkOverwrite,
              isPremium: false,
              dates: [DateTime(2026, 1, 1), DateTime(2026, 8, 1)]),
          AdminModeOfferKind.gate);
    });
  });

  test('the analytics values are closed, kebab-case and distinct', () {
    final names = [for (final a in AdminModeAction.values) a.wireName];
    expect(names.toSet().length, names.length);
    for (final n in names) {
      expect(RegExp(r'^[a-z]+(-[a-z]+)*$').hasMatch(n), isTrue, reason: n);
    }
  });

  test('every action names itself, in both languages', () {
    final keys = [
      for (final a in AdminModeAction.values) adminModeOfferMessageKey(a)
    ];
    expect(keys.toSet().length, keys.length);
    for (final lang in [StringsAppPtBr.values, StringsAppEn.values]) {
      for (final k in keys) {
        expect(lang[k], isNotNull, reason: k);
      }
    }
  });
}
