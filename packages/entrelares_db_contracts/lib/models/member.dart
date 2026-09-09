import 'package:entrelares_core/entrelares_core.dart';

/// The slice of a `profiles` row the calendar needs.
/// Mirrors `Entrelares/Models/Profile.cs`.
class Member {
  final int id;

  /// The family this profile belongs to. The APP never needs it — RLS already
  /// narrows every read to `get_my_family_id()`, so a member the client can see
  /// is a member of its own family by construction. The database GATE is the
  /// reader that does: proving RLS holds means naming the family a row claims
  /// and showing family A never sees family B's. Null when the projection did
  /// not ask for the column.
  final int? familyId;

  final String fullName;
  final int? colorSlot;
  final String? userId;
  final String? leftAt;

  /// U-13: the user's explicit language CHOICE (`profiles.language`), or null
  /// when they never chose. Drives cross-device adoption; the server-side
  /// senders read the generated `language_effective`.
  final String? language;

  /// U-13: what this user's sessions actually render in, recorded on boot
  /// (`profiles.language_detected`). Never drives a screen — it exists so an
  /// e-mail arrives in the same language as the app did.
  final String? languageDetected;

  /// Family admin (🛡️). Client-side it only gates AFFORDANCES (the F-31
  /// invite nudge here); every admin power is re-checked by RLS/triggers.
  final bool isAdmin;

  /// The `roles` row this member holds — resolved against the fetched role list
  /// for display (built-ins translate, F-41 custom roles pass through).
  final int? roleId;

  /// The address on the profile row. Read-only in this client; changing it is
  /// a sudo-gated flow of its own.
  final String? email;

  /// S-11: when this member's data is purged, once they asked to leave. Null
  /// while they are staying.
  final DateTime? deletionScheduledFor;

  /// S-15: which declaration this member accepted — founder or invitee. The
  /// re-consent gate has no invite context left, so the marker is persisted
  /// (and immutable: a trigger preserves it on update).
  final bool joinedViaInvite;

  /// S-13: the policy version stamped at sign-up. Null on legacy profiles,
  /// which the gate deliberately captures rather than backfilling.
  final String? consentPolicyVersion;

  /// S-13: WHEN that consent was given. The pair is the demonstrable-consent
  /// record (LGPD art. 8 §1, where the burden of proof is the controller's), so
  /// the two columns only ever move together — and a refused accept must leave
  /// BOTH untouched, which is what the gate asserts. No screen reads this.
  final DateTime? consentAcceptedAt;

  /// U-23 — the three onboarding stamps. They are the ONLY "seen" flags in the
  /// checklist: every other step reads real family state, because a card that
  /// ticked itself off from a flag would claim someone had finished something
  /// they never did.
  final DateTime? onboardingSwapExplainedAt;
  final DateTime? onboardingTourSeenAt;
  final DateTime? onboardingDismissedAt;

  const Member({
    required this.id,
    this.familyId,
    required this.fullName,
    this.colorSlot,
    this.userId,
    this.leftAt,
    this.language,
    this.languageDetected,
    this.isAdmin = false,
    this.roleId,
    this.email,
    this.deletionScheduledFor,
    this.joinedViaInvite = false,
    this.consentPolicyVersion,
    this.consentAcceptedAt,
    this.onboardingSwapExplainedAt,
    this.onboardingTourSeenAt,
    this.onboardingDismissedAt,
  });

  /// A live, present member holds a family seat (Profile.IsActiveMember).
  bool get isActiveMember => (userId ?? '').isNotEmpty && leftAt == null;

  /// F-56: invited, not yet joined — a profile with NO auth user that has not
  /// departed. Assignable to days and holding a seat and a colour, but never a
  /// swap counterpart (nothing to approve with) and never an admin. The pair
  /// (`user_id`, `left_at`) is the member state: this is the mirror image of
  /// the S-11 tombstone, which is `user_id` NULL *with* `left_at` set.
  bool get isPendingMember => (userId ?? '').isEmpty && leftAt == null;

  /// S-11: departed — or a removed placeholder (F-56). Frozen, no seat, no
  /// colour; the name stays on the history.
  bool get hasLeft => leftAt != null;

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as int,
        familyId: json['family_id'] as int?,
        fullName: (json['full_name'] as String?) ?? '',
        colorSlot: json['color_slot'] as int?,
        userId: json['user_id'] as String?,
        leftAt: json['left_at'] as String?,
        language: json['language'] as String?,
        languageDetected: json['language_detected'] as String?,
        isAdmin: (json['is_admin'] as bool?) ?? false,
        roleId: json['role_id'] as int?,
        email: json['email'] as String?,
        deletionScheduledFor: json['deletion_scheduled_for'] == null
            ? null
            : DateTime.parse(json['deletion_scheduled_for'] as String).toUtc(),
        joinedViaInvite: (json['joined_via_invite'] as bool?) ?? false,
        consentPolicyVersion: json['consent_policy_version'] as String?,
        consentAcceptedAt: _utc(json['consent_accepted_at'] as String?),
        onboardingSwapExplainedAt:
            _utc(json['onboarding_swap_explained_at'] as String?),
        onboardingTourSeenAt: _utc(json['onboarding_tour_seen_at'] as String?),
        onboardingDismissedAt:
            _utc(json['onboarding_dismissed_at'] as String?),
      );

  static DateTime? _utc(String? wire) =>
      wire == null ? null : DateTime.parse(wire).toUtc();

  /// The avatar letter the roster shows — "?" when there is no usable name,
  /// mirroring the web's `GetInitial`.
  String get initial =>
      fullName.trim().isEmpty ? '?' : fullName.trim()[0].toUpperCase();

  MemberView toView() => MemberView(
        id: id,
        fullName: fullName,
        colorSlot: colorSlot,
        isActiveMember: isActiveMember,
        isPendingMember: isPendingMember,
      );
}
