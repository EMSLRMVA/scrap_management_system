import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/scrap_data_provider.dart';
import '../../reports/report_pdf_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<ScrapDataProvider>().reports;
    final service = ReportPdfService();
    return ModuleScaffold(
      title: 'Reports',
      subtitle:
          'Daily, weekly, monthly, stock, expense, sales, purchase, and profit reports',
      icon: Icons.summarize,
      actions: [
        FilledButton.icon(
          onPressed: () =>
              Printing.layoutPdf(onLayout: (_) => service.buildReport(reports)),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Export PDF'),
        ),
      ],
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            for (final report in reports)
              EnterpriseCard(
                title: report.title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReportLine(
                      label: 'Purchase',
                      value: report.purchase,
                      color: AppTheme.orange,
                    ),
                    _ReportLine(
                      label: 'Sales',
                      value: report.sales,
                      color: AppTheme.blue,
                    ),
                    _ReportLine(
                      label: 'Expense',
                      value: report.expense,
                      color: AppTheme.red,
                    ),
                    const Divider(),
                    _ReportLine(
                      label: 'Profit',
                      value: report.profit,
                      color: report.profit >= 0 ? AppTheme.green : AppTheme.red,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Report Register',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Report')),
                DataColumn(label: Text('Purchase')),
                DataColumn(label: Text('Sales')),
                DataColumn(label: Text('Expense')),
                DataColumn(label: Text('Profit')),
                DataColumn(label: Text('Generated')),
              ],
              rows: [
                for (final report in reports)
                  DataRow(
                    cells: [
                      DataCell(Text(report.title)),
                      DataCell(Text(Formatters.money(report.purchase))),
                      DataCell(Text(Formatters.money(report.sales))),
                      DataCell(Text(Formatters.money(report.expense))),
                      DataCell(Text(Formatters.money(report.profit))),
                      DataCell(Text(Formatters.dateTime(report.generatedAt))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            Formatters.money(value),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
