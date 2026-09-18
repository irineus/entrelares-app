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
