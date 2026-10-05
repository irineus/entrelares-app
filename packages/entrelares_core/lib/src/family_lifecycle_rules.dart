/// S-11 — the pure rules of leaving a family and of deleting one. Mirror of the
/// derived state in `entrelares-app` `DeletionService.cs`, `ProfilePage.razor`
/// and `FamilyPage.razor`.
///
/// Every one of these is a PRESENTATION rule. The database decides all of it
/// again: `request_account_deletion` refuses without a successor when it needs
/// one, `execute_family_deletion` recounts unanimity, and both demand a live
/// sudo window. What lives here is what the screen must know to show the right
/// question — never to grant anything.
library;

/// One member's answer to a deletion request. Absent (no row) means
/// "aguardando", which is why the caller works with a nullable.
class DeletionVote {
  final int profileId;
  final bool agreed;

  const DeletionVote({required this.profileId, required this.agreed});
}

/// The minimum a member has to look like for these rules.
class LifecycleMember {
  final int id;
  final bool isActiveMember;
  final bool isAdmin;

  const LifecycleMember({
    required this.id,
    required this.isActiveMember,
    this.isAdmin = false,
  });
}

abstract final class FamilyLifecycleRules {
  /// How many days the family has to change its mind — mirrored only to render
  /// the copy; the deadline itself is stamped by the DB.
  static const int deletionGraceDays = 30;

  /// Am I the last live member? Then "leaving" is really "deleting the family",
  /// and the screen has to say so BEFORE the button is pressed.
  static bool isLastActiveMember(
          Iterable<LifecycleMember> members, int myProfileId) =>
      !members.any((m) => m.id != myProfileId && m.isActiveMember);

  /// Am I the only admin left among live members? Then somebody has to inherit
  /// the role, and the DB promotes the successor BEFORE letting me go — a
  /// family with no admin could never invite, rename or resolve anything again.
  static bool needsSuccessor(
      Iterable<LifecycleMember> members, int myProfileId) {
    final active = members.where((m) => m.isActiveMember).toList();
    final me = active.where((m) => m.id == myProfileId).firstOrNull;
    if (me == null || !me.isAdmin) return false;
    // Only meaningful while somebody stays behind to inherit it.
    if (active.length <= 1) return false;
    return !active.any((m) => m.id != myProfileId && m.isAdmin);
  }

  /// Who may become admin in my place.
  static List<LifecycleMember> successorCandidates(
          Iterable<LifecycleMember> members, int myProfileId) =>
      members
          .where((m) => m.isActiveMember && m.id != myProfileId)
          .toList(growable: false);

  /// Who gets to vote on deleting the family: every live member EXCEPT the one
  /// who asked. The requester's own agreement is the request itself.
  static List<LifecycleMember> voters(
          Iterable<LifecycleMember> members, int requesterProfileId) =>
      members
          .where((m) => m.isActiveMember && m.id != requesterProfileId)
          .toList(growable: false);

  /// A member's answer, or null for "aguardando".
  static bool? voteOf(Iterable<DeletionVote> votes, int profileId) =>
      votes.where((v) => v.profileId == profileId).firstOrNull?.agreed;

  /// Unanimity: EVERY voter must have an explicit `agreed` row. A missing row
  /// is not consent — silence never deletes a family.
  static bool allAgreed({
    required Iterable<LifecycleMember> members,
    required int requesterProfileId,
    required Iterable<DeletionVote> votes,
  }) {
    final list = voters(members, requesterProfileId);
    if (list.isEmpty) return false;
    return list.every((m) => voteOf(votes, m.id) == true);
  }

  /// A refusal ends the request outright — it does not merely fail to reach
  /// unanimity, and the panel says so.
  static bool anyRefused({
    required Iterable<LifecycleMember> members,
    required int requesterProfileId,
    required Iterable<DeletionVote> votes,
  }) =>
      voters(members, requesterProfileId)
          .any((m) => voteOf(votes, m.id) == false);

  /// Who may ask for the family to be deleted: an admin, and only while there
  /// is more than one live member — a lone member deletes the family by simply
  /// leaving, and the DB says exactly that.
  static bool canRequestFamilyDeletion({
    required bool isAdmin,
    required int activeMemberCount,
  }) =>
      isAdmin && activeMemberCount > 1;

  /// The "delete it now" affordance: an admin, with unanimity already reached.
  /// Still sudo-gated, and the DB recounts.
  static bool canExecuteNow({
    required bool isAdmin,
    required bool allAgreed,
  }) =>
      isAdmin && allAgreed;

  /// A member on their way out is confined to the leaving screen (and to the
  /// login route, so signing out works). Mirror of `MainLayout.EnforceLeaving`.
  static bool mustStayOnLeavingScreen({
    required bool isLeaving,
    required String location,
  }) =>
      isLeaving &&
      location != leavingRoute &&
      location != loginRoute &&
      // F-89: someone confined to the exit can still ask for help.
      location != helpRoute;

  static const String leavingRoute = '/leaving';
  static const String loginRoute = '/login';
  static const String policyUpdateRoute = '/policy-update';
  static const String helpRoute = '/help';

  /// F-89: the family goes with this member when no CAREGIVER stays — a
  /// viewer only follows the plan and keeps no family alive (F-50). The
  /// exit screen read "Sua conta será apagada" to the last caregiver of a
  /// family with a viewer, while the server removed the whole family.
  static bool isFamilyRemoval({
    required int myId,
    required Iterable<({int id, bool isActiveMember, bool isViewer})> members,
  }) =>
      !members.any((m) => m.id != myId && m.isActiveMember && !m.isViewer);

  /// F-89: an admin leaving a family whose subscription still charges is
  /// told so, with the way to cancel first — the money keeps going after
  /// they are gone.
  static bool leavesAPayingSubscription({
    required bool isAdmin,
    required String? subscriptionStatus,
  }) =>
      isAdmin &&
      (subscriptionStatus == 'active' ||
          subscriptionStatus == 'scheduled' ||
          subscriptionStatus == 'overdue');
}
