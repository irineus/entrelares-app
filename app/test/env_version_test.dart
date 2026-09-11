// `Env.appVersion` exists for ONE reader — the F-17 LGPD export — and a stale
// value there would misdate a legal record. The pubspec is the source of truth
// and the bump ritual already touches it, so this test is what makes the copy
// safe: forget the second half and the build goes red.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/env.dart';

void main() {
  test('Env.appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      Env.appVersion,
      match!.group(1),
      reason: 'bump Env.appVersion in the same delivery as the pubspec',
    );
  });
}
