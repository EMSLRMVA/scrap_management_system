import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/dispatch.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/status_pill.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  final _customer = TextEditingController(text: 'Sharma Recyclers');
  final _material = TextEditingController(text: 'Coconut Shell');
  final _weight = TextEditingController(text: '500');
  final _vehicle = TextEditingController(text: 'TN70AB1123');
  final _driver = TextEditingController(text: 'Lokesh');

  @override
  void dispose() {
    _customer.dispose();
    _material.dispose();
    _weight.dispose();
    _vehicle.dispose();
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final dispatches = data.dispatches;
    final totalWeight = dispatches.fold<double>(
      0,
      (sum, dispatch) => sum + dispatch.weightKg,
    );

    return ModuleScaffold(
      title: 'Dispatch Management',
      subtitle: 'Vehicle, driver, material, weight, and status tracking',
      icon: Icons.local_shipping,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Dispatches',
              value: dispatches.length.toString(),
              icon: Icons.local_shipping,
              color: AppTheme.blue,
            ),
            StatTile(
              label: 'Loaded Weight',
              value: Formatters.kg(totalWeight),
              icon: Icons.scale,
              color: AppTheme.green,
            ),
            StatTile(
              label: 'In Transit',
              value: dispatches
                  .where((item) => item.status == DispatchStatus.inTransit)
                  .length
                  .toString(),
              icon: Icons.route,
              color: AppTheme.orange,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final form = EnterpriseCard(
              title: 'Dispatch Entry',
              child: Column(
                children: [
                  TextField(
                    controller: _customer,
                    decoration: const InputDecoration(
                      labelText: 'Vendor / Customer',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _material,
                    decoration: const InputDecoration(labelText: 'Material'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Weight (KG)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _vehicle,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle number',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _driver,
                    decoration: const InputDecoration(labelText: 'Driver name'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.outbox),
                      label: const Text('Dispatch Material'),
                    ),
                  ),
                ],
              ),
            );
            final table = _DispatchTable(dispatches: dispatches);
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

  void _save() {
    context.read<ScrapDataProvider>().addDispatch(
      customerName: _customer.text,
      materialName: _material.text,
      weightKg: double.tryParse(_weight.text) ?? 0,
      vehicleNumber: _vehicle.text,
      driverName: _driver.text,
    );
  }
}

class _DispatchTable extends StatelessWidget {
  const _DispatchTable({required this.dispatches});

  final List<Dispatch> dispatches;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'Dispatch Register',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Material')),
            DataColumn(label: Text('Weight')),
            DataColumn(label: Text('Vehicle')),
            DataColumn(label: Text('Driver')),
            DataColumn(label: Text('Status')),
          ],
          rows: [
            for (final dispatch in dispatches)
              DataRow(
                cells: [
                  DataCell(Text(Formatters.dateTime(dispatch.createdAt))),
                  DataCell(Text(dispatch.customerName)),
                  DataCell(Text(dispatch.materialName)),
                  DataCell(Text(Formatters.kg(dispatch.weightKg))),
                  DataCell(Text(dispatch.vehicleNumber)),
                  DataCell(Text(dispatch.driverName)),
                  DataCell(
                    StatusPill(
                      label: dispatch.status.label,
                      color: dispatch.status == DispatchStatus.delivered
                          ? AppTheme.green
                          : AppTheme.orange,
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
