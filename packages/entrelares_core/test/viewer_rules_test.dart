import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-50 — the Visualizador, as the client mirrors it. The DB gate proves the
/// server; this pins what the screen offers.
void main() {
  group('ViewerRules.inviteBlock', () {
    ViewerInviteBlock block(int taken, {bool premium = false}) =>
        ViewerRules.inviteBlock(
          viewersTaken: taken,
          isPremium: premium,
          freeViewers: 1,
          maxViewers: 4,
        );

    test('free: the first viewer is included, the second is Premium', () {
      expect(block(0), ViewerInviteBlock.none);
      expect(block(1), ViewerInviteBlock.freeCap);
    });

    test('Premium: up to the ceiling, then the ceiling says so', () {
      expect(block(3, premium: true), ViewerInviteBlock.none);
      expect(block(4, premium: true), ViewerInviteBlock.maxCap);
    });

    test('the ceiling wins over the free cap when both are hit', () {
      expect(
          ViewerRules.inviteBlock(
              viewersTaken: 2, isPremium: false, freeViewers: 2, maxViewers: 2),
          ViewerInviteBlock.maxCap);
    });
  });

  test('a viewer is in the family, but never assignable to a day', () {
    const viewer = MemberView(id: 3, fullName: 'Vó', isViewer: true);
    const carer = MemberView(id: 1, fullName: 'Ana');
    expect(viewer.isAssignable, isFalse);
    expect(carer.isAssignable, isTrue);
  });

  test('the viewer keys read their seeds until the server answers', () {
    const s = PublicSettings.unloaded;
    expect(s.viewersEnabled, isFalse);
    expect(s.freeViewers, 1);
    expect(s.maxViewers, 4);
    expect(const PublicSettings({'feature.viewers': 'true'}).viewersEnabled,
        isTrue);
  });
}
