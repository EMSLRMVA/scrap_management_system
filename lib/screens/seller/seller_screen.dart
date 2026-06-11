import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/party.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class SellerScreen extends StatefulWidget {
  const SellerScreen({super.key});

  @override
  State<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends State<SellerScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _gst = TextEditingController();
  Party? _editing;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _area.dispose();
    _gst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    return ModuleScaffold(
      title: _editing == null ? 'Add New Seller' : 'Edit Seller',
      subtitle: 'Create vendors, update details, and open their ledger',
      icon: Icons.storefront,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final form = _SellerFormCard(
              name: _name,
              phone: _phone,
              area: _area,
              gst: _gst,
              editing: _editing,
              onSave: _save,
              onClear: _clear,
            );
            final list = _SellerListPanel(
              sellers: data.sellers,
              onEdit: _edit,
              onDelete: (seller) => _confirmDelete(context, data, seller),
            );
            if (constraints.maxWidth < 980) {
              return Column(children: [form, const SizedBox(height: 12), list]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 430, child: form),
                const SizedBox(width: 14),
                Expanded(child: list),
              ],
            );
          },
        ),
      ],
    );
  }

  void _edit(Party seller) {
    setState(() {
      _editing = seller;
      _name.text = seller.name;
      _phone.text = seller.phone;
      _area.text = seller.area;
      _gst.text = seller.gstNumber ?? '';
    });
  }

  void _save() {
    final data = context.read<ScrapDataProvider>();
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final area = _area.text.trim();
    final gst = _gst.text.trim();

    if (name.isEmpty || phone.isEmpty || area.isEmpty) {
      _showMessage('Seller name, mobile number and area are required.');
      return;
    }

    if (_editing == null) {
      data.addParty(
        name: name,
        phone: phone,
        area: area,
        type: PartyType.seller,
        gstNumber: gst.isEmpty ? null : gst,
      );
      _showMessage('$name saved as seller.');
    } else {
      data.updateParty(
        _editing!.copyWith(
          name: name,
          phone: phone,
          area: area,
          gstNumber: gst.isEmpty ? null : gst,
        ),
      );
      _showMessage('$name updated.');
    }
    _clear();
  }

  void _clear() {
    setState(() {
      _editing = null;
      _name.clear();
      _phone.clear();
      _area.clear();
      _gst.clear();
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ScrapDataProvider data,
    Party seller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete seller?'),
        content: Text('Remove ${seller.name} from seller list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      data.deleteParty(seller.id);
      _showMessage('${seller.name} deleted.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SellerFormCard extends StatelessWidget {
  const _SellerFormCard({
    required this.name,
    required this.phone,
    required this.area,
    required this.gst,
    required this.editing,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController area;
  final TextEditingController gst;
  final Party? editing;
  final VoidCallback onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      child: Column(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppTheme.green.withValues(alpha: 0.15),
            child: const Icon(
              Icons.person_add_alt_1,
              color: AppTheme.green,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          _Input(
            controller: name,
            label: 'Seller Name',
            icon: Icons.storefront,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _Input(
            controller: area,
            label: 'Area Name',
            icon: Icons.location_on_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _Input(
            controller: phone,
            label: 'Mobile Number',
            icon: Icons.phone_android,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _Input(
            controller: gst,
            label: 'GST Number (Optional)',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.blue),
                  onPressed: onSave,
                  icon: Icon(editing == null ? Icons.save : Icons.check),
                  label: Text(
                    editing == null ? 'Save Seller' : 'Update Seller',
                  ),
                ),
              ),
              if (editing != null) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Cancel edit',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}

class _SellerListPanel extends StatelessWidget {
  const _SellerListPanel({
    required this.sellers,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Party> sellers;
  final ValueChanged<Party> onEdit;
  final ValueChanged<Party> onDelete;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Seller Ledger',
      child: Column(
        children: [
          for (final seller in sellers)
            _SellerTile(
              seller: seller,
              onEdit: () => onEdit(seller),
              onDelete: () => onDelete(seller),
              onLedger: () => context.go('/ledgers'),
            ),
        ],
      ),
    );
  }
}

class _SellerTile extends StatelessWidget {
  const _SellerTile({
    required this.seller,
    required this.onEdit,
    required this.onDelete,
    required this.onLedger,
  });

  final Party seller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLedger;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.blue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(
              seller.name.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text('${seller.phone} - ${seller.area}'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const StatusPill(label: 'Active', color: AppTheme.green),
                    const SizedBox(width: 8),
                    Text(
                      'Opening ${Formatters.money(seller.openingBalance)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Ledger',
            onPressed: onLedger,
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, color: AppTheme.orange),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: AppTheme.red),
          ),
        ],
      ),
    );
  }
}
