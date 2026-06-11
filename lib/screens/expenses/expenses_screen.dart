import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/responsive_grid.dart';
import '../../widgets/stat_tile.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _category = AppConstants.expenseCategories.first;
  final _amount = TextEditingController(text: '1000');
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final total = data.expenses.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    return ModuleScaffold(
      title: 'Expense Management',
      subtitle: 'Fuel, transport, salary, rent, maintenance, food, and reports',
      icon: Icons.receipt_long,
      children: [
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Total Expenses',
              value: Formatters.money(total),
              icon: Icons.payments,
              color: AppTheme.red,
            ),
            StatTile(
              label: 'Entries',
              value: data.expenses.length.toString(),
              icon: Icons.format_list_numbered,
              color: AppTheme.orange,
            ),
            StatTile(
              label: 'Top Category',
              value: data.expenses.first.category,
              icon: Icons.category,
              color: AppTheme.blue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final form = EnterpriseCard(
              title: 'Add Expense',
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final category in AppConstants.expenseCategories)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _category = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.add),
                      label: const Text('Save Expense'),
                    ),
                  ),
                ],
              ),
            );
            final table = _ExpenseTable();
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
    final user = context.read<AuthProvider>().currentUser;
    context.read<ScrapDataProvider>().addExpense(
      category: _category,
      amount: double.tryParse(_amount.text) ?? 0,
      createdBy: user?.name ?? 'System',
      note: _note.text,
    );
    _note.clear();
  }
}

class _ExpenseTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ScrapDataProvider>().expenses;
    return EnterpriseCard(
      title: 'Expense Register',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Category')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('Created By')),
            DataColumn(label: Text('Note')),
          ],
          rows: [
            for (final expense in expenses)
              DataRow(
                cells: [
                  DataCell(Text(Formatters.date(expense.createdAt))),
                  DataCell(Text(expense.category)),
                  DataCell(Text(Formatters.money(expense.amount))),
                  DataCell(Text(expense.createdBy)),
                  DataCell(Text(expense.note ?? '-')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
