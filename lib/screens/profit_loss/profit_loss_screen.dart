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

class ProfitLossScreen extends StatelessWidget {
  const ProfitLossScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final metrics = data.metrics;
    final reports = data.reports;
    return ModuleScaffold(
      title: 'Profit & Loss',
      subtitle:
          'Real-time profit equals sales revenue minus purchase cost and expenses',
      icon: Icons.trending_up,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Net Profit',
              value: Formatters.money(metrics.netProfit),
              icon: Icons.savings,
              color: metrics.netProfit >= 0 ? AppTheme.green : AppTheme.red,
            ),
            StatTile(
              label: 'Sales Revenue',
              value: Formatters.money(metrics.todaySalesValue),
              icon: Icons.call_received,
              color: AppTheme.blue,
            ),
            StatTile(
              label: 'Purchase Cost',
              value: Formatters.money(metrics.todayPurchaseValue),
              icon: Icons.call_made,
              color: AppTheme.orange,
            ),
            StatTile(
              label: 'Expenses',
              value: Formatters.money(metrics.todayExpenses),
              icon: Icons.receipt,
              color: AppTheme.red,
            ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Business Trend',
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
                  for (var index = 0; index < reports.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: reports[index].profit / 1000,
                          color: reports[index].profit >= 0
                              ? AppTheme.green
                              : AppTheme.red,
                          width: 24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
