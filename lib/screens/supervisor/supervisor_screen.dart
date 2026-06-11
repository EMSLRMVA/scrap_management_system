import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/stat_tile.dart';

class SupervisorScreen extends StatelessWidget {
  const SupervisorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final data = context.watch<ScrapDataProvider>();
    return ModuleScaffold(
      title: 'Supervisor Panel',
      subtitle:
          'Daily yard operations, quick actions, and assigned dispatch work',
      icon: Icons.supervisor_account,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Supervisor',
              value: user?.name ?? 'Supervisor',
              icon: Icons.person,
              color: AppTheme.blue,
            ),
            StatTile(
              label: 'Today Purchase',
              value: Formatters.money(data.metrics.todayPurchaseValue),
              icon: Icons.add_shopping_cart,
              color: AppTheme.green,
            ),
            StatTile(
              label: 'Dispatch Jobs',
              value: data.dispatches.length.toString(),
              icon: Icons.local_shipping,
              color: AppTheme.orange,
            ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Supervisor Actions',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/purchase'),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Quick Purchase'),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/dispatch'),
                icon: const Icon(Icons.local_shipping),
                label: const Text('Dispatch'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/voice'),
                icon: const Icon(Icons.mic),
                label: const Text('Voice Entry'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Recent Activity',
          child: Column(
            children: [
              for (final activity in data.activities.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bolt, color: AppTheme.orange),
                  title: Text(activity.message),
                  subtitle: Text(
                    '${activity.actor} - ${Formatters.dateTime(activity.createdAt)}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
