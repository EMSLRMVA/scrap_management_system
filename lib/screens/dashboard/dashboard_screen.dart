import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../constants/app_constants.dart';
import '../../models/dashboard_metrics.dart';
import '../../models/ledger_entry.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final metrics = data.metrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            desktop ? 18 : 10,
            desktop ? 18 : 10,
            desktop ? 18 : 10,
            14,
          ),
          children: [
            if (desktop)
              _DesktopCommandCenter(data: data, metrics: metrics)
            else
              _MobileCommandCenter(data: data, metrics: metrics),
          ],
        );
      },
    );
  }
}

class _MobileCommandCenter extends StatelessWidget {
  const _MobileCommandCenter({required this.data, required this.metrics});

  final ScrapDataProvider data;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TodayHeader(),
        const SizedBox(height: 8),
        _MetricGrid(data: data, metrics: metrics),
        const SizedBox(height: 8),
        _CountStrip(data: data, metrics: metrics),
        const SizedBox(height: 8),
        _LiveActivityPanel(data: data, compact: true),
        const SizedBox(height: 8),
        _StockPulsePanel(data: data, compact: true),
        const SizedBox(height: 8),
        _DashboardActions(),
      ],
    );
  }
}

class _DesktopCommandCenter extends StatelessWidget {
  const _DesktopCommandCenter({required this.data, required this.metrics});

  final ScrapDataProvider data;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 390,
          child: _MobileCommandCenter(data: data, metrics: metrics),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              _SmartFeaturePanel(),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _RecentInvoicePanel(data: data)),
                  const SizedBox(width: 14),
                  Expanded(child: _LedgerPreviewPanel(data: data)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ReportsShortcutPanel()),
                  const SizedBox(width: 14),
                  Expanded(child: _LiveActivityPanel(data: data)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Today, ${Formatters.date(DateTime.now())}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: AppTheme.green, size: 8),
                SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(
                    color: AppTheme.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.data, required this.metrics});

  final ScrapDataProvider data;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final todayPurchases = data.purchases.where(
      (purchase) => _isToday(purchase.createdAt),
    );
    final paidToday = todayPurchases.fold<double>(
      0,
      (total, purchase) => total + purchase.paidAmount,
    );
    final pendingToday = todayPurchases.fold<double>(
      0,
      (total, purchase) =>
          total + purchase.balanceAmount.clamp(0, double.infinity),
    );

    final cards = [
      _MetricSpec(
        label: 'Total Purchase (KG)',
        value: Formatters.kg(metrics.todayPurchaseKg),
        caption:
            '+ ${Formatters.kg(data.purchases.isEmpty ? 0 : data.purchases.first.totalWeightKg)}',
        icon: Icons.group,
        color: AppTheme.green,
      ),
      _MetricSpec(
        label: 'Purchase Value',
        value: Formatters.money(metrics.todayPurchaseValue),
        caption: '+ ${Formatters.money(metrics.todayPurchaseValue)}',
        icon: Icons.currency_rupee,
        color: AppTheme.blue,
      ),
      _MetricSpec(
        label: 'Total Sales (KG)',
        value: Formatters.kg(metrics.todaySalesKg),
        caption: '+ ${Formatters.kg(metrics.todaySalesKg)}',
        icon: Icons.groups_2,
        color: AppTheme.green,
      ),
      _MetricSpec(
        label: 'Sales Value',
        value: Formatters.money(metrics.todaySalesValue),
        caption: '+ ${Formatters.money(metrics.todaySalesValue)}',
        icon: Icons.trending_up,
        color: AppTheme.blue,
      ),
      _MetricSpec(
        label: 'Paid Amount',
        value: Formatters.money(paidToday),
        caption: 'Cash paid today',
        icon: Icons.price_check,
        color: AppTheme.orange,
      ),
      _MetricSpec(
        label: 'Pending Amount',
        value: Formatters.money(pendingToday),
        caption: 'Vendor balance',
        icon: Icons.notification_important,
        color: AppTheme.red,
      ),
    ];

    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.42,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) => _DashboardMetricCard(spec: cards[index]),
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({required this.spec});

  final _MetricSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: spec.color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.09,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: spec.color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(spec.icon, color: spec.color, size: 21),
            ],
          ),
          const Spacer(),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              spec.value,
              style: TextStyle(
                color: spec.color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            spec.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: spec.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSpec {
  const _MetricSpec({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
}

class _CountStrip extends StatelessWidget {
  const _CountStrip({required this.data, required this.metrics});

  final ScrapDataProvider data;
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final stockKg = data.materials.fold<double>(
      0,
      (total, material) => total + material.currentStockKg,
    );
    final counts = [
      (
        'Sellers',
        metrics.vendorCount.toString(),
        Icons.person_add_alt_1,
        AppTheme.blue,
      ),
      (
        'Items',
        data.materials.length.toString(),
        Icons.inventory_2,
        AppTheme.purple,
      ),
      (
        'Invoices',
        metrics.invoiceCount.toString(),
        Icons.description,
        AppTheme.blue,
      ),
      ('Stock (KG)', stockKg.toStringAsFixed(0), Icons.scale, AppTheme.ink),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (final count in counts)
            Expanded(
              child: _CountTile(
                label: count.$1,
                value: count.$2,
                icon: count.$3,
                color: count.$4,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _LiveActivityPanel extends StatelessWidget {
  const _LiveActivityPanel({required this.data, this.compact = false});

  final ScrapDataProvider data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final activities = data.activities.take(compact ? 3 : 5).toList();
    return _Panel(
      title: 'Live Activities (Real Time)',
      trailing: TextButton(
        onPressed: () => context.go('/notifications'),
        child: const Text('View All'),
      ),
      child: Column(
        children: [
          for (final activity in activities)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      Formatters.time(activity.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppTheme.orange.withValues(alpha: 0.14),
                    child: const Icon(
                      Icons.bolt,
                      size: 15,
                      color: AppTheme.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activity.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StockPulsePanel extends StatelessWidget {
  const _StockPulsePanel({required this.data, this.compact = false});

  final ScrapDataProvider data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final materials = data.materials.take(compact ? 3 : 6).toList();
    return _Panel(
      title: 'Stock Summary',
      trailing: TextButton(
        onPressed: () => context.go('/stock'),
        child: const Text('View All'),
      ),
      child: Column(
        children: [
          for (final material in materials)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Icon(
                    AppConstants.materialIcons[material.name] ??
                        Icons.inventory_2,
                    color: material.isLowStock ? AppTheme.red : AppTheme.green,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      material.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.kg(material.currentStockKg),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Voice Entry',
            icon: Icons.mic,
            color: AppTheme.purple,
            onTap: () => context.go('/voice'),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _ActionButton(
            label: 'Scan Seller QR',
            icon: Icons.qr_code_scanner,
            color: AppTheme.green,
            onTap: () => context.go('/sellers'),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _ActionButton(
            label: 'Quick Purchase',
            icon: Icons.flash_on,
            color: AppTheme.blue,
            onTap: () => context.go('/purchase'),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.10)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RecentInvoicePanel extends StatelessWidget {
  const _RecentInvoicePanel({required this.data});

  final ScrapDataProvider data;

  @override
  Widget build(BuildContext context) {
    final purchase = data.purchases.firstOrNull;
    return _Panel(
      title: 'Latest Invoice',
      trailing: TextButton(
        onPressed: () => context.go('/invoices'),
        child: const Text('Open'),
      ),
      child: purchase == null
          ? const Text('No purchase invoice yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: AppTheme.green, size: 42),
                const SizedBox(height: 8),
                Text(
                  purchase.invoiceNumber,
                  style: const TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                _AmountLine(label: 'Seller', value: purchase.sellerName),
                _AmountLine(
                  label: 'Total Bill',
                  value: Formatters.money(purchase.totalAmount),
                ),
                _AmountLine(
                  label: 'Paid',
                  value: Formatters.money(purchase.paidAmount),
                ),
                _AmountLine(
                  label: 'Balance',
                  value: Formatters.money(purchase.balanceAmount),
                  color: purchase.balanceAmount > 0
                      ? AppTheme.red
                      : AppTheme.green,
                ),
              ],
            ),
    );
  }
}

class _LedgerPreviewPanel extends StatelessWidget {
  const _LedgerPreviewPanel({required this.data});

  final ScrapDataProvider data;

  @override
  Widget build(BuildContext context) {
    final seller = data.sellers.firstOrNull;
    final entries = seller == null
        ? []
        : data.ledgerFor(seller.id).take(4).toList();
    return _Panel(
      title: 'Seller Ledger',
      trailing: TextButton(
        onPressed: () => context.go('/ledgers'),
        child: const Text('Open'),
      ),
      child: seller == null
          ? const Text('No seller found')
          : Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Text('R')),
                  title: Text(seller.name),
                  subtitle: Text(seller.phone),
                ),
                for (final entry in entries)
                  _AmountLine(
                    label: entry.description,
                    value: Formatters.money(entry.amount),
                    color: entry.direction == LedgerDirection.credit
                        ? AppTheme.green
                        : AppTheme.red,
                  ),
              ],
            ),
    );
  }
}

class _ReportsShortcutPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      ('Daily Report', Icons.today, AppTheme.blue),
      ('Weekly Report', Icons.calendar_view_week, AppTheme.green),
      ('Seller Report', Icons.storefront, AppTheme.purple),
      ('Profit & Loss', Icons.trending_up, AppTheme.orange),
    ];
    return _Panel(
      title: 'Reports',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final shortcut in shortcuts)
            SizedBox(
              width: 155,
              height: 42,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: shortcut.$3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => context.go('/reports'),
                icon: Icon(shortcut.$2, size: 17),
                label: Text(shortcut.$1, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartFeaturePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      (
        'Super fast data entry',
        'Purchase, sale and expense entry in seconds.',
        Icons.speed,
        AppTheme.green,
      ),
      (
        'Voice first approach',
        'Speak natural entries and save them quickly.',
        Icons.mic,
        AppTheme.blue,
      ),
      (
        'Profit focused',
        'Purchase, sales and expenses calculate live.',
        Icons.currency_rupee,
        AppTheme.orange,
      ),
      (
        'Secure roles',
        'Owner, supervisor and accountant access controls.',
        Icons.verified_user,
        AppTheme.purple,
      ),
    ];
    return _Panel(
      title: 'Smart Features',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final feature in features)
            SizedBox(
              width: 260,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: feature.$4.withValues(alpha: 0.12),
                    child: Icon(feature.$3, color: feature.$4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.$1,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          feature.$2,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}
