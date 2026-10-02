// T-98 — the Main store listing is published FROM `store/` by the
// `play-listing` workflow (fastlane lane `android listing`), never pasted in
// the Play Console (owner, 02/10/2026).
//
// Two things are proven here, as source, like `play_release_test`:
//   1. the listing files parse by the SAME rules the lane applies, and every
//      field fits Play's limit in both languages — checked in the PR that
//      edits the copy, not after the owner has dispatched and approved;
//   2. the lane touches the listing and nothing else, and the workflow runs
//      only from `main`, behind the owner's approval on `play-production`.
//
// The header grammar and the field order are READ from the Fastfile, so the
// lane and this test cannot drift apart; Play's limits are pinned here on
// their own, because they are Google's, not ours.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

File _fastfile() => File('../fastlane/Fastfile');
File _listingWorkflow() => File('../.github/workflows/play-listing.yml');

/// Play's own limits, in characters (Console → Main store listing).
const _playLimits = {
  'title': 30,
  'short_description': 80,
  'full_description': 4000,
};

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

String _lane(String fastfile, String name) {
  final start = fastfile.indexOf('lane :$name do');
  expect(start, isNot(-1), reason: 'lane $name exists');
  final end = fastfile.indexOf(RegExp(r'\r?\n  end\r?\n'), start);
  expect(end, isNot(-1), reason: 'lane $name closes at two spaces');
  return fastfile.substring(start, end);
}

/// The lane's header regex, `LISTING_HEADER = /…/` in the Fastfile, in Dart.
/// Ruby's `\A`/`\z` anchor the string; a single line has no other start.
RegExp _headerFromFastfile(String fastfile) {
  final ruby = RegExp(r'^LISTING_HEADER = /(.+)/$', multiLine: true)
      .firstMatch(fastfile)
      ?.group(1);
  expect(ruby, isNotNull, reason: 'the Fastfile declares LISTING_HEADER');
  expect(ruby, startsWith(r'\A'));
  expect(ruby, endsWith(r'\z'));
  return RegExp(
      '^${ruby!.substring(2, ruby.length - 2)}\$');
}

/// The lane's field order, `LISTING_FIELDS = [["title", 30], …]`.
List<(String, int)> _fieldsFromFastfile(String fastfile) {
  final line = RegExp(r'^LISTING_FIELDS = (.+)$', multiLine: true)
      .firstMatch(fastfile)
      ?.group(1);
  expect(line, isNotNull, reason: 'the Fastfile declares LISTING_FIELDS');
  return [
    for (final m in RegExp(r'\["([a-z_]+)", (\d+)\]').allMatches(line!))
      (m.group(1)!, int.parse(m.group(2)!)),
  ];
}

List<String> _languagesFromFastfile(String fastfile) {
  final words = RegExp(r'^LISTING_LANGUAGES = %w\[([^\]]*)\]', multiLine: true)
      .firstMatch(fastfile)
      ?.group(1);
  expect(words, isNotNull, reason: 'the Fastfile declares LISTING_LANGUAGES');
  return words!.trim().split(RegExp(r'\s+'));
}

/// Ruby's `String#strip`: ASCII whitespace and NUL, nothing Unicode — Dart's
/// `trim()` would also eat a no-break space the lane sends to Play.
String _strip(String s) =>
    s.replaceAll(RegExp(r'^[\x00\t\n\v\f\r ]+|[\x00\t\n\v\f\r ]+$'), '');

/// The lane's `listing_fields`, rule for rule. Returns the fields, or throws a
/// [FormatException] naming the broken rule.
Map<String, String> _parseListing(
    String source, RegExp header, List<(String, int)> fields) {
  final sections = <(int, List<String>)>[];
  for (final line in source.replaceAll('\r\n', '\n').split('\n')) {
    final m = header.firstMatch(line);
    if (m != null) {
      sections.add((int.parse(m.group(1)!), <String>[]));
    } else if (sections.isEmpty) {
      if (_strip(line).isNotEmpty) {
        throw const FormatException('text before the first header');
      }
    } else {
      sections.last.$2.add(line);
    }
  }
  if (sections.length != fields.length) {
    throw FormatException(
        '${sections.length} sections; the format has ${fields.length}');
  }
  final out = <String, String>{};
  for (var i = 0; i < fields.length; i++) {
    final (field, limit) = fields[i];
    final (declared, lines) = sections[i];
    final text = _strip(lines.join('\n'));
    if (declared != limit) {
      throw FormatException('section ${i + 1} declares <= $declared, '
          'but $field is $limit on Play');
    }
    if (text.isEmpty) throw FormatException('$field is empty');
    if (field != 'full_description' && text.contains('\n')) {
      throw FormatException('$field must be one line');
    }
    // Ruby's `length` counts code points; Dart's counts UTF-16 units.
    if (text.runes.length > limit) {
      throw FormatException(
          '$field has ${text.runes.length} characters; Play takes $limit');
    }
    out[field] = text;
  }
  return out;
}

/// Width × height from a PNG's IHDR, or null when it is not a PNG.
(int, int)? _pngSize(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  late String fastfile;
  late RegExp header;
  late List<(String, int)> fields;

  setUp(() {
    fastfile = _fastfile().readAsStringSync();
    header = _headerFromFastfile(fastfile);
    fields = _fieldsFromFastfile(fastfile);
  });

  group('store/listing-<lang>.txt', () {
    test("the lane's field order carries Play's limits", () {
      expect(fields.map((f) => f.$1).toList(),
          ['title', 'short_description', 'full_description'],
          reason: 'supply reads these exact file names, in this order of '
              'sections');
      for (final (field, limit) in fields) {
        expect(limit, _playLimits[field],
            reason: '$field is $limit in the Fastfile, '
                '${_playLimits[field]} on Play');
      }
    });

    test('the languages are the files, and the file suffix is the Play code',
        () {
      final languages = _languagesFromFastfile(fastfile);
      expect(languages, ['pt-BR', 'en-US'],
          reason: 'pt-BR is the default listing, en-US the translation');
      final files = Directory('../store')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('listing-') && n.endsWith('.txt'))
          .toSet();
      expect(files, {for (final l in languages) 'listing-$l.txt'},
          reason: 'a listing file the lane does not name never reaches Play');
    });

    for (final lang in ['pt-BR', 'en-US']) {
      test("$lang parses by the lane's rules and fits Play's limits", () {
        final listing = _parseListing(
            File('../store/listing-$lang.txt').readAsStringSync(),
            header,
            fields);
        for (final MapEntry(key: field, value: text) in listing.entries) {
          expect(text.runes.length, lessThanOrEqualTo(_playLimits[field]!),
              reason: '$lang $field');
        }
        expect(listing['full_description'], isNot(contains('===')),
            reason: 'a mistyped header is read as description text');
      });
    }

    test('the parser refuses what the lane refuses', () {
      String file(String title, String short, String full,
              {String lead = '', List<int> limits = const [30, 80, 4000]}) =>
          '$lead=== NOME (<= ${limits[0]} caracteres) ===\n$title\n\n'
          '=== CURTA (<= ${limits[1]} caracteres) ===\n$short\n\n'
          '=== COMPLETA (<= ${limits[2]} caracteres) ===\n$full\n';
      Map<String, String> parse(String s) => _parseListing(s, header, fields);

      expect(parse(file('Nome', 'Curta.', 'Completa.\n\nDois.')), {
        'title': 'Nome',
        'short_description': 'Curta.',
        'full_description': 'Completa.\n\nDois.',
      });
      expect(parse(file('Nome', 'Curta.', 'C.').replaceAll('\n', '\r\n')),
          containsPair('title', 'Nome'),
          reason: 'a Windows checkout reads the same');
      for (final (label, source) in [
        ('text before the header', file('N', 'C', 'F', lead: 'oi\n')),
        ('sections swapped', file('N', 'C', 'F', limits: [80, 30, 4000])),
        ('two-line name', file('N\nM', 'C', 'F')),
        ('empty short', file('N', '  ', 'F')),
        ('name over 30', file('N' * 31, 'C', 'F')),
        ('a fourth section', '${file('N', 'C', 'F')}=== X (<= 9 c) ===\nx\n'),
      ]) {
        expect(() => parse(source), throwsFormatException, reason: label);
      }
      expect(parse(file('é' * 30, 'C', 'F'))['title'], 'é' * 30,
          reason: 'characters, not bytes: 30 accented letters fit');
    });
  });

  group('store/screenshots/<lang>/phone-<n>.png (when present)', () {
    test("the Fastfile's names and range are the ones checked here", () {
      expect(fastfile,
          contains(r'SCREENSHOT_NAME = /\Aphone-([1-9]\d*)\.png\z/'));
      expect(fastfile, contains('SCREENSHOT_RANGE = (2..8).freeze'));
    });

    final root = Directory('../store/screenshots');
    final langs = root.existsSync()
        ? root.listSync().whereType<Directory>().toList()
        : <Directory>[];
    for (final dir in langs) {
      final lang = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      test("$lang: phone-1…N, 2 to 8 of them, within Play's sizes", () {
        expect(['pt-BR', 'en-US'], contains(lang),
            reason: 'a folder the lane does not read never reaches Play');
        final shots = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith('phone-'))
            .toList();
        if (shots.isEmpty) return; // nothing here yet: the lane skips it too
        final numbers = <int>[];
        for (final shot in shots) {
          final name = shot.uri.pathSegments.last;
          final m = RegExp(r'^phone-([1-9]\d*)\.png$').firstMatch(name);
          expect(m, isNotNull, reason: '$lang/$name is not phone-<n>.png');
          numbers.add(int.parse(m!.group(1)!));
          final size = _pngSize(shot.readAsBytesSync());
          expect(size, isNotNull, reason: '$lang/$name is not a PNG');
          final (w, h) = size!;
          final long = w > h ? w : h;
          final short = w > h ? h : w;
          expect(short, greaterThanOrEqualTo(320), reason: '$lang/$name');
          expect(long, lessThanOrEqualTo(3840), reason: '$lang/$name');
          expect(long, lessThanOrEqualTo(short * 2),
              reason: '$lang/$name: Play refuses a side over twice the other');
        }
        numbers.sort();
        expect(numbers, [for (var i = 1; i <= numbers.length; i++) i],
            reason: 'numbered with no gap — the lane refuses one');
        expect(numbers.length, inInclusiveRange(2, 8));
      });
    }
  });

  group('the listing lane', () {
    late String lane;

    setUp(() => lane = _code(_lane(fastfile, 'listing')));

    test('it sends the listing and nothing else', () {
      for (final skip in [
        'skip_upload_apk: true',
        'skip_upload_aab: true',
        'skip_upload_changelogs: true',
        'skip_upload_images: true',
        'skip_upload_metadata: false',
      ]) {
        expect(lane, contains(skip));
      }
      // `\b` so that `skip_upload_apk:` is not read as `apk:`.
      for (final never in [r'\btrack_promote_to:', r'\brollout:',
          r'\brelease_status:', r'\baab:', r'\bapk:']) {
        expect(RegExp(never).hasMatch(lane), isFalse,
            reason: 'a listing edit must not move a track or a binary ($never)');
      }
      expect(lane, contains('listing_fields(lang)'),
          reason: 'the text comes from store/, through the checked parser');
    });

    test('screenshots go up only when asked, and REPLACE the phone set', () {
      expect(lane, contains('skip_upload_screenshots: !screenshots'));
      expect(lane, contains('options[:upload_screenshots].to_s == "true"'),
          reason: 'anything but an explicit true leaves the images alone');
      expect(lane, contains('sync_image_upload: true'));
      expect(lane, contains('"phoneScreenshots"'),
          reason: 'only the phone type has local files');
    });

    test('a dry run validates and commits nothing', () {
      expect(lane, contains('validate_only: dry_run'));
      expect(lane, contains('options[:dry_run].to_s == "true"'));
    });

    test('the edit hangs on ONE release of Internal, read and not changed', () {
      expect(lane, contains('track: "internal"'));
      expect(lane, contains('version_code: anchor'),
          reason: 'supply refuses a metadata upload without one release '
              'of the track to hang it on');
    });
  });

  group('play-listing — the owner publishes, from main', () {
    late String workflow;

    setUp(() => workflow = _code(_listingWorkflow().readAsStringSync()));

    test('nothing starts it but a manual dispatch', () {
      final on = workflow.substring(
          workflow.indexOf('\non:'), workflow.indexOf('\npermissions:'));
      expect(on, contains('workflow_dispatch:'));
      for (final trigger in ['push:', 'pull_request', 'schedule:',
          'workflow_run']) {
        expect(on, isNot(contains(trigger)),
            reason: 'what the store says is the owner\'s decision; '
                '`$trigger` would make it an event\'s');
      }
    });

    test('a dry run is the default, and screenshots are opt-in', () {
      final dryRun = workflow.substring(workflow.indexOf('      dry_run:'),
          workflow.indexOf('      upload_screenshots:'));
      expect(dryRun, contains('default: true'),
          reason: 'the first dispatch of any change validates only');
      final shots = workflow.substring(
          workflow.indexOf('      upload_screenshots:'),
          workflow.indexOf('\npermissions:'));
      expect(shots, contains('default: false'),
          reason: 'images go up only after the owner approved the PNGs');
    });

    test("the run waits for the owner's approval, from main only", () {
      final job = _job(workflow, 'listing');
      expect(job, contains("if: github.ref_name == 'main'"));
      expect(job, contains('    environment: play-production\n'),
          reason: "the Environment's required reviewer IS the approval, and "
              'its branch rule is what keeps a branch from reading the key');
      expect(job, contains('cancel-in-progress: false'));
      expect(job, contains("if: env.PLAY_RELEASE_SERVICE_ACCOUNT == ''"));
      expect(job, contains('fastlane android listing'));
    });

    test('inputs never reach the shell as code', () {
      final run =
          workflow.substring(workflow.indexOf('fastlane android listing'));
      expect(run, isNot(contains(r'${{')));
    });
  });

  // S-23's rule for the production credentials, applied to the Play key: an
  // `if` on `main` stops a job from RUNNING elsewhere, but only an
  // Environment whose branch rule is `main` stops a same-repo branch of this
  // PUBLIC repo from READING the secret.
  test('the Play release key is read only inside the two Play Environments',
      () {
    final workflows = Directory('../.github/workflows')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'));
    var readers = 0;
    for (final file in workflows) {
      final source = _code(file.readAsStringSync());
      final lines = source.split('\n');
      final start = lines.indexOf('jobs:');
      if (start == -1) continue;
      for (final line in lines.skip(start + 1)) {
        final m = RegExp(r'^  ([a-z0-9-]+):$').firstMatch(line);
        if (m == null) continue;
        final job = _job(source, m.group(1)!);
        if (!job.contains('secrets.PLAY_RELEASE_SERVICE_ACCOUNT')) continue;
        readers++;
        expect(
            RegExp(r'\n    environment: play-(internal|production)\n')
                .hasMatch(job),
            isTrue,
            reason: '${file.path} · ${m.group(1)} reads the Play key outside '
                'play-internal / play-production');
      }
    }
    expect(readers, greaterThanOrEqualTo(3),
        reason: 'play-internal, play-promote and play-listing — a guard that '
            'finds no reader is green over nothing (T-58)');
  });
}
