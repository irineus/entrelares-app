import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

void main() {
  group('AnalyticsCatalog — the names are a series, and a series has one name',
      () {
    // The snapshot IS the point: renaming `swap_requested` to `swap-requested`
    // would end one Umami series and start another with no error anywhere.
    // Adding an event means adding it here too; renaming one means deciding,
    // on purpose, that its history stops.
    test('the catalogue is exactly this list', () {
      expect(AnalyticsCatalog.names, {
        'signup_started', 'signup_step', 'family_created', 'invitee_joined',
        'invite_sent', 'invite_nudge_shown', 'invite_nudge_click',
        'wizard-started', 'wizard_completed', 'swap_requested', 'swap-answered',
        'day-note-saved', 'day-sheet-closed', 'day-notice-sent',
        'day-notice-answered',
        'day-account-saved', 'admin-mode-offer', 'admin-mode-toggle',
        'pdf-export', 'app-open', 'sign-in', 'notification-open',
        'push-nudge-view', 'push-nudge-click', 'push-enable-result',
        'install-hint-view', 'install-hint-open', 'install-hint-dismiss',
        'preference-changed', 'support-contact-sent', 'premium-gate-click',
        'premium-paywall-view', 'premium-interest', 'premium-checkout-start',
        'premium-checkout-return', 'premium-checkout-outcome',
        'premium-cancel', 'premium-reactivate',
      });
    });

    test('no declared prop key names a person', () {
      const forbidden = {'name', 'user', 'userId', 'profile', 'family', 'id',
          'token', 'message', 'note', 'text', 'url', 'path', 'phone'};
      for (final entry in AnalyticsCatalog.props.entries) {
        expect(entry.value.intersection(forbidden), isEmpty,
            reason: '${entry.key} declares an identifying key');
      }
    });
  });

  group('AnalyticsCatalog.filterProps', () {
    test('keeps declared keys with token, bool and number values', () {
      expect(
          AnalyticsCatalog.filterProps(AnalyticsEvents.swapAnswered,
              {'action': 'approved', 'kind': 'revert'}),
          {'action': 'approved', 'kind': 'revert'});
      expect(
          AnalyticsCatalog.filterProps(
              AnalyticsEvents.premiumInterest, {'source': 'family', 'trial': true}),
          {'source': 'family', 'trial': true});
      expect(
          AnalyticsCatalog.filterProps(AnalyticsEvents.premiumCancel,
              {'channel': 'store', 'cycle': '?'}),
          {'channel': 'store', 'cycle': '?'});
    });

    test('drops a key the event did not declare', () {
      expect(
          AnalyticsCatalog.filterProps(AnalyticsEvents.swapAnswered,
              {'action': 'approved', 'profileId': '42'}),
          {'action': 'approved'});
    });

    test('drops any value that is not a token — free text cannot pass', () {
      expect(
          AnalyticsCatalog.filterProps(AnalyticsEvents.supportContactSent, {
            'category': 'Não consigo entrar',
            'signed_in': 'ana@example.com',
          }),
          isNull);
      expect(
          AnalyticsCatalog.filterProps(AnalyticsEvents.preferenceChanged,
              {'pref': 'theme', 'value': 'a' * 33}),
          {'pref': 'theme'});
      expect(
          AnalyticsCatalog.filterProps(
              AnalyticsEvents.pdfExport, {'period': 'https://x/y'}),
          isNull);
    });

    test('an unknown event carries nothing', () {
      expect(AnalyticsCatalog.filterProps('made-up', {'a': 'b'}), isNull);
      expect(AnalyticsCatalog.isKnown('made-up'), isFalse);
    });

    test('every existing funnel prop still passes (no series loses a prop)',
        () {
      final funnel = analyticsFunnelProps(
          channel: 'web',
          cycle: 'annual',
          outcome: 'confirmed',
          mode: 'avulso');
      expect(
          AnalyticsCatalog.filterProps(
              AnalyticsEvents.premiumCheckoutOutcome, funnel),
          funnel);
    });
  });

  group('AnalyticsCatalog.notificationType', () {
    test('every push type the server can send is a known type', () {
      final block = RegExp(r'export const PUSH_TYPES[^=]*=\s*\[([\s\S]*?)\]')
          .firstMatch(repoFile('supabase/functions/_shared/push.ts'));
      expect(block, isNotNull);
      final pushTypes = RegExp(r'"([a-z_]+)"')
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(pushTypes, isNotEmpty);
      expect(AnalyticsCatalog.notificationTypes.containsAll(pushTypes), isTrue,
          reason: 'a new push type would be reported as "other"');
    });

    test('anything else is "other"', () {
      expect(AnalyticsCatalog.notificationType('swap_approved'), 'swap_approved');
      expect(AnalyticsCatalog.notificationType(null), 'other');
      expect(AnalyticsCatalog.notificationType('<script>'), 'other');
    });
  });
}
