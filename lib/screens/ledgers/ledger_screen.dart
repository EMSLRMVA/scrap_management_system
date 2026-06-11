import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/ledger_entry.dart';
import '../../models/party.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  String? _partyId;
  _LedgerFilter _filter = _LedgerFilter.all;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    _partyId ??= data.parties.firstOrNull?.id;

    final selected = data.parties
        .where((party) => party.id == _partyId)
        .firstOrNull;
    final allEntries = selected == null
        ? <LedgerEntry>[]
        : data.ledgerFor(selected.id);
    final entries = _filtered(allEntries);
    final balance = allEntries.isEmpty
        ? selected?.openingBalance ?? 0
        : allEntries.first.balanceAfter;

    return ModuleScaffold(
      title: selected == null ? 'Seller Ledger' : '${selected.name} Ledger',
      subtitle: 'Vendor and customer credit-debit balances',
      icon: Icons.account_balance_wallet,
      children: [
        _PartySelectorCard(
          parties: data.parties,
          partyId: _partyId,
          selected: selected,
          balance: balance,
          onChanged: (value) => setState(() {
            _partyId = value;
            _filter = _LedgerFilter.all;
          }),
        ),
        const SizedBox(height: 12),
        if (selected != null)
          _LedgerSummary(data: data, party: selected, balance: balance),
        const SizedBox(height: 12),
        _FilterStrip(
          value: _filter,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: 12),
        _LedgerEntriesPanel(entries: entries),
      ],
    );
  }

  List<LedgerEntry> _filtered(List<LedgerEntry> entries) {
    switch (_filter) {
      case _LedgerFilter.all:
        return entries;
      case _LedgerFilter.unpaid:
        return entries.where((entry) => entry.balanceAfter > 0).toList();
      case _LedgerFilter.paid:
        return entries.where((entry) => entry.balanceAfter <= 0).toList();
      case _LedgerFilter.today:
        return entries.where((entry) => _isToday(entry.date)).toList();
    }
  }
}

class _PartySelectorCard extends StatelessWidget {
  const _PartySelectorCard({
    required this.parties,
    required this.partyId,
    required this.selected,
    required this.balance,
    required this.onChanged,
  });

  final List<Party> parties;
  final String? partyId;
  final Party? selected;
  final double balance;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: partyId,
            decoration: const InputDecoration(
              labelText: 'Vendor / Customer',
              prefixIcon: Icon(Icons.manage_accounts),
            ),
            items: [
              for (final party in parties)
                DropdownMenuItem(
                  value: party.id,
                  child: Text('${party.name} (${party.type.label})'),
                ),
            ],
            onChanged: onChanged,
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.purple.withValues(alpha: 0.12),
                  child: Text(
                    selected!.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.purple,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected!.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${selected!.phone} - ${selected!.area}'),
                    ],
                  ),
                ),
                StatusPill(
                  label: Formatters.money(balance),
                  color: balance > 0 ? AppTheme.red : AppTheme.green,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({
    required this.data,
    required this.party,
    required this.balance,
  });

  final ScrapDataProvider data;
  final Party party;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final isSeller = party.type == PartyType.seller;
    final total = isSeller
        ? data.purchases
              .where((purchase) => purchase.sellerId == party.id)
              .fold<double>(0, (sum, purchase) => sum + purchase.totalAmount)
        : data.sales
              .where((sale) => sale.customerId == party.id)
              .fold<double>(0, (sum, sale) => sum + sale.totalAmount);
    final paid = isSeller
        ? data.purchases
              .where((purchase) => purchase.sellerId == party.id)
              .fold<double>(0, (sum, purchase) => sum + purchase.paidAmount)
        : data.sales
              .where((sale) => sale.customerId == party.id)
              .fold<double>(0, (sum, sale) => sum + sale.receivedAmount);

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: isSeller ? 'Total Purchase' : 'Total Sale',
            value: Formatters.money(total),
            color: AppTheme.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: isSeller ? 'Total Paid' : 'Received',
            value: Formatters.money(paid),
            color: AppTheme.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: 'Balance',
            value: Formatters.money(balance),
            color: balance > 0 ? AppTheme.red : AppTheme.green,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.value, required this.onChanged});

  final _LedgerFilter value;
  final ValueChanged<_LedgerFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_LedgerFilter>(
        segments: const [
          ButtonSegment(value: _LedgerFilter.all, label: Text('All')),
          ButtonSegment(value: _LedgerFilter.unpaid, label: Text('Unpaid')),
          ButtonSegment(value: _LedgerFilter.paid, label: Text('Paid')),
          ButtonSegment(value: _LedgerFilter.today, label: Text('Today')),
        ],
        selected: {value},
        onSelectionChanged: (values) => onChanged(values.first),
      ),
    );
  }
}

class _LedgerEntriesPanel extends StatelessWidget {
  const _LedgerEntriesPanel({required this.entries});

  final List<LedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Transactions',
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No transactions for this filter')),
            )
          : Column(
              children: [
                for (final entry in entries) _LedgerEntryTile(entry: entry),
              ],
            ),
    );
  }
}

class _LedgerEntryTile extends StatelessWidget {
  const _LedgerEntryTile({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.direction == LedgerDirection.credit;
    final color = isCredit ? AppTheme.green : AppTheme.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(
              isCredit ? Icons.south_west : Icons.north_east,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(Formatters.date(entry.date)),
                Text(
                  'Balance ${Formatters.money(entry.balanceAfter)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.money(entry.amount),
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              Text(
                isCredit ? 'Credit' : 'Debit',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _LedgerFilter { all, unpaid, paid, today }

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}
