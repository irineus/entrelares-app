// T-79 — the gate of the QA CHANNEL: a PR's dev APK on the owner's phone and
// a QA web on the dev project, plus `qa.entrelares.app` built from `main`.
//
// The one failure that would be catastrophic here is also the quietest: a QA
// build deployed to the PRODUCTION Pages project, or a production build to the
// QA one. The web picks its database from a single `--dart-define`, so a
// wrong line in a workflow puts a dev-database app on `web.entrelares.app`
// with every check green. Everything else is the usual silent kind: a filter
// that names a directory nobody has any more, or a signing key that travels
// where it should not.
import 'dart:convert';
import 'dart:io';

import 'package:entrelares_app/deep_link_urls.dart';
import 'package:entrelares_app/env.dart';
import 'package:flutter_test/flutter_test.dart';

String _code(String source) => source
    .split(RegExp(r'\r?\n'))
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

String _job(String workflow, String name) {
  final lines = workflow.split('\n');
  final start = lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: 'job $name exists');
  final end = lines.indexWhere(
      (l) => RegExp(r'^  [a-z0-9-]+:$').hasMatch(l), start + 1);
  return lines.sublist(start, end == -1 ? lines.length : end).join('\n');
}

List<String> _inputs(String name) => File('../.github/qa_inputs/$name.txt')
    .readAsLinesSync()
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('#'))
    .toList();

void main() {
  late String workflow;

  setUp(() => workflow =
      _code(File('../.github/workflows/verify.yml').readAsStringSync()));

  group('the two web projects never cross', () {
    test('every QA deploy is a DEV build, to the QA project', () {
      for (final name in ['qa-preview', 'qa-web']) {
        final job = _job(workflow, name);
        expect(job, contains('flutter build web --release --no-web-resources-cdn'),
            reason: '$name builds the web bundle');
        expect(job, isNot(contains('APP_ENV')),
            reason: '$name: on the web the define is the ONLY thing that '
                'selects production — a QA bundle with it talks to the '
                'production database');
        final deploys = RegExp(r'wrangler pages deploy[^\n]*')
            .allMatches(job)
            .map((m) => m.group(0)!)
            .toList();
        expect(deploys, isNotEmpty, reason: '$name deploys');
        for (final line in deploys) {
          expect(line, contains('--project-name=entrelares-web-qa '),
              reason: '$name must deploy to the QA project only: $line');
        }
      }
    });

    test('the production project is named by deploy-web alone', () {
      final all = RegExp(r'--project-name=entrelares-web(?![-\w])')
          .allMatches(workflow)
          .length;
      expect(all, 1,
          reason: 'one publish to `entrelares-web`, the production channel');
      expect(_job(workflow, 'deploy-web'),
          contains('--project-name=entrelares-web --branch=main'));
      expect(File('../.github/qa_pages_project.sh').readAsStringSync(),
          contains('project="entrelares-web-qa"'),
          reason: 'the project the script creates is the one both jobs name');
    });
  });

  group('qa-preview — a PR on the owner\'s phone', () {
    late String job;

    setUp(() => job = _job(workflow, 'qa-preview'));

    test('only for a same-repo PR that is ready, after the gates', () {
      expect(job, contains("github.event_name == 'pull_request'"));
      expect(job, contains('!github.event.pull_request.draft'));
      expect(job,
          contains('github.event.pull_request.head.repo.full_name == github.repository'),
          reason: 'a fork gets no secrets; the job must not pretend to run');
      final needs = RegExp(r'needs:\s*(\[[^\]]*\])').firstMatch(job)!.group(1)!;
      expect(needs, contains('verify'));
      expect(needs, contains('db-gate'),
          reason: 'db-gate is what brings the PR\'s schema to the dev project');
    });

    test('it signs with the DEV key, and only for the length of the job', () {
      expect(job, contains('dev.storeFile='));
      expect(job, isNot(contains('prod.storeFile')),
          reason: 'the upload key lives in the play-internal Environment, '
              'which a PR must never reach');
      expect(job, isNot(contains('environment:')),
          reason: 'a PR job in an Environment limited to main would be refused');
      expect(
          RegExp(r'if: always\(\)\s*\n\s*run: rm -f "\$RUNNER_TEMP/dev\.jks" '
                  r'app/android/key\.properties')
              .hasMatch(job),
          isTrue);
      expect(job, contains('flutter build apk --release --flavor dev'));
    });

    test('the build is decided by the path lists, never by hand', () {
      expect(job, contains('.github/qa_inputs/apk.txt'));
      expect(job, contains('.github/qa_inputs/web.txt'));
      expect(job, contains('cancel-in-progress: true'));
    });
  });

  group('the path lists (owner: mechanical, never a judgement call)', () {
    test('the APK list is what goes inside the APK', () {
      final apk = _inputs('apk');
      for (final input in ['app/lib/', 'app/android/', 'app/pubspec.yaml',
          'packages/entrelares_core/lib/']) {
        expect(apk, contains(input));
      }
      for (final prefix in ['app/test', 'app/integration_test', 'app/web',
          'supabase', '.github', 'docs', 'store']) {
        expect(apk.where((i) => i.startsWith(prefix)), isEmpty,
            reason: '$prefix does not go inside the APK');
      }
    });

    test('the web list is the APK\'s, with web/ for android/', () {
      final web = _inputs('web');
      expect(web, contains('app/web/'));
      expect(web, isNot(contains('app/android/')));
      expect(web.toSet(),
          {..._inputs('apk').where((i) => i != 'app/android/'), 'app/web/'});
    });

    test('every entry names something that EXISTS', () {
      // A renamed directory leaves the filter matching nothing, forever, and
      // green: the PR that needs a device build simply never gets one.
      for (final input in {..._inputs('apk'), ..._inputs('web')}) {
        final path = '../$input';
        final exists = input.endsWith('/')
            ? Directory(path).existsSync()
            : File(path).existsSync();
        expect(exists, isTrue, reason: '$input is in a QA list but not in the repo');
      }
    });
  });

  group('the QA web of main — qa.entrelares.app', () {
    test('it publishes from main after the gates, and never alarms production',
        () {
      final job = _job(workflow, 'qa-web');
      expect(job, contains("github.ref_name == 'main'"));
      final needs = RegExp(r'needs:\s*(\[[^\]]*\])').firstMatch(job)!.group(1)!;
      expect(needs, contains('verify'));
      expect(needs, contains('db-gate'));
      expect(job, contains('--branch=main'));
      final alert = RegExp(r'needs:\s*(\[[^\]]*\])')
          .firstMatch(_job(workflow, 'ops-alert'))!
          .group(1)!;
      expect(alert, isNot(contains('qa-')),
          reason: 'a red QA deploy is not a production incident');
    });

    test('a dev build\'s links open the QA web, a prod build\'s the product', () {
      expect(Env.dev.webOrigin, 'https://qa.entrelares.app');
      expect(Env.prod.webOrigin, 'https://${Env.prod.webHostname}');
      expect(DeepLinkUrls.webOrigin, Env.current.webOrigin);
      expect(DeepLinkUrls.login, '${Env.current.webOrigin}/login');
      expect(_job(workflow, 'qa-web'),
          contains(Uri.parse(Env.dev.webOrigin).host),
          reason: 'the job checks the host the dev build links to');
    });
  });

  group('Firebase App Distribution', () {
    test('the Fastfile names the dev flavour\'s own Firebase app', () {
      final json = jsonDecode(File('android/app/src/dev/google-services.json')
          .readAsStringSync()) as Map<String, dynamic>;
      final client = (json['client'] as List).cast<Map<String, dynamic>>().firstWhere(
          (c) =>
              c['client_info']['android_client_info']['package_name'] ==
              Env.dev.androidPackage);
      final appId = client['client_info']['mobilesdk_app_id'] as String;
      expect(File('../fastlane/Fastfile').readAsStringSync(),
          contains('FIREBASE_DEV_ANDROID_APP = "$appId"'),
          reason: 'an APK sent to another app id is refused, or worse, '
              'lands under an app nobody installs');
    });
  });
}
