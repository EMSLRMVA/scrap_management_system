import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/status_pill.dart';

class OwnerPanelScreen extends StatefulWidget {
  const OwnerPanelScreen({super.key});

  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  final _pin = TextEditingController();
  bool _unlocked = true;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final data = context.watch<ScrapDataProvider>();
    final metrics = data.metrics;

    return ModuleScaffold(
      title: 'Owner Panel',
      subtitle:
          'Protected overview, business analytics, cash flow, and control center',
      icon: Icons.admin_panel_settings,
      actions: [
        StatusPill(
          label: _unlocked ? 'Unlocked' : 'Locked',
          color: _unlocked ? AppTheme.green : AppTheme.red,
          icon: _unlocked ? Icons.lock_open : Icons.lock,
        ),
      ],
      children: [
        if (!_unlocked)
          EnterpriseCard(
            title: 'Enter Password / Fingerprint',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Owner PIN',
                    prefixIcon: Icon(Icons.password),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => setState(() => _unlocked = true),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          )
        else ...[
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
                label: 'Stock Value',
                value: Formatters.money(metrics.stockValue),
                icon: Icons.warehouse,
                color: AppTheme.blue,
              ),
              StatTile(
                label: 'Pending',
                value: Formatters.money(metrics.pendingPayments),
                icon: Icons.pending_actions,
                color: AppTheme.orange,
              ),
              StatTile(
                label: 'Owner',
                value: user?.name ?? 'Owner',
                icon: Icons.verified_user,
                color: AppTheme.purple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cash = EnterpriseCard(
                title: 'Cash Given To Supervisors',
                child: Column(
                  children: const [
                    _CashLine(name: 'Mahesh Kumar', value: 5000),
                    _CashLine(name: 'Suresh Kumar', value: 3000),
                    _CashLine(name: 'Ravi Kumar', value: 2000),
                  ],
                ),
              );
              final controls = EnterpriseCard(
                title: 'Owner Controls',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _unlocked = false),
                      icon: const Icon(Icons.lock),
                      label: const Text('Lock Panel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.backup),
                      label: const Text('Backup Data'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.security),
                      label: const Text('Security Audit'),
                    ),
                  ],
                ),
              );
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [cash, const SizedBox(height: 12), controls],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cash),
                  const SizedBox(width: 12),
                  Expanded(child: controls),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _CashLine extends StatelessWidget {
  const _CashLine({required this.name, required this.value});

  final String name;
  final double value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(name),
      subtitle: const Text('Today'),
      trailing: Text(
        Formatters.money(value),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}
