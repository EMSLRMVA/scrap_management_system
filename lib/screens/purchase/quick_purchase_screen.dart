import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../constants/app_constants.dart';
import '../../models/material_item.dart';
import '../../models/party.dart';
import '../../models/transaction_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';

class QuickPurchaseScreen extends StatefulWidget {
  const QuickPurchaseScreen({super.key});

  @override
  State<QuickPurchaseScreen> createState() => _QuickPurchaseScreenState();
}

class _QuickPurchaseScreenState extends State<QuickPurchaseScreen> {
  String? _sellerId;
  String? _materialId;
  final _weight = TextEditingController(text: '150');
  final _rate = TextEditingController(text: '15');
  final _discount = TextEditingController(text: '0');
  final _paid = TextEditingController(text: '2000');
  final List<TransactionItem> _items = [];
  late final FlutterTts _tts;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
  }

  @override
  void dispose() {
    _tts.stop();
    _weight.dispose();
    _rate.dispose();
    _discount.dispose();
    _paid.dispose();
    super.dispose();
  }

  double get _itemsTotal => _items.fold(0, (sum, item) => sum + item.amount);
  double get _paidAmount => double.tryParse(_paid.text) ?? 0;
  double get _balance => _itemsTotal - _paidAmount;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    _sellerId ??= data.sellers.firstOrNull?.id;
    _materialId ??= data.materials.firstOrNull?.id;

    final selectedSeller = data.sellers
        .where((seller) => seller.id == _sellerId)
        .firstOrNull;

    return ModuleScaffold(
      title: 'Quick Purchase',
      subtitle: 'Fast multi-item purchase with live balance and invoice',
      icon: Icons.add_shopping_cart,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 980;
            final left = Column(
              children: [
                _SellerSelectorCard(
                  sellers: data.sellers,
                  selectedSeller: selectedSeller,
                  sellerId: _sellerId,
                  onChanged: (value) => setState(() => _sellerId = value),
                ),
                const SizedBox(height: 12),
                _ItemEntryCard(
                  materials: data.materials,
                  materialId: _materialId,
                  weight: _weight,
                  rate: _rate,
                  discount: _discount,
                  paid: _paid,
                  onMaterialChanged: (value) {
                    final material = data.materials
                        .where((item) => item.id == value)
                        .firstOrNull;
                    setState(() {
                      _materialId = value;
                      if (material != null) {
                        _rate.text = material.currentBuyingRate.toStringAsFixed(
                          0,
                        );
                      }
                    });
                  },
                  onValueChanged: () => setState(() {}),
                  onAddItem: () => _addItem(data.materials),
                ),
              ],
            );
            final right = Column(
              children: [
                _PurchaseTicketCard(
                  seller: selectedSeller,
                  items: _items,
                  total: _itemsTotal,
                  paid: _paidAmount,
                  balance: _balance,
                  onRemove: (item) => setState(() => _items.remove(item)),
                  onListen: () => _speakBill(selectedSeller),
                  onSave: () => _save(data),
                ),
                const SizedBox(height: 12),
                _RecentPurchasePanel(),
              ],
            );

            if (!desktop) {
              return Column(
                children: [left, const SizedBox(height: 12), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 430, child: left),
                const SizedBox(width: 14),
                Expanded(child: right),
              ],
            );
          },
        ),
      ],
    );
  }

  void _addItem(List<MaterialItem> materials) {
    final material = materials
        .where((item) => item.id == _materialId)
        .firstOrNull;
    final weight = double.tryParse(_weight.text) ?? 0;
    final rate = double.tryParse(_rate.text) ?? 0;
    final discount = double.tryParse(_discount.text) ?? 0;
    if (material == null || weight <= 0 || rate <= 0) {
      _showMessage('Enter a valid material, weight and rate.');
      return;
    }
    setState(() {
      final deduction = material.normalizedWastageDeductionPercent;
      final effectiveWeight = (weight - (weight * deduction / 100))
          .clamp(0, double.infinity)
          .toDouble();
      _items.add(
        TransactionItem(
          materialId: material.id,
          materialName: material.name,
          weightKg: weight,
          wastageDeductionPercent: deduction,
          effectiveWeight: effectiveWeight,
          rate: rate,
          discount: discount,
        ),
      );
    });
  }

  Future<void> _speakBill(Party? seller) async {
    if (_items.isEmpty) {
      _showMessage('Add at least one item before listening to the bill.');
      return;
    }
    final lineItems = _items
        .map((item) => '${item.materialName}, ${item.weightKg} kg')
        .join(', ');
    final message =
        'Purchase bill for ${seller?.name ?? 'seller'}. Items: $lineItems. Total bill ${_itemsTotal.toStringAsFixed(0)} rupees. Paid ${_paidAmount.toStringAsFixed(0)} rupees. Balance ${_balance.toStringAsFixed(0)} rupees.';
    await _tts.speak(message);
  }

  void _save(ScrapDataProvider data) {
    if (_items.isEmpty) {
      _showMessage('Add at least one item before saving purchase.');
      return;
    }
    if (_sellerId == null) {
      _showMessage('Select a seller before saving purchase.');
      return;
    }
    final user = context.read<AuthProvider>().currentUser;
    final purchase = data.addPurchase(
      sellerId: _sellerId!,
      items: List.of(_items),
      paidAmount: _paidAmount,
      createdBy: user?.name ?? 'System',
    );
    setState(_items.clear);
    _showMessage('${purchase.invoiceNumber} saved successfully.');
    context.go('/invoices');
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

class _SellerSelectorCard extends StatelessWidget {
  const _SellerSelectorCard({
    required this.sellers,
    required this.selectedSeller,
    required this.sellerId,
    required this.onChanged,
  });

  final List<Party> sellers;
  final Party? selectedSeller;
  final String? sellerId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Seller',
      trailing: IconButton.outlined(
        tooltip: 'Add seller',
        onPressed: () => context.go('/sellers'),
        icon: const Icon(Icons.person_add_alt_1),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: sellerId,
            decoration: const InputDecoration(
              labelText: 'Select seller',
              prefixIcon: Icon(Icons.storefront),
            ),
            items: [
              for (final seller in sellers)
                DropdownMenuItem(value: seller.id, child: Text(seller.name)),
            ],
            onChanged: onChanged,
          ),
          if (selectedSeller != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.blue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.orange.withValues(alpha: 0.16),
                    child: Text(
                      selectedSeller!.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedSeller!.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(selectedSeller!.phone),
                        Text(
                          selectedSeller!.area,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Pending',
                      style: TextStyle(
                        color: AppTheme.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemEntryCard extends StatelessWidget {
  const _ItemEntryCard({
    required this.materials,
    required this.materialId,
    required this.weight,
    required this.rate,
    required this.discount,
    required this.paid,
    required this.onMaterialChanged,
    required this.onValueChanged,
    required this.onAddItem,
  });

  final List<MaterialItem> materials;
  final String? materialId;
  final TextEditingController weight;
  final TextEditingController rate;
  final TextEditingController discount;
  final TextEditingController paid;
  final ValueChanged<String?> onMaterialChanged;
  final VoidCallback onValueChanged;
  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Items',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: materialId,
            decoration: const InputDecoration(
              labelText: 'Material',
              prefixIcon: Icon(Icons.inventory_2),
            ),
            items: [
              for (final material in materials)
                DropdownMenuItem(
                  value: material.id,
                  child: Row(
                    children: [
                      Icon(
                        AppConstants.materialIcons[material.name] ??
                            Icons.inventory,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(material.name),
                    ],
                  ),
                ),
            ],
            onChanged: onMaterialChanged,
          ),
          const SizedBox(height: 12),
          ResponsiveGrid(
            minItemWidth: 132,
            children: [
              TextField(
                controller: weight,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(
                  labelText: 'Weight (KG)',
                  prefixIcon: Icon(Icons.scale),
                ),
              ),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(
                  labelText: 'Rate / KG',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              TextField(
                controller: discount,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(
                  labelText: 'Discount',
                  prefixIcon: Icon(Icons.percent),
                ),
              ),
              TextField(
                controller: paid,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(
                  labelText: 'Paid Amount',
                  prefixIcon: Icon(Icons.payments),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseTicketCard extends StatelessWidget {
  const _PurchaseTicketCard({
    required this.seller,
    required this.items,
    required this.total,
    required this.paid,
    required this.balance,
    required this.onRemove,
    required this.onListen,
    required this.onSave,
  });

  final Party? seller;
  final List<TransactionItem> items;
  final double total;
  final double paid;
  final double balance;
  final ValueChanged<TransactionItem> onRemove;
  final VoidCallback onListen;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Quick Purchase Bill',
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: AppTheme.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  seller?.name ?? 'Select seller',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Add item details and press Add Item to build this bill.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final item in items)
              _BillItemRow(item: item, onRemove: () => onRemove(item)),
          const Divider(height: 24),
          _Line(label: 'Total Bill Amount', value: Formatters.money(total)),
          _Line(label: 'Paid Amount', value: Formatters.money(paid)),
          _Line(
            label: 'Balance (Pending)',
            value: Formatters.money(balance),
            color: balance > 0 ? AppTheme.red : AppTheme.green,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onListen,
                  icon: const Icon(Icons.volume_up),
                  label: const FittedBox(child: Text('Listen Bill')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.green,
                  ),
                  onPressed: onSave,
                  icon: const Icon(Icons.check),
                  label: const FittedBox(child: Text('Save Purchase')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillItemRow extends StatelessWidget {
  const _BillItemRow({required this.item, required this.onRemove});

  final TransactionItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.green.withValues(alpha: 0.10),
            child: Icon(
              AppConstants.materialIcons[item.materialName] ?? Icons.recycling,
              color: AppTheme.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.materialName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${Formatters.kg(item.weightKg)} x ${Formatters.money(item.rate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            Formatters.money(item.amount),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          IconButton(
            tooltip: 'Remove item',
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: AppTheme.red),
          ),
        ],
      ),
    );
  }
}

class _RecentPurchasePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final purchases = context.watch<ScrapDataProvider>().purchases.take(4);
    return EnterpriseCard(
      title: 'Recent Purchases',
      child: Column(
        children: [
          for (final purchase in purchases)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text(
                purchase.invoiceNumber,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(purchase.sellerName),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.money(purchase.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(Formatters.kg(purchase.totalWeightKg)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}
