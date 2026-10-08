import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('PushRouting.landingFor', () {
    test('a request awaiting me opens on "Para você"', () {
      for (final type in ['swap_requested', 'revert_requested']) {
        expect(PushRouting.landingFor(type), NotificationLanding.incoming,
            reason: '$type leaves the recipient with something to do');
      }
    });

    test('the 24h reminder opens on "Para você"', () {
      // The one worth pinning: it goes to the APPROVER and says the request
      // auto-approves if nobody replies. Burying the most deadline-bound notice
      // the product sends in a read-only list would be the worst placement of
      // any type here.
      expect(PushRouting.landingFor('auto_reminder'),
          NotificationLanding.incoming);
    });

    test('every receipt opens on "Todas"', () {
      // These are about requests that are already closed. "Para você" lists
      // OPEN requests, so it is empty for exactly these — the person taps a
      // notice and arrives at "nada pendente", which reads as the app having
      // lost what it just told them.
      for (final type in [
        'swap_approved',
        'swap_rejected',
        'swap_cancelled',
        'revert_approved',
        'revert_rejected',
        'revert_cancelled',
        'auto_approved',
      ]) {
        expect(PushRouting.landingFor(type), NotificationLanding.history,
            reason: '$type is a receipt, not a call to act');
      }
    });

    // F-52: one type, four wordings, two destinations. The first version
    // routed by type alone, so it had to pick ONE tab for all four — and
    // avoided the empty-tab defect by refusing to push the other three. The
    // owner's first real round sent a courtesy aviso twice and no phone rang.
    test('an aviso that ASKS lands on "Para você", where it is answered', () {
      expect(PushRouting.landingFor('day_notice', kind: 'pickup'),
          NotificationLanding.incoming);
      expect(PushRouting.landingFor('day_notice', kind: 'keep'),
          NotificationLanding.incoming);
    });

    test('an aviso that only TELLS lands on "Todas", where it is listed', () {
      for (final kind in ['info', 'cancelled', 'helping', 'keeping']) {
        expect(PushRouting.landingFor('day_notice', kind: kind),
            NotificationLanding.history,
            reason: kind);
      }
    });

    // A `day_notice` with no kind is a payload we could not read; Todas always
    // holds the row, so the wrong guess this way shows a full list.
    test('an aviso with no kind falls to "Todas"', () {
      expect(PushRouting.landingFor('day_notice'),
          NotificationLanding.history);
    });

    test('a plan that never started opens the wizard (F-78)', () {
      expect(PushRouting.landingFor('plan_ending', kind: 'unplanned'),
          NotificationLanding.planFirst);
      expect(PushRouting.landingFor('plan_ending', kind: 'ending'),
          NotificationLanding.history);
    });

    test("an admin's direct change opens the day or the Histórico (F-81)", () {
      expect(PushRouting.landingFor('day_admin_change', kind: 'single'),
          NotificationLanding.day);
      expect(PushRouting.landingFor('day_admin_change', kind: 'batch'),
          NotificationLanding.auditTrail);
      // A future kind is a receipt until someone decides otherwise.
      expect(PushRouting.landingFor('day_admin_change', kind: 'undone'),
          NotificationLanding.history);
      expect(PushRouting.landingFor('day_admin_change'),
          NotificationLanding.history);
    });

    test('the referral reward opens the plan page (F-80 PR 3)', () {
      expect(PushRouting.landingFor('referral_reward', kind: 'granted'),
          NotificationLanding.plan);
    });

    test('a member\'s ask for Premium opens the plan page (F-102)', () {
      expect(PushRouting.landingFor('premium_request', kind: 'ask'),
          NotificationLanding.plan);
    });

    test('an expired invitation opens the Família page (F-101)', () {
      expect(PushRouting.landingFor('invitation_expired', kind: 'expired'),
          NotificationLanding.family);
      expect(PushRouting.landingFor('invitation_expired'),
          NotificationLanding.family);
    });

    test("the Premium trial's end opens the plan page (F-77)", () {
      expect(PushRouting.landingFor('premium_trial', kind: 'ending'),
          NotificationLanding.plan);
      expect(PushRouting.landingFor('premium_trial', kind: 'ended'),
          NotificationLanding.plan);
    });

    test('an unknown or missing type falls to "Todas"', () {
      // A future writer's notice is a receipt until somebody decides
      // otherwise, and the wrong guess this way shows a full list rather than
      // an empty one.
      expect(PushRouting.landingFor('something_new_in_2027'),
          NotificationLanding.history);
      expect(PushRouting.landingFor(null), NotificationLanding.history);
    });
  });
}
