import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/party.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
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
      title: 'Customer Management',
      subtitle:
          'Track customers, outstanding amounts, sales history, and reminders',
      icon: Icons.people,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final form = _CustomerForm(
              name: _name,
              phone: _phone,
              area: _area,
              gst: _gst,
              editing: _editing,
              onSave: _save,
              onClear: _clear,
            );
            final table = _CustomerTable(
              customers: data.customers,
              salesBalance: {
                for (final customer in data.customers)
                  customer.id: data.sales
                      .where((sale) => sale.customerId == customer.id)
                      .fold<double>(0, (sum, sale) => sum + sale.balanceAmount),
              },
              onEdit: _edit,
              onDelete: (customer) => data.deleteParty(customer.id),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [form, const SizedBox(height: 12), table],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 420, child: form),
                const SizedBox(width: 12),
                Expanded(child: table),
              ],
            );
          },
        ),
      ],
    );
  }

  void _edit(Party customer) {
    setState(() {
      _editing = customer;
      _name.text = customer.name;
      _phone.text = customer.phone;
      _area.text = customer.area;
      _gst.text = customer.gstNumber ?? '';
    });
  }

  void _save() {
    final data = context.read<ScrapDataProvider>();
    if (_editing == null) {
      data.addParty(
        name: _name.text.isEmpty ? 'New Customer' : _name.text,
        phone: _phone.text,
        area: _area.text,
        type: PartyType.customer,
        gstNumber: _gst.text.isEmpty ? null : _gst.text,
      );
    } else {
      data.updateParty(
        _editing!.copyWith(
          name: _name.text,
          phone: _phone.text,
          area: _area.text,
          gstNumber: _gst.text.isEmpty ? null : _gst.text,
        ),
      );
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
}

class _CustomerForm extends StatelessWidget {
  const _CustomerForm({
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
      title: editing == null ? 'Add Customer' : 'Edit Customer',
      child: Column(
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Customer name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Mobile number'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: area,
            decoration: const InputDecoration(labelText: 'Area'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: gst,
            decoration: const InputDecoration(labelText: 'GST number'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: Icon(editing == null ? Icons.add : Icons.save),
                  label: Text(
                    editing == null ? 'Add Customer' : 'Save Changes',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({
    required this.customers,
    required this.salesBalance,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Party> customers;
  final Map<String, double> salesBalance;
  final ValueChanged<Party> onEdit;
  final ValueChanged<Party> onDelete;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Customer Ledger',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Area')),
            DataColumn(label: Text('Outstanding')),
            DataColumn(label: Text('Reminder')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final customer in customers)
              DataRow(
                cells: [
                  DataCell(Text(customer.name)),
                  DataCell(Text(customer.phone)),
                  DataCell(Text(customer.area)),
                  DataCell(
                    Text(Formatters.money(salesBalance[customer.id] ?? 0)),
                  ),
                  const DataCell(
                    StatusPill(label: 'WhatsApp Ready', color: AppTheme.green),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          onPressed: () => onEdit(customer),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => onDelete(customer),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
