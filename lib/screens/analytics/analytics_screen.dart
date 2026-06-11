import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/stat_tile.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final topMaterials = data.materials.toList()
      ..sort((a, b) => b.currentStockKg.compareTo(a.currentStockKg));
    final topCustomers = data.customers.take(4).toList();
    final topVendors = data.sellers.take(4).toList();

    return ModuleScaffold(
      title: 'Analytics',
      subtitle: 'Charts, trends, top materials, top vendors, and top customers',
      icon: Icons.analytics,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Stock Value',
              value: Formatters.money(data.metrics.stockValue),
              icon: Icons.warehouse,
              color: AppTheme.green,
            ),
            StatTile(
              label: 'Vendors',
              value: data.metrics.vendorCount.toString(),
              icon: Icons.storefront,
              color: AppTheme.orange,
            ),
            StatTile(
              label: 'Customers',
              value: data.metrics.customerCount.toString(),
              icon: Icons.people,
              color: AppTheme.blue,
            ),
            StatTile(
              label: 'Invoices',
              value: data.metrics.invoiceCount.toString(),
              icon: Icons.description,
              color: AppTheme.purple,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final chart = EnterpriseCard(
              title: 'Material Stock Trend',
              child: SizedBox(
                height: 280,
                child: BarChart(
                  BarChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    barGroups: [
                      for (var index = 0; index < topMaterials.length; index++)
                        BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: topMaterials[index].currentStockKg / 100,
                              width: 22,
                              color: AppTheme.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
            final rankings = EnterpriseCard(
              title: 'Business Rankings',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _RankingTitle('Top Materials'),
                  for (final material in topMaterials.take(4))
                    _RankingRow(
                      label: material.name,
                      value: Formatters.kg(material.currentStockKg),
                    ),
                  const Divider(),
                  const _RankingTitle('Top Vendors'),
                  for (final vendor in topVendors)
                    _RankingRow(label: vendor.name, value: vendor.area),
                  const Divider(),
                  const _RankingTitle('Top Customers'),
                  for (final customer in topCustomers)
                    _RankingRow(label: customer.name, value: customer.area),
                ],
              ),
            );

            if (constraints.maxWidth < 980) {
              return Column(
                children: [chart, const SizedBox(height: 12), rankings],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: chart),
                const SizedBox(width: 12),
                Expanded(child: rankings),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RankingTitle extends StatelessWidget {
  const _RankingTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
