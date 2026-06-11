import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/material_item.dart';
import '../../models/party.dart';
import '../../models/transaction_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String? _customerId;
  String? _materialId;
  final _weight = TextEditingController(text: '500');
  final _rate = TextEditingController(text: '18');
  final _received = TextEditingController(text: '9000');
  final _vehicle = TextEditingController(text: 'TN70AB1123');
  final List<TransactionItem> _items = [];

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    _received.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0, (sum, item) => sum + item.amount);
  double get _receivedAmount => double.tryParse(_received.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    if (_customerId == null && data.customers.isNotEmpty) {
      _customerId = data.customers.first.id;
    }
    if (_materialId == null && data.materials.isNotEmpty) {
      _materialId = data.materials.first.id;
    }

    return ModuleScaffold(
      title: 'Sales Entry',
      subtitle: 'Multi-item sales with invoice, vehicle, and payment tracking',
      icon: Icons.point_of_sale,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final form = _SaleForm(
              customers: data.customers,
              materials: data.materials,
              customerId: _customerId,
              materialId: _materialId,
              weight: _weight,
              rate: _rate,
              received: _received,
              vehicle: _vehicle,
              onCustomerChanged: (value) => setState(() => _customerId = value),
              onMaterialChanged: (value) {
                final material = data.materials.firstWhere(
                  (item) => item.id == value,
                );
                setState(() {
                  _materialId = value;
                  _rate.text = material.currentSellingRate.toStringAsFixed(0);
                });
              },
              onValueChanged: () => setState(() {}),
              onAddItem: () => _addItem(data.materials),
            );
            final summary = _SaleSummary(
              items: _items,
              total: _total,
              received: _receivedAmount,
              onRemove: (item) => setState(() => _items.remove(item)),
              onSave: () => _save(data),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [form, const SizedBox(height: 12), summary],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(width: 12),
                Expanded(child: summary),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _SalesHistory(),
      ],
    );
  }

  void _addItem(List<MaterialItem> materials) {
    final material = materials.firstWhere((item) => item.id == _materialId);
    final weight = double.tryParse(_weight.text) ?? 0;
    final rate = double.tryParse(_rate.text) ?? 0;
    if (weight <= 0 || rate <= 0) {
      return;
    }
    setState(() {
      _items.add(
        TransactionItem(
          materialId: material.id,
          materialName: material.name,
          weightKg: weight,
          rate: rate,
        ),
      );
    });
  }

  void _save(ScrapDataProvider data) {
    if (_items.isEmpty || _customerId == null) {
      return;
    }
    final user = context.read<AuthProvider>().currentUser;
    final sale = data.addSale(
      customerId: _customerId!,
      items: List.of(_items),
      receivedAmount: _receivedAmount,
      createdBy: user?.name ?? 'System',
      vehicleNumber: _vehicle.text,
    );
    setState(_items.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${sale.invoiceNumber} saved successfully')),
    );
  }
}

class _SaleForm extends StatelessWidget {
  const _SaleForm({
    required this.customers,
    required this.materials,
    required this.customerId,
    required this.materialId,
    required this.weight,
    required this.rate,
    required this.received,
    required this.vehicle,
    required this.onCustomerChanged,
    required this.onMaterialChanged,
    required this.onValueChanged,
    required this.onAddItem,
  });

  final List<Party> customers;
  final List<MaterialItem> materials;
  final String? customerId;
  final String? materialId;
  final TextEditingController weight;
  final TextEditingController rate;
  final TextEditingController received;
  final TextEditingController vehicle;
  final ValueChanged<String?> onCustomerChanged;
  final ValueChanged<String?> onMaterialChanged;
  final VoidCallback onValueChanged;
  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'New Sale',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: customerId,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: [
              for (final customer in customers)
                DropdownMenuItem(
                  value: customer.id,
                  child: Text(customer.name),
                ),
            ],
            onChanged: onCustomerChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: materialId,
            decoration: const InputDecoration(labelText: 'Material'),
            items: [
              for (final material in materials)
                DropdownMenuItem(
                  value: material.id,
                  child: Text(material.name),
                ),
            ],
            onChanged: onMaterialChanged,
          ),
          const SizedBox(height: 12),
          ResponsiveGrid(
            minItemWidth: 150,
            children: [
              TextField(
                controller: weight,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(labelText: 'Weight (KG)'),
              ),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(labelText: 'Sale Rate'),
              ),
              TextField(
                controller: received,
                keyboardType: TextInputType.number,
                onChanged: (_) => onValueChanged(),
                decoration: const InputDecoration(labelText: 'Received'),
              ),
              TextField(
                controller: vehicle,
                decoration: const InputDecoration(labelText: 'Vehicle No.'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Sale Item'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleSummary extends StatelessWidget {
  const _SaleSummary({
    required this.items,
    required this.total,
    required this.received,
    required this.onRemove,
    required this.onSave,
  });

  final List<TransactionItem> items;
  final double total;
  final double received;
  final ValueChanged<TransactionItem> onRemove;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final balance = total - received;
    return EnterpriseCard(
      title: 'Invoice Summary',
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.inventory)),
              title: Text(item.materialName),
              subtitle: Text(
                '${Formatters.kg(item.weightKg)} x ${Formatters.money(item.rate)}',
              ),
              trailing: IconButton(
                tooltip: 'Remove item',
                onPressed: () => onRemove(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Text('Add materials to create invoice'),
            ),
          const Divider(),
          _Line(label: 'Total Sale', value: Formatters.money(total)),
          _Line(label: 'Received', value: Formatters.money(received)),
          _Line(
            label: 'Balance',
            value: Formatters.money(balance),
            color: balance > 0 ? AppTheme.red : AppTheme.green,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save),
              label: const Text('Save Sale'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<ScrapDataProvider>().sales;
    return EnterpriseCard(
      title: 'Sales History',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Invoice')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Weight')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Received')),
            DataColumn(label: Text('Balance')),
          ],
          rows: [
            for (final sale in sales)
              DataRow(
                cells: [
                  DataCell(Text(sale.invoiceNumber)),
                  DataCell(Text(sale.customerName)),
                  DataCell(Text(Formatters.kg(sale.totalWeightKg))),
                  DataCell(Text(Formatters.money(sale.totalAmount))),
                  DataCell(Text(Formatters.money(sale.receivedAmount))),
                  DataCell(Text(Formatters.money(sale.balanceAmount))),
                ],
              ),
          ],
        ),
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
