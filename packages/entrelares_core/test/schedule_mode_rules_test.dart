import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-07 (PR 3) — the plan card's door, mirroring `set_schedule_mode`. The DB
/// gate proves the server; this pins what the Crianças page offers.
void main() {
  ScheduleModeOffer offer(
          {bool flag = true, String mode = 'single', int kids = 2}) =>
      ScheduleModeRules.offer(flagOn: flag, mode: mode, childCount: kids);

  test('flag OFF: no card, whatever the family has', () {
    expect(offer(flag: false), ScheduleModeOffer.hidden);
    expect(offer(flag: false, mode: 'per_child'), ScheduleModeOffer.hidden);
  });

  test('one plan: no child, no card; one child, the two-children line', () {
    expect(offer(kids: 0), ScheduleModeOffer.hidden);
    expect(offer(kids: 1), ScheduleModeOffer.needsTwoChildren);
  });

  test('one plan and two children or more: the door to one per child', () {
    expect(offer(kids: 2), ScheduleModeOffer.toPerChild);
    expect(offer(kids: 5), ScheduleModeOffer.toPerChild);
  });

  test('one plan per child: the door back, even with one child left', () {
    expect(offer(mode: 'per_child'), ScheduleModeOffer.toSingle);
    expect(offer(mode: 'per_child', kids: 1), ScheduleModeOffer.toSingle);
  });

  test('the flag reads false until the server says true', () {
    expect(PublicSettings.unloaded.perChildScheduleEnabled, isFalse);
    expect(
        const PublicSettings({'feature.per_child_schedule': 'true'})
            .perChildScheduleEnabled,
        isTrue);
  });
}
