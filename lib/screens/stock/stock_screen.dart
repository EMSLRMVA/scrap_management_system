import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../constants/app_constants.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/progress_bar.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/status_pill.dart';

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final materials = context.watch<ScrapDataProvider>().materials;
    final totalValue = materials.fold<double>(
      0,
      (sum, item) => sum + item.stockValue,
    );
    return ModuleScaffold(
      title: 'Stock Management',
      subtitle:
          'Opening, purchased, sold, and current stock with auto valuation',
      icon: Icons.inventory_2,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            for (final material in materials)
              EnterpriseCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.green.withValues(
                            alpha: 0.14,
                          ),
                          child: Icon(
                            AppConstants.materialIcons[material.name] ??
                                Icons.inventory,
                            color: AppTheme.green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            material.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (material.isLowStock)
                          const StatusPill(label: 'Low', color: AppTheme.red),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(Formatters.kg(material.currentStockKg)),
                    const SizedBox(height: 8),
                    ProgressBar(
                      value: material.currentStockKg / 5000,
                      color: material.isLowStock
                          ? AppTheme.red
                          : AppTheme.green,
                    ),
                    const SizedBox(height: 10),
                    Text('Value ${Formatters.money(material.stockValue)}'),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Inventory Register',
          trailing: Text(
            'Total ${Formatters.money(totalValue)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.green,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Material')),
                DataColumn(label: Text('Opening')),
                DataColumn(label: Text('Purchased')),
                DataColumn(label: Text('Sold')),
                DataColumn(label: Text('Current')),
                DataColumn(label: Text('Avg Purchase')),
                DataColumn(label: Text('Stock Value')),
              ],
              rows: [
                for (final material in materials)
                  DataRow(
                    cells: [
                      DataCell(Text(material.name)),
                      DataCell(Text(Formatters.kg(material.openingStockKg))),
                      DataCell(Text(Formatters.kg(material.purchasedKg))),
                      DataCell(Text(Formatters.kg(material.soldKg))),
                      DataCell(Text(Formatters.kg(material.currentStockKg))),
                      DataCell(
                        Text(Formatters.money(material.currentBuyingRate)),
                      ),
                      DataCell(Text(Formatters.money(material.stockValue))),
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
