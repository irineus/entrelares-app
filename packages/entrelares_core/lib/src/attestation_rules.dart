/// F-64 — the verifiable report, as the client mirrors it.
///
/// The server issues the attestation (a summary with initials and counts)
/// and answers `verify_report_attestation` with a closed state; the app adds
/// the QR and the SHA-256 of the final bytes. The id is a CAPABILITY: whoever
/// holds the paper may check it, so it never reaches analytics or crash
/// reports (both sanitizers mask a uuid segment — pinned by tests).
library;

/// The public answer's closed set. Anything else is a future server's shape
/// and reads as [unknown].
enum AttestationState {
  valid,
  pending,
  revoked,
  expired,
  unknown;

  static AttestationState parse(Object? wire) =>
      values.where((s) => s.name == wire).firstOrNull ?? unknown;
}

abstract final class AttestationRules {
  static final RegExp _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  /// A well-formed attestation id (lower-case uuid).
  static bool isId(String? s) => s != null && _uuid.hasMatch(s.toLowerCase());

  /// The app route the QR opens.
  static String path(String id) => '/verificar/$id';

  /// The URL printed in the QR — the environment's web origin, so a dev PDF
  /// opens the QA host and never production.
  static String url(String webOrigin, String id) =>
      '${webOrigin.replaceAll(RegExp(r'/+$'), '')}${path(id)}';

  /// What the PDF prints under the QR: the address without the scheme, short
  /// enough to type from paper.
  static String address(String webOrigin, String id) =>
      url(webOrigin, id).replaceFirst(RegExp(r'^https?://'), '');

  /// A 64-hex fingerprint in groups of four, so a person can compare it by
  /// eye: "ab12 cd34 …".
  static String groupFingerprint(String hex) {
    final clean = hex.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    return [
      for (var i = 0; i < clean.length; i += 4)
        clean.substring(i, i + 4 > clean.length ? clean.length : i + 4)
    ].join(' ');
  }

  /// Whether two fingerprints are the same document (case and spacing
  /// ignored).
  static bool sameFingerprint(String a, String b) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    final x = norm(a);
    return x.length == 64 && x == norm(b);
  }
}
