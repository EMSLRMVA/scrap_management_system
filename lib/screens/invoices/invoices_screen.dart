import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../providers/scrap_data_provider.dart';
import '../../services/pdf_invoice_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ScrapDataProvider>();
    final service = PdfInvoiceService();
    final latestPurchase = data.purchases.firstOrNull;

    return ModuleScaffold(
      title: 'Invoice Generated',
      subtitle: 'Open, print and review purchase or sales invoices',
      icon: Icons.description,
      children: [
        _InvoiceSuccessPanel(
          purchase: latestPurchase,
          onViewPdf: latestPurchase == null
              ? null
              : () => Printing.layoutPdf(
                  onLayout: (_) => service.buildPurchaseInvoice(latestPurchase),
                ),
        ),
        const SizedBox(height: 12),
        _InvoiceTabs(
          purchases: data.purchases,
          sales: data.sales,
          service: service,
        ),
      ],
    );
  }
}

class _InvoiceSuccessPanel extends StatelessWidget {
  const _InvoiceSuccessPanel({required this.purchase, required this.onViewPdf});

  final Purchase? purchase;
  final VoidCallback? onViewPdf;

  @override
  Widget build(BuildContext context) {
    if (purchase == null) {
      return EnterpriseCard(
        child: Column(
          children: [
            const Icon(Icons.receipt_long, color: AppTheme.blue, size: 54),
            const SizedBox(height: 10),
            const Text(
              'No purchase invoice yet',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => context.go('/purchase'),
              icon: const Icon(Icons.add),
              label: const Text('Create Purchase'),
            ),
          ],
        ),
      );
    }

    return EnterpriseCard(
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.green, size: 58),
          const SizedBox(height: 8),
          const Text(
            'Purchase Saved Successfully',
            style: TextStyle(
              color: AppTheme.green,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            purchase!.invoiceNumber,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.blue,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          _SoftBox(
            child: Column(
              children: [
                _Line(label: 'Seller Name', value: purchase!.sellerName),
                _Line(
                  label: 'Total Bill',
                  value: Formatters.money(purchase!.totalAmount),
                ),
                _Line(
                  label: 'Paid Amount',
                  value: Formatters.money(purchase!.paidAmount),
                ),
                _Line(
                  label: 'Balance (Pending)',
                  value: Formatters.money(purchase!.balanceAmount),
                  color: purchase!.balanceAmount > 0
                      ? AppTheme.red
                      : AppTheme.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SoftBox(
            color: AppTheme.green.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(Icons.verified, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Invoice saved on ${Formatters.dateTime(purchase!.createdAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onViewPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('View Invoice'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/purchase'),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('New Purchase'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/ledgers'),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Ledger'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceTabs extends StatelessWidget {
  const _InvoiceTabs({
    required this.purchases,
    required this.sales,
    required this.service,
  });

  final List<Purchase> purchases;
  final List<Sale> sales;
  final PdfInvoiceService service;

  @override
  Widget build(BuildContext context) {
    return EnterpriseCard(
      title: 'All Invoices',
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Purchase'),
                Tab(text: 'Sales'),
              ],
            ),
            SizedBox(
              height: 360,
              child: TabBarView(
                children: [
                  _PurchaseInvoiceList(purchases: purchases, service: service),
                  _SalesInvoiceList(sales: sales, service: service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseInvoiceList extends StatelessWidget {
  const _PurchaseInvoiceList({required this.purchases, required this.service});

  final List<Purchase> purchases;
  final PdfInvoiceService service;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Invoice')),
          DataColumn(label: Text('Seller')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Balance')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('PDF')),
        ],
        rows: [
          for (final purchase in purchases)
            DataRow(
              cells: [
                DataCell(Text(purchase.invoiceNumber)),
                DataCell(Text(purchase.sellerName)),
                DataCell(Text(Formatters.date(purchase.createdAt))),
                DataCell(Text(Formatters.money(purchase.totalAmount))),
                DataCell(Text(Formatters.money(purchase.balanceAmount))),
                DataCell(
                  StatusPill(
                    label: purchase.isPaid ? 'Paid' : 'Pending',
                    color: purchase.isPaid ? AppTheme.green : AppTheme.red,
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'Generate PDF',
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () => Printing.layoutPdf(
                      onLayout: (_) => service.buildPurchaseInvoice(purchase),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SalesInvoiceList extends StatelessWidget {
  const _SalesInvoiceList({required this.sales, required this.service});

  final List<Sale> sales;
  final PdfInvoiceService service;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Invoice')),
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Balance')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('PDF')),
        ],
        rows: [
          for (final sale in sales)
            DataRow(
              cells: [
                DataCell(Text(sale.invoiceNumber)),
                DataCell(Text(sale.customerName)),
                DataCell(Text(Formatters.date(sale.createdAt))),
                DataCell(Text(Formatters.money(sale.totalAmount))),
                DataCell(Text(Formatters.money(sale.balanceAmount))),
                DataCell(
                  StatusPill(
                    label: sale.isPaid ? 'Paid' : 'Pending',
                    color: sale.isPaid ? AppTheme.green : AppTheme.red,
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'Generate PDF',
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () => Printing.layoutPdf(
                      onLayout: (_) => service.buildSalesInvoice(sale),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SoftBox extends StatelessWidget {
  const _SoftBox({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? AppTheme.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
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
