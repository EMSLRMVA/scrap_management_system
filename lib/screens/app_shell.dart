import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_top_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final items = _navItems.where((item) => auth.canAccess(item.key)).toList();
    final current = GoRouterState.of(context).uri.pathSegments.isEmpty
        ? 'dashboard'
        : GoRouterState.of(context).uri.pathSegments.first;
    final selectedItem = items.where((item) => item.key == current).firstOrNull;
    final drawer = _NavigationDrawer(items: items, selectedKey: current);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: drawer,
      body: Column(
        children: [
          Builder(
            builder: (context) {
              return AppTopBar(
                title: selectedItem?.label ?? 'Dashboard',
                onMenuPressed: () => Scaffold.of(context).openDrawer(),
                onNotificationsPressed: () => context.go('/notifications'),
              );
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({required this.items, required this.selectedKey});

  final List<_NavItem> items;
  final String selectedKey;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 310,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: const BoxDecoration(color: AppTheme.navy),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.recycling, color: AppTheme.green),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scrap System',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Smart scrap management',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              ListTile(
                dense: true,
                selected: item.key == selectedKey,
                selectedTileColor: AppTheme.blue.withValues(alpha: 0.10),
                selectedColor: AppTheme.blue,
                leading: Icon(item.icon),
                title: Text(item.label),
                trailing: item.key == selectedKey
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/${item.key}');
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _navItems = [
  _NavItem(
    key: 'dashboard',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  _NavItem(
    key: 'purchase',
    label: 'Quick Purchase',
    icon: Icons.add_shopping_cart_outlined,
    selectedIcon: Icons.add_shopping_cart,
  ),
  _NavItem(
    key: 'sellers',
    label: 'Sellers',
    icon: Icons.storefront_outlined,
    selectedIcon: Icons.storefront,
  ),
  _NavItem(
    key: 'customers',
    label: 'Customers',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
  ),
  _NavItem(
    key: 'stock',
    label: 'Stock',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
  ),
  _NavItem(
    key: 'sales',
    label: 'Sales',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
  ),
  _NavItem(
    key: 'expenses',
    label: 'Expenses',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  _NavItem(
    key: 'invoices',
    label: 'Invoices',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
  ),
  _NavItem(
    key: 'ledgers',
    label: 'Ledgers',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  _NavItem(
    key: 'profit-loss',
    label: 'P&L',
    icon: Icons.trending_up_outlined,
    selectedIcon: Icons.trending_up,
  ),
  _NavItem(
    key: 'reports',
    label: 'Reports',
    icon: Icons.summarize_outlined,
    selectedIcon: Icons.summarize,
  ),
  _NavItem(
    key: 'voice',
    label: 'Voice',
    icon: Icons.mic_none,
    selectedIcon: Icons.mic,
  ),
  _NavItem(
    key: 'dispatch',
    label: 'Dispatch',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping,
  ),
  _NavItem(
    key: 'analytics',
    label: 'Analytics',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),
  _NavItem(
    key: 'notifications',
    label: 'Alerts',
    icon: Icons.notifications_none,
    selectedIcon: Icons.notifications_active,
  ),
  _NavItem(
    key: 'owner',
    label: 'Owner',
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
  ),
  _NavItem(
    key: 'admin',
    label: 'Admin',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts,
  ),
  _NavItem(
    key: 'supervisor',
    label: 'Supervisor',
    icon: Icons.supervisor_account_outlined,
    selectedIcon: Icons.supervisor_account,
  ),
  _NavItem(
    key: 'settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  _NavItem(
    key: 'profile',
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];
