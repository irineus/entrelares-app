/// F-15: a co-caregiver invitation. Mirrors
/// `Entrelares/Models/FamilyInvitation.cs`.
///
/// Rows are written EXCLUSIVELY by the `create_invitation` / `revoke_invitation`
/// RPCs — the client only reads them (RLS: family-scoped SELECT). The two
/// computed flags below are what the Família page sorts the list by.
class FamilyInvitation {
  final int id;

  /// Which family issued it. The app only ever lists its own (RLS); the gate
  /// needs the column to sweep a family's open invitations clean between
  /// scenarios, and to prove a purge did not reach across families.
  final int? familyId;

  /// When it was issued. The S-15/A-4 purge promise ("permanently erased within
  /// 30 days") is measured from HERE, so the gate backdates this column to age
  /// an invitation instead of waiting a month.
  final DateTime? createdAt;

  final String email;
  final int roleId;

  /// The uuid that travels in `/register?invite=…`.
  final String token;

  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  /// F-56: the pending member this invitation is for. Accepting it attaches
  /// the new auth user to THAT profile; a resend is a new row for the same
  /// profile. Null on a legacy invitation — one that will create a profile.
  final int? profileId;

  const FamilyInvitation({
    required this.id,
    this.familyId,
    this.createdAt,
    required this.email,
    required this.roleId,
    required this.token,
    required this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
    this.profileId,
  });

  /// Still usable: nobody accepted it, nobody revoked it, and the 7-day window
  /// has not closed. A pending invitation HOLDS A SEAT (F-37).
  bool isPending(DateTime nowUtc) =>
      acceptedAt == null && revokedAt == null && expiresAt.isAfter(nowUtc);

  /// Dead by time rather than by decision — the page offers a resend instead of
  /// the link, because the link no longer works.
  bool isExpired(DateTime nowUtc) =>
      acceptedAt == null && revokedAt == null && !expiresAt.isAfter(nowUtc);

  factory FamilyInvitation.fromJson(Map<String, dynamic> json) =>
      FamilyInvitation(
        id: json['id'] as int,
        familyId: json['family_id'] as int?,
        createdAt: _utc(json['created_at'] as String?),
        email: (json['email'] as String?) ?? '',
        roleId: json['role_id'] as int,
        token: (json['token'] as String?) ?? '',
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        acceptedAt: _utc(json['accepted_at'] as String?),
        revokedAt: _utc(json['revoked_at'] as String?),
        profileId: json['profile_id'] as int?,
      );

  static DateTime? _utc(String? wire) =>
      wire == null ? null : DateTime.parse(wire).toUtc();
}
