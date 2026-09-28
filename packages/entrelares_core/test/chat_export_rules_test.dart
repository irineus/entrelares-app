// U-59 — the Conversa's door to the PDF: the pre-filled window and the QR line.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChatExportRules', () {
    test('the window is the last 30 days, today the last one, as dates', () {
      final (start, end) =
          ChatExportRules.initialPeriod(DateTime(2026, 9, 28, 22, 45));
      expect(end, DateTime(2026, 9, 28));
      expect(start, DateTime(2026, 8, 30));
      expect(end.difference(start).inDays + 1, ChatExportRules.days);
    });

    test('the window crosses a year like any other', () {
      final (start, end) = ChatExportRules.initialPeriod(DateTime(2027, 1, 10));
      expect(start, DateTime(2026, 12, 12));
      expect(end, DateTime(2027, 1, 10));
    });

    test('the QR is promised only where a PDF can carry one (F-64)', () {
      expect(
          ChatExportRules.saysQr(viewer: false, attestationEnabled: true), isTrue);
      // A viewer issues no attestation — the server refuses it.
      expect(
          ChatExportRules.saysQr(viewer: true, attestationEnabled: true), isFalse);
      // The flag off: nobody's PDF has the QR.
      expect(ChatExportRules.saysQr(viewer: false, attestationEnabled: false),
          isFalse);
    });

    test('the lead carries the window as a placeholder, never a typed number', () {
      for (final lang in AppLanguage.values) {
        final lead = Localization(lang)[KApp.chatExportLead];
        expect(lead, contains('{0}'));
        expect(lead, isNot(contains('30')));
      }
    });

    test('the Relatórios tab and the Conversa are told apart in pdf-export', () {
      expect(AnalyticsCatalog.props[AnalyticsEvents.pdfExport],
          {'period', 'source'});
    });
  });
}
