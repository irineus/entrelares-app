/// The `report_attestations` row a family member reads (F-64): one verifiable
/// report issued by the family. Written only through the RPCs; the public
/// check goes through `verify_report_attestation`, never this row.
class ReportAttestation {
  /// The capability the QR carries.
  final String id;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  /// Null until the PDF's final bytes were fingerprinted ("pending").
  final String? sha256;

  const ReportAttestation({
    required this.id,
    required this.issuedAt,
    required this.expiresAt,
    this.periodFrom,
    this.periodTo,
    this.revokedAt,
    this.sha256,
  });

  static DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.parse(raw as String);

  factory ReportAttestation.fromJson(Map<String, dynamic> json) =>
      ReportAttestation(
        id: json['id'] as String,
        periodFrom: _date(json['period_from']),
        periodTo: _date(json['period_to']),
        issuedAt: DateTime.parse(json['issued_at'] as String).toUtc(),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        revokedAt: json['revoked_at'] == null
            ? null
            : DateTime.parse(json['revoked_at'] as String).toUtc(),
        sha256: json['sha256'] as String?,
      );
}
