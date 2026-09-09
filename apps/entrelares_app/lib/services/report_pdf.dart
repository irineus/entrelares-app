import 'dart:typed_data';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The faces the document embeds. dart_pdf's built-in Helvetica has NO Unicode
/// support: it DROPS every accent (a report titled "Relatório" prints as
/// "Relatrio") and refuses the em dash. For a Portuguese legal-ish document
/// that is not a cosmetic detail, so Roboto travels with the app and is
/// embedded in every report.
class ReportFonts {
  final pw.Font regular;
  final pw.Font bold;

  const ReportFonts(this.regular, this.bold);
}

ReportFonts? _cachedFonts;

/// Loads (once per process) the vendored faces from the asset bundle.
Future<ReportFonts> loadReportFonts() async {
  final cached = _cachedFonts;
  if (cached != null) return cached;
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  return _cachedFonts = ReportFonts(regular, bold);
}

/// F-33 — **the redesign**: the web renders the document as HTML and asks the
/// browser to print it. A native app has no `print()`, so the same document is
/// composed here as a REAL PDF and handed to the system (share sheet or the
/// native print dialog).
///
/// What did NOT change: the document's content is [buildCustodyReport]'s
/// output — the same assembly, the same numbers as the Resumo screen, the same
/// honest copy (the immutability paragraph and the footer come from the
/// catalog verbatim, in the reader's language).
///
/// Composition is pure Dart with no platform channel, so a widget test can
/// assert the bytes without a device.
///
/// [compress] exists for the tests: an uncompressed document keeps its text
/// readable in the bytes, which is how the suite proves a sentence really
/// reached the page instead of only the model.
Future<Uint8List> buildReportPdf(
  CustodyReport report,
  Localization l, {
  bool compress = true,
  ReportFonts? fonts,
}) async {
  final faces = fonts ?? await loadReportFonts();
  final theme = pw.ThemeData.withFont(base: faces.regular, bold: faces.bold);
  final doc = pw.Document(
    title: l[K.pdfDocTitle],
    author: report.generatedBy,
    creator: 'Entrelares ${report.appVersion}',
    theme: theme,
    compress: compress,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (context) => [
        ..._header(report, l),
        _paragraph(stripRichText(l[K.pdfDocImmutability]), size: 8.5),
        pw.SizedBox(height: 14),
        ..._summarySection(report, l),
        pw.SizedBox(height: 14),
        ..._historySection(report, l),
        pw.SizedBox(height: 16),
        pw.Divider(color: PdfColors.grey400),
        _paragraph(
          stripRichText(l.format(K.pdfDocFooter,
              [report.appVersion, l.formatDateTime(report.generatedAtLocal)])),
          size: 7.5,
          color: PdfColors.grey700,
        ),
      ],
    ),
  );

  return doc.save();
}

List<pw.Widget> _header(CustodyReport report, Localization l) => [
      pw.Text(l[K.pdfDocTitle],
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(l[K.pdfDocSubtitle],
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(3),
        },
        children: [
          _metaRow(l[K.pdfDocFamily], report.familyName),
          if (report.childName != null)
            _metaRow(l[K.pdfDocChild], report.childName!),
          _metaRow(
            l[K.pdfDocPeriod],
            l.format(K.pdfDocPeriodValue, [
              l.formatDate(report.periodStart),
              l.formatDate(report.periodEnd),
              report.totalDays,
            ]),
          ),
          if (report.includesFutureSwaps)
            _metaRow(l[K.pdfDocCriterion], l[K.pdfDocCriterionValue]),
          _metaRow(l[K.pdfDocGeneratedAt],
              l.formatDateTime(report.generatedAtLocal)),
          _metaRow(l[K.pdfDocGeneratedBy], report.generatedBy),
        ],
      ),
      pw.SizedBox(height: 12),
    ];

pw.TableRow _metaRow(String label, String value) => pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(label,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ),
    ]);

List<pw.Widget> _summarySection(CustodyReport report, Localization l) => [
      _sectionTitle(l[K.pdfDocSection1]),
      if (report.caregivers.isEmpty)
        _paragraph(l[K.pdfDocEmptySummary])
      else ...[
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _cell(l[K.pdfDocColCaregiver], bold: true),
                _cell(l[K.pdfDocColRole], bold: true),
                _cell(l[K.pdfDocColPlanned], bold: true),
                _cell(l[K.pdfDocColActual], bold: true),
                if (report.includesFutureSwaps)
                  _cell(l[K.pdfDocColProjected], bold: true),
                _cell(l[K.pdfDocColSwaps], bold: true),
              ],
            ),
            for (final c in report.caregivers)
              pw.TableRow(children: [
                _cell(c.name),
                _cell(c.role),
                _cell('${c.plannedDays}'),
                _cell('${c.actualDays}'),
                if (report.includesFutureSwaps) _cell('${c.projectedDays}'),
                _cell('${c.swapsGiven} · ${c.swapsReceived}'),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        _paragraph(stripRichText(l.format(
            report.includesFutureSwaps
                ? K.pdfDocTotalSwapsFuture
                : K.pdfDocTotalSwaps,
            [report.totalSwaps]))),
      ],
    ];

List<pw.Widget> _historySection(CustodyReport report, Localization l) => [
      _sectionTitle(l[K.pdfDocSection2]),
      if (report.auditEntries.isEmpty)
        _paragraph(l[K.pdfDocEmptyHistory])
      else
        for (final e in report.auditEntries)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${l.formatDateTime(e.timestampLocal)} — ${e.performedBy}: '
                  '${e.actionLabel} ${l.formatDate(e.affectedDate)}.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                // F-45: the origin and the motivation behind the change.
                if (e.originText != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10, top: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // No italic face travels with the app — the origin is
                        // set apart by color, not by a face we cannot embed.
                        pw.Text(e.originText!,
                            style: const pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey800)),
                        if (e.originMessage != null)
                          _detail(l[K.pdfDocRequesterMessage], e.originMessage!),
                        if (e.originNote != null)
                          _detail(l[K.pdfDocApproverMessage], e.originNote!),
                      ],
                    ),
                  ),
                // F-61: the dated facts beyond the diff — set in bold so a
                // reader skimming the history finds them without reading
                // every line; the wording itself stays a plain fact.
                for (final line in e.authorshipLines)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10, top: 2),
                    child: pw.Text(line,
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ),
                for (final change in e.changes)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10, top: 1),
                    child: pw.Text(
                      '${change.label}: ${_changeValue(change)}',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
              ],
            ),
          ),
    ];

/// Mirror of the web's document markup: a two-sided change reads `de → para`,
/// a one-sided one prints whichever value exists.
String _changeValue(AuditFieldChange change) =>
    change.from != null && change.to != null
        ? '${change.from} → ${change.to}'
        : (change.to ?? change.from ?? '');

pw.Widget _detail(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 1),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(
                  fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      ),
    );

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _paragraph(String text,
        {double size = 9, PdfColor color = PdfColors.black}) =>
    pw.Text(text,
        textAlign: pw.TextAlign.justify,
        style: pw.TextStyle(fontSize: size, color: color));

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

/// The file name the share sheet offers — dated, so a folder of them sorts.
String reportFileName(CustodyReport report) {
  String two(int n) => n.toString().padLeft(2, '0');
  String iso(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  return 'entrelares-relatorio-${iso(report.periodStart)}_${iso(report.periodEnd)}.pdf';
}
