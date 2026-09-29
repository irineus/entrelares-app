import 'package:entrelares_core/entrelares_core.dart';

/// The slice of the `families` row the entitlement mirror reads (F-32).
/// Mirrors `Entrelares/Models/Family.cs`: `plan` is written only by the
/// service-role RPC `set_family_plan`; `comp_premium_at` (F-58) only by
/// `admin_set_comp` — the client never writes any of this.
class Family {
  final int id;

  /// Free text the family chose; renamed only through the `rename_family` RPC,
  /// which audits the change into `account_logs`.
  final String name;

  final String plan;
  final DateTime? trialEndsAt;
  final DateTime? compPremiumAt;

  /// F-07: `single` (one plan for every child — every family until F-07) or
  /// `per_child`. Written only by `set_schedule_mode`.
  final String scheduleMode;

  const Family({
    required this.id,
    this.name = '',
    required this.plan,
    this.trialEndsAt,
    this.compPremiumAt,
    this.scheduleMode = 'single',
  });

  bool get isPerChild => scheduleMode == 'per_child';

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        plan: (json['plan'] as String?) ?? 'free',
        trialEndsAt: _utc(json['trial_ends_at'] as String?),
        compPremiumAt: _utc(json['comp_premium_at'] as String?),
        scheduleMode: (json['schedule_mode'] as String?) ?? 'single',
      );

  static DateTime? _utc(String? wire) =>
      wire == null ? null : DateTime.parse(wire).toUtc();

  /// Mirror of `EntitlementService.IsPremium(Family?)`: null → free — the
  /// fail-closed default (an RLS-blocked or missing row never grants).
  static bool isPremiumFamily(Family? family, DateTime nowUtc) =>
      family != null &&
      computeIsPremium(
        plan: family.plan,
        trialEndsAtUtc: family.trialEndsAt,
        nowUtc: nowUtc,
        compPremiumAtUtc: family.compPremiumAt,
      );
}
