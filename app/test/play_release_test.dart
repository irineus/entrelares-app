// T-79 — the gate of the ANDROID release pipeline, cut to the same pattern as
// `web_channel_test`: a workflow cannot be proven by running the app, so what
// it promises is proven as source.
//
// Everything asserted here is silent until it is expensive: a publish that
// skips a gate, an upload key left on a runner, a PR branch able to read it,
// or a pipeline that ships straight to Production without the owner.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _workflow() => File('../.github/workflows/verify.yml');
File _fastfile() => File('../fastlane/Fastfile');

/// The workflow without its comments: several comments quote the very lines
/// these tests look for, and a guard that matches its own explanation passes
/// over a workflow whose code was changed (the T-68 lesson).
String _code(String source) => source
    .split(RegExp(r'\r?\n'))
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

/// One job's body: from its `  name:` line to the next top-level job.
String _job(String workflow, String name) {
  final lines = workflow.split('\n');
  final start = lines.indexOf('  $name:');
  expect(start, isNot(-1), reason: 'job $name exists');
  final end = lines.indexWhere(
      (l) => RegExp(r'^  [a-z0-9-]+:$').hasMatch(l), start + 1);
  return lines.sublist(start, end == -1 ? lines.length : end).join('\n');
}

/// One lane's body in the Fastfile, up to its own `end` — NOT to the next
/// lane, whose header comments (Production, for `promote`) would otherwise be
/// read as this lane's code.
String _lane(String fastfile, String name) {
  final start = fastfile.indexOf('lane :$name do');
  expect(start, isNot(-1), reason: 'lane $name exists');
  final end = fastfile.indexOf(RegExp(r'\r?\n  end\r?\n'), start);
  expect(end, isNot(-1), reason: 'lane $name closes at two spaces');
  return fastfile.substring(start, end);
}

void main() {
  group('play-internal — merge to Internal testing', () {
    late String job;

    setUp(() => job = _job(_code(_workflow().readAsStringSync()), 'play-internal'));

    test('it waits for EVERY gate and the production schema, and only on main',
        () {
      final needs = RegExp(r'needs:\s*(\[[^\]]*\])').firstMatch(job)?.group(1);
      expect(needs, isNotNull);
      for (final gate in ['verify', 'db-gate', 'web-e2e', 'db-prod']) {
        expect(needs, contains(gate),
            reason: 'a phone must not receive what the $gate gate did not see');
      }
      expect(needs, isNot(contains('deploy-web')),
          reason: 'a red deploy-web is usually the EDGE (T-73) — it says '
              'nothing about an Android binary');
      expect(job, contains("github.ref_name == 'main'"));
    });

    test('its secrets live in an Environment only main can deploy to', () {
      // The repo is PUBLIC. The job's `if` keeps it from running on a PR; the
      // Environment's branch rule is what keeps a same-repo PR branch from
      // READING the key — a workflow edited on that branch has no `if`.
      expect(job, contains('environment: play-internal'));
    });

    test('it never cancels an upload half-way', () {
      expect(job, contains('cancel-in-progress: false'));
    });

    test('the upload key exists only for the job, and only the PROD one', () {
      expect(job, contains(r'"$RUNNER_TEMP/upload.jks"'),
          reason: 'the keystore goes OUTSIDE the checkout');
      expect(
          RegExp(r'if: always\(\)\s*\n\s*run: rm -f "\$RUNNER_TEMP/upload\.jks" '
                  r'app/android/key\.properties')
              .hasMatch(job),
          isTrue,
          reason: 'the key is removed whatever happened before');
      expect(job, contains('prod.storeFile='));
      expect(job, isNot(contains('dev.storeFile')),
          reason: 'the dev keystore never travels with the publishing one');
    });

    test('it builds the prod flavour and uploads THAT bundle', () {
      expect(job, contains('flutter build appbundle --release --flavor prod'));
      expect(
          job,
          contains('fastlane android beta '
              'aab:app/build/app/outputs/bundle/prodRelease/app-prod-release.aab'));
      final guard = job.indexOf('fastlane android version_guard');
      final build = job.indexOf('flutter build appbundle');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(build),
          reason: 'a merge with nothing new to send must not spend a build');
    });

    test('it disarms, loudly, while the service account is missing', () {
      expect(job, contains("if: env.PLAY_RELEASE_SERVICE_ACCOUNT == ''"));
      expect(job, contains('PLAY_RELEASE_SERVICE_ACCOUNT'));
    });

    test('a manual dispatch on main republishes it too (F-63)', () {
      final condition = RegExp(r'if: (.+)').firstMatch(job)!.group(1)!;
      expect(condition, contains("github.event_name == 'push'"));
      expect(condition, contains("github.event_name == 'workflow_dispatch'"));
    });

    test('a red here raises the ops alert, naming the right channel', () {
      final workflow = _code(_workflow().readAsStringSync());
      final alert = _job(workflow, 'ops-alert');
      expect(alert, contains('play-internal]'),
          reason: 'a merge that never reaches Android is an incident too');
      expect(alert, contains('android_only'));
      final script = _code(File('../.github/ops_alert.sh').readAsStringSync());
      expect(script, contains('o Android não subiu para a Internal testing'));
    });
  });

  group('the Fastfile', () {
    late String fastfile;

    setUp(() => fastfile = _fastfile().readAsStringSync());

    test('the merge lane uploads to Internal testing and nowhere else', () {
      final beta = _lane(fastfile, 'beta');
      expect(beta, contains('track: "internal"'));
      expect(beta, isNot(contains('production')),
          reason: 'Production is the owner\'s decision, never a merge\'s');
      expect(beta, isNot(contains('track_promote_to')));
    });

    test('the guard reads EVERY track a versionCode may already live on', () {
      expect(fastfile,
          contains('PLAY_TRACKS = %w[internal alpha beta production].freeze'));
      final guard = _lane(fastfile, 'version_guard');
      expect(guard, contains('UI.user_error!'),
          reason: 'a LOWER code must fail, not skip: skipping ships a merge '
              'that never reaches Android');
    });

    test('credentials come from the environment, never from a file', () {
      expect(fastfile, contains('ENV["PLAY_RELEASE_SERVICE_ACCOUNT"]'));
      expect(fastfile, isNot(contains('json_key:')),
          reason: 'a key file on disk is a key file someone forgets to delete');
      expect(fastfile, isNot(contains('"PLAY_SERVICE_ACCOUNT"')),
          reason: 'the billing account is not the release account (owner, '
              '22/09/2026)');
    });

    test('fastlane is pinned, and the lockfile agrees', () {
      final pin = RegExp(r'gem "fastlane", "([\d.]+)"')
          .firstMatch(File('../Gemfile').readAsStringSync())
          ?.group(1);
      expect(pin, isNotNull, reason: 'the Gemfile pins an exact version');
      expect(File('../Gemfile.lock').readAsStringSync(),
          contains('    fastlane ($pin)'));
    });
  });

  group('play-promote — Production, only by the owner', () {
    late String workflow;

    setUp(() => workflow =
        _code(File('../.github/workflows/play-promote.yml').readAsStringSync()));

    test('nothing starts it but a manual dispatch', () {
      final on = workflow.substring(
          workflow.indexOf('\non:'), workflow.indexOf('\npermissions:'));
      expect(on, contains('workflow_dispatch:'));
      for (final trigger in ['push:', 'pull_request', 'schedule:', 'workflow_run']) {
        expect(on, isNot(contains(trigger)),
            reason: "Production is the owner's decision (22/09/2026); "
                "`$trigger` would make it an event's");
      }
    });

    test("the run waits for the owner's approval, from main only", () {
      expect(workflow, contains('environment: play-production'),
          reason: "the Environment's required reviewer IS the approval");
      expect(workflow, contains("if: github.ref_name == 'main'"));
      expect(workflow, contains('cancel-in-progress: false'));
    });

    test('free-text inputs never reach the shell as code', () {
      final run = workflow.substring(workflow.indexOf('fastlane android promote'));
      expect(run, isNot(contains(r'${{')),
          reason: 'inputs go through `env:`; interpolated into `run:` they '
              'are a shell injection');
    });

    test('the lane promotes from Internal, the one testing track', () {
      final promote = _lane(_fastfile().readAsStringSync(), 'promote');
      expect(promote, contains('track: "internal"'));
      expect(promote, contains('track_promote_to: "production"'));
      expect(promote, contains('release_notes_metadata(code)'),
          reason: 'a promotion carries its notes, or it does not happen');
    });
  });

  group('release notes (store/release-notes/<versionCode>/)', () {
    // Checked on the way IN, in the PR that writes them — the promotion lane
    // refuses the same things, but only after the owner has dispatched it.
    final root = Directory('../store/release-notes');
    final folders = root.existsSync()
        ? (root.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <Directory>[];

    test('every folder is a versionCode', () {
      for (final dir in folders) {
        final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        expect(RegExp(r'^[1-9]\d*$').hasMatch(name), isTrue,
            reason: '$name is not a versionCode');
      }
    });

    for (final dir in folders) {
      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      test("$name carries both languages, within Play's 500 characters", () {
        final files = dir.listSync().whereType<File>().map((f) =>
            f.uri.pathSegments.last).toSet();
        expect(files, {'pt-BR.txt', 'en-US.txt'},
            reason: 'Play shows the notes per language; a missing one '
                'refuses the promotion after the owner dispatched it');
        for (final lang in files) {
          final text =
              File('${dir.path}/$lang').readAsStringSync().trim();
          expect(text, isNotEmpty, reason: '$name/$lang is empty');
          expect(text.length, lessThanOrEqualTo(500),
              reason: '$name/$lang has ${text.length} characters');
        }
      });
    }
  });

  group('release signing', () {
    test('each flavour is signed by ITS entries, not by the file existing', () {
      // The CI job writes `prod.*` only. A Gradle file that demanded both
      // flavours would fail that job at configuration — or push someone into
      // copying the dev keystore next to the publishing one.
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('val signedFlavors'));
      expect(gradle, isNot(contains('hasKeyProperties')));
    });
  });
}
