/// S-11 — leaving a family, and deleting one.
///
/// The unanimity rule is the one that must not drift: a MISSING answer is not
/// consent. Silence never deletes a family, and a refusal ends the request
/// outright rather than merely delaying it.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

const ana = LifecycleMember(id: 1, isActiveMember: true, isAdmin: true);
const bruno = LifecycleMember(id: 2, isActiveMember: true);
const carla = LifecycleMember(id: 3, isActiveMember: true);
const brunoAdmin = LifecycleMember(id: 2, isActiveMember: true, isAdmin: true);
const departed = LifecycleMember(id: 4, isActiveMember: false);

void main() {
  group('isLastActiveMember', () {
    test('alone in the family', () {
      expect(FamilyLifecycleRules.isLastActiveMember([ana], 1), isTrue);
    });

    test('a departed member does not keep me company', () {
      expect(FamilyLifecycleRules.isLastActiveMember([ana, departed], 1),
          isTrue);
    });

    test('someone live stays behind', () {
      expect(
          FamilyLifecycleRules.isLastActiveMember([ana, bruno], 1), isFalse);
    });
  });

  group('needsSuccessor', () {
    test('the only admin among several members must name one', () {
      expect(FamilyLifecycleRules.needsSuccessor([ana, bruno], 1), isTrue);
    });

    test('not when another admin remains', () {
      expect(FamilyLifecycleRules.needsSuccessor([ana, brunoAdmin], 1),
          isFalse);
    });

    test('not for a non-admin', () {
      expect(FamilyLifecycleRules.needsSuccessor([ana, bruno], 2), isFalse);
    });

    test('not for the LAST member — there is nobody to inherit, and the family '
        'is going away with them', () {
      expect(FamilyLifecycleRules.needsSuccessor([ana, departed], 1), isFalse);
    });

    test('candidates exclude me and anyone departed', () {
      final candidates = FamilyLifecycleRules.successorCandidates(
          [ana, bruno, carla, departed], 1);
      expect(candidates.map((m) => m.id), [2, 3]);
    });
  });

  group('voters', () {
    test('everyone live except the requester', () {
      final list = FamilyLifecycleRules.voters([ana, bruno, carla, departed], 1);
      expect(list.map((m) => m.id), [2, 3]);
    });

    test('a departed member has no vote', () {
      final list = FamilyLifecycleRules.voters([ana, departed], 1);
      expect(list, isEmpty);
    });
  });

  group('unanimity', () {
    const members = [ana, bruno, carla];

    test('every voter agreeing is unanimity', () {
      expect(
        FamilyLifecycleRules.allAgreed(
          members: members,
          requesterProfileId: 1,
          votes: const [
            DeletionVote(profileId: 2, agreed: true),
            DeletionVote(profileId: 3, agreed: true),
          ],
        ),
        isTrue,
      );
    });

    test('a MISSING answer is not consent — silence never deletes a family',
        () {
      expect(
        FamilyLifecycleRules.allAgreed(
          members: members,
          requesterProfileId: 1,
          votes: const [DeletionVote(profileId: 2, agreed: true)],
        ),
        isFalse,
      );
    });

    test('one refusal breaks it', () {
      expect(
        FamilyLifecycleRules.allAgreed(
          members: members,
          requesterProfileId: 1,
          votes: const [
            DeletionVote(profileId: 2, agreed: true),
            DeletionVote(profileId: 3, agreed: false),
          ],
        ),
        isFalse,
      );
    });

    test('the requester\'s own (absent) vote never blocks it — the request IS '
        'their agreement', () {
      expect(
        FamilyLifecycleRules.allAgreed(
          members: const [ana, bruno],
          requesterProfileId: 1,
          votes: const [DeletionVote(profileId: 2, agreed: true)],
        ),
        isTrue,
      );
    });

    test('no voters at all is never unanimity', () {
      expect(
        FamilyLifecycleRules.allAgreed(
          members: const [ana, departed],
          requesterProfileId: 1,
          votes: const [],
        ),
        isFalse,
      );
    });

    test('anyRefused spots the answer that ends the request', () {
      expect(
        FamilyLifecycleRules.anyRefused(
          members: members,
          requesterProfileId: 1,
          votes: const [DeletionVote(profileId: 3, agreed: false)],
        ),
        isTrue,
      );
      expect(
        FamilyLifecycleRules.anyRefused(
          members: members,
          requesterProfileId: 1,
          votes: const [DeletionVote(profileId: 3, agreed: true)],
        ),
        isFalse,
      );
    });

    test('voteOf tells refusal apart from silence', () {
      const votes = [DeletionVote(profileId: 2, agreed: false)];
      expect(FamilyLifecycleRules.voteOf(votes, 2), isFalse);
      expect(FamilyLifecycleRules.voteOf(votes, 3), isNull);
    });
  });

  group('affordances', () {
    test('only an admin with company may ask for the deletion', () {
      expect(
          FamilyLifecycleRules.canRequestFamilyDeletion(
              isAdmin: true, activeMemberCount: 2),
          isTrue);
      expect(
          FamilyLifecycleRules.canRequestFamilyDeletion(
              isAdmin: false, activeMemberCount: 2),
          isFalse);
    });

    test('a lone member deletes the family by LEAVING, not by asking', () {
      expect(
          FamilyLifecycleRules.canRequestFamilyDeletion(
              isAdmin: true, activeMemberCount: 1),
          isFalse);
    });

    test('"delete it now" needs both the role and the unanimity', () {
      expect(
          FamilyLifecycleRules.canExecuteNow(isAdmin: true, allAgreed: true),
          isTrue);
      expect(
          FamilyLifecycleRules.canExecuteNow(isAdmin: true, allAgreed: false),
          isFalse);
      expect(
          FamilyLifecycleRules.canExecuteNow(isAdmin: false, allAgreed: true),
          isFalse);
    });
  });

  group('the leaving confinement', () {
    test('a leaving member is held on the leaving screen', () {
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/'),
          isTrue);
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/family'),
          isTrue);
    });

    test('but may stay there, and may still sign out', () {
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/leaving'),
          isFalse);
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/login'),
          isFalse);
    });

    test('everyone else moves freely', () {
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: false, location: '/family'),
          isFalse);
    });
  });

  group('F-89', () {
    test('Help is reachable from the exit confinement', () {
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/help'),
          isFalse);
      expect(
          FamilyLifecycleRules.mustStayOnLeavingScreen(
              isLeaving: true, location: '/family'),
          isTrue);
    });

    test('a viewer keeps no family alive', () {
      expect(
          FamilyLifecycleRules.isFamilyRemoval(myId: 1, members: [
            (id: 1, isActiveMember: true, isViewer: false),
            (id: 2, isActiveMember: true, isViewer: true),
          ]),
          isTrue);
      expect(
          FamilyLifecycleRules.isFamilyRemoval(myId: 1, members: [
            (id: 1, isActiveMember: true, isViewer: false),
            (id: 2, isActiveMember: true, isViewer: false),
          ]),
          isFalse);
    });

    test('only an admin leaving a charging subscription is told', () {
      for (final status in ['active', 'scheduled', 'overdue']) {
        expect(
            FamilyLifecycleRules.leavesAPayingSubscription(
                isAdmin: true, subscriptionStatus: status),
            isTrue,
            reason: status);
      }
      expect(
          FamilyLifecycleRules.leavesAPayingSubscription(
              isAdmin: true, subscriptionStatus: 'canceled'),
          isFalse);
      expect(
          FamilyLifecycleRules.leavesAPayingSubscription(
              isAdmin: false, subscriptionStatus: 'active'),
          isFalse);
    });
  });
}
