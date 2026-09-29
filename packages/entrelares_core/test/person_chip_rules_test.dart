import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-07 (owner's QA, 29/09/2026) — the calendar's people, with avatars.
void main() {
  group('childInitials', () {
    test('one letter while unique', () {
      expect(childInitials({1: 'Benicio', 2: 'Catarina', 3: 'Lucas'}),
          {1: 'B', 2: 'C', 3: 'L'});
    });

    test('a shared first letter takes two', () {
      expect(childInitials({1: 'Benicio', 2: 'Bianca', 3: 'Lucas'}),
          {1: 'Be', 2: 'Bi', 3: 'L'});
    });

    test('two shared letters add the place in the order', () {
      expect(childInitials({1: 'Ana', 2: 'Ana Clara'}), {1: 'An1', 2: 'An2'});
    });
  });

  group('legendNames', () {
    test('the first name while unique; the role is gone', () {
      expect(legendNames({1: 'Irineu Junior', 2: 'Fernanda Daroit'}),
          {1: 'Irineu', 2: 'Fernanda'});
    });

    test("a shared first name takes the surname's initial", () {
      expect(legendNames({1: 'Ana Souza', 2: 'Ana Lima', 3: 'Bruno'}),
          {1: 'Ana S.', 2: 'Ana L.', 3: 'Bruno'});
    });
  });

  test('memberLinkTarget: my chip, an admin, anyone else', () {
    expect(memberLinkTarget(isOwn: true, iAmAdmin: false),
        MemberLinkTarget.ownProfile);
    expect(memberLinkTarget(isOwn: false, iAmAdmin: true),
        MemberLinkTarget.memberProfile);
    expect(memberLinkTarget(isOwn: false, iAmAdmin: false),
        MemberLinkTarget.family);
  });

  group('fitSplitCell', () {
    test('two carers on a 48 dp cell keep the usual avatar', () {
      final fit = fitSplitCell(
          width: 48, avatarDiameter: 18, childrenPerColumn: [2, 1]);
      expect(fit.carerDiameter, 18);
      expect(fit.shown, [2, 1]);
      expect(fit.more, [0, 0]);
    });

    test('three carers shrink the avatars, never under the floors', () {
      final fit = fitSplitCell(
          width: 48, avatarDiameter: 18, childrenPerColumn: [1, 1, 1]);
      expect(fit.carerDiameter, lessThan(18));
      expect(fit.carerDiameter, greaterThanOrEqualTo(SplitCellFit.minCarer));
      expect(fit.childDiameter, greaterThanOrEqualTo(SplitCellFit.minChild));
    });

    test('more children than fit: the last place is "+N"', () {
      final fit = fitSplitCell(
          width: 48, avatarDiameter: 18, childrenPerColumn: [4, 1]);
      expect(fit.shown.first + fit.more.first, 4);
      expect(fit.more.first, greaterThan(0));
      expect(fit.more.last, 0);
    });
  });
}
