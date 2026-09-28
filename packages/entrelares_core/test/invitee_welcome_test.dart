// U-58 — the invitee's welcome sheet: which lines each kind of member reads.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('InviteeWelcomeRules', () {
    test('a caregiver and a viewer read different points, three each', () {
      final full = InviteeWelcomeRules.pointKeys(viewer: false);
      final viewer = InviteeWelcomeRules.pointKeys(viewer: true);
      expect(full, hasLength(3));
      expect(viewer, hasLength(3));
      expect(full.toSet().intersection(viewer.toSet()), isEmpty);
    });

    test('the viewer never reads the caregiver line about swaps and colour',
        () {
      // F-50: a viewer changes nothing, holds no colour and takes no part in
      // swaps — the caregiver's "what the others see" would be false for it.
      expect(InviteeWelcomeRules.pointKeys(viewer: true),
          isNot(contains(KApp.welcomeSeen)));
    });

    test('the viewer lines live under app.viewer — the only place the word '
        '"visualizador" and the agenda may be said (vocabulary_test)', () {
      for (final key in InviteeWelcomeRules.pointKeys(viewer: true)) {
        expect(key, startsWith('app.viewer.'));
      }
    });

    test('every line exists in both languages', () {
      for (final lang in AppLanguage.values) {
        final l = Localization(lang);
        for (final viewer in [false, true]) {
          for (final key in [
            KApp.welcomeTitle,
            KApp.welcomeLead,
            KApp.welcomeAction,
            ...InviteeWelcomeRules.pointKeys(viewer: viewer),
          ]) {
            expect(l[key], isNot(key), reason: '$key missing in $lang');
            expect(l[key].trim(), isNotEmpty);
          }
        }
      }
    });

    test('the title and the lead carry the family and the inviter', () {
      final l = Localization(AppLanguage.ptBr);
      expect(l.format(KApp.welcomeTitle, ['Souza']), contains('Souza'));
      expect(l.format(KApp.welcomeLead, ['Ana']), startsWith('Ana '));
    });

    test('the analytics prop is a closed token, never a name (T-78)', () {
      expect(InviteeWelcomeRules.memberProp(viewer: true), 'viewer');
      expect(InviteeWelcomeRules.memberProp(viewer: false), 'full');
      expect(AnalyticsCatalog.props[AnalyticsEvents.inviteeWelcomeView],
          {'channel', 'member'});
    });
  });
}
