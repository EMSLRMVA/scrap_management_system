import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report_summary.dart';
import '../utils/formatters.dart';

class ReportPdfService {
  Future<Uint8List> buildReport(List<ReportSummary> summaries) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(32),
          pageFormat: PdfPageFormat.a4,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Scrap Management Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Generated ${Formatters.dateTime(DateTime.now())}'),
            pw.SizedBox(height: 24),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Report',
                'Purchase',
                'Sales',
                'Expense',
                'Profit',
              ],
              data: [
                for (final summary in summaries)
                  [
                    summary.title,
                    Formatters.money(summary.purchase),
                    Formatters.money(summary.sales),
                    Formatters.money(summary.expense),
                    Formatters.money(summary.profit),
                  ],
              ],
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
