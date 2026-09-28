/// U-59 — the Conversa's door to the EXISTING PDF report (F-33/F-64): which
/// period it pre-fills and whether the sheet may promise the QR.
///
/// No new PDF code: the door only opens `ReportsPdfTab` with these values,
/// the Conversa's switch on and the future swaps off; everything stays
/// editable there.
abstract final class ChatExportRules {
  /// The pre-filled window, in days, today included.
  static const int days = 30;

  /// The last [days] days as calendar dates, today the last one.
  static (DateTime, DateTime) initialPeriod(DateTime now) {
    final end = DateTime(now.year, now.month, now.day);
    return (DateTime(end.year, end.month, end.day - (days - 1)), end);
  }

  /// Whether the sheet may say the PDF comes out verifiable by QR. A viewer
  /// issues no attestation (F-64: the client skips it and
  /// `issue_report_attestation` refuses), and with
  /// `feature.report_attestation` off nobody does — S-15: the sentence is
  /// said only where it is true.
  static bool saysQr({required bool viewer, required bool attestationEnabled}) =>
      attestationEnabled && !viewer;
}
