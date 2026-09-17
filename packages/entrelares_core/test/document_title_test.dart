// U-48 — the document title per route: what the browser's tab and history
// print for each screen. T-64 made the URL name the screen; this names the
// tab, in one shape, in both languages, with the environment prefix in front.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final pt = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);

  group('the shape', () {
    test('a screen reads "<name> · Entrelares", in the reader\'s language', () {
      expect(DocumentTitle.compose('/', pt), 'Calendário · Entrelares');
      expect(DocumentTitle.compose('/', en), 'Calendar · Entrelares');
      expect(DocumentTitle.compose('/family', pt), 'Família · Entrelares');
      expect(DocumentTitle.compose('/reports', en), 'Reports · Entrelares');
    });

    test('the environment prefix goes in front of it all', () {
      expect(
        DocumentTitle.compose(
          '/',
          pt,
          environmentPrefix: environmentTitlePrefix(isProduction: false),
        ),
        '[Dev] Calendário · Entrelares',
      );
      expect(
        DocumentTitle.compose(
          '/splash',
          pt,
          environmentPrefix: environmentTitlePrefix(isProduction: false),
        ),
        '[Dev] Entrelares',
      );
    });

    test('the splash is a gate, not a screen: the brand alone', () {
      expect(DocumentTitle.keyFor('/splash'), isNull);
      expect(DocumentTitle.compose('/splash', pt), 'Entrelares');
    });

    test('the ported page titles lose their " - Entrelares" tail, so every '
        'route reads in ONE shape', () {
      // The catalog carries the old web client's <title>s verbatim.
      expect(pt[K.loginPageTitle], endsWith(' - Entrelares'));
      expect(DocumentTitle.compose('/login', pt), 'Login · Entrelares');
      expect(DocumentTitle.compose('/login', en), 'Sign in · Entrelares');
      expect(
        DocumentTitle.compose('/family/profile', pt),
        'Perfil · Entrelares',
      );
      expect(
        DocumentTitle.compose('/premium/retorno', en),
        'Payment · Entrelares',
      );
      for (final location in DocumentTitle.knownLocations) {
        for (final l in [pt, en]) {
          final title = DocumentTitle.compose(location, l);
          expect(
            title,
            isNot(contains(' - Entrelares')),
            reason: '$location keeps the legacy tail',
          );
          expect(
            ' · Entrelares'.allMatches(title).length,
            lessThanOrEqualTo(1),
          );
          expect(title.trim(), title);
        }
      }
    });
  });

  group('every route the router serves has a name', () {
    test('and none of them is the not-found title', () {
      for (final location in DocumentTitle.knownLocations) {
        final key = DocumentTitle.keyFor(location);
        if (location == RouteRules.splash) continue;
        expect(key, isNotNull, reason: '$location has no title');
        expect(
          key,
          isNot(K.notFoundTitle),
          reason: '$location is served, so it is not "not found"',
        );
        expect(pt[key!], isNotEmpty);
        expect(en[key], isNotEmpty);
      }
    });

    test('the query and the fragment never change the name', () {
      expect(DocumentTitle.keyFor('/notifications?open=42'), K.notifPageTitle);
      expect(DocumentTitle.keyFor('/register?invite=abc'), K.registerPageTitle);
      expect(
        DocumentTitle.keyFor('/#/family'),
        K.navCalendar,
        reason: 'a fragment is not a path',
      );
    });

    test('the other member\'s profile does not print their name', () {
      expect(DocumentTitle.keyFor('/family/profile/42'), K.profPageTitle);
      expect(DocumentTitle.keyFor('/family/profile'), K.profPageTitle);
    });

    test('an unknown path is the not-found screen\'s title (T-64)', () {
      for (final location in [
        '/nope',
        '/family/nope',
        '/family/plan/extra',
        '/premium',
        '/premium/other',
        '/login/extra',
        '/family/profile/42/extra',
      ]) {
        expect(
          DocumentTitle.keyFor(location),
          K.notFoundTitle,
          reason: '$location is not served',
        );
      }
      expect(
        DocumentTitle.compose('/nope', pt),
        'Página não encontrada · Entrelares',
      );
    });

    test('the known-location list covers every path RouteRules names', () {
      // A new route is a one-line addition to `knownLocations`; without this
      // the walk above would silently skip it.
      for (final route in [
        ...RouteRules.publicRoutes,
        ...RouteRules.anonymousOnlyRoutes,
        RouteRules.home,
        FamilyLifecycleRules.leavingRoute,
        FamilyLifecycleRules.policyUpdateRoute,
      ]) {
        expect(
          DocumentTitle.knownLocations,
          contains(route),
          reason:
              '$route is a route the rules name and the title list '
              'does not walk',
        );
      }
    });
  });
}
