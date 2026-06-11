class DashboardMetrics {
  const DashboardMetrics({
    required this.todayPurchaseKg,
    required this.todayPurchaseValue,
    required this.todaySalesKg,
    required this.todaySalesValue,
    required this.pendingPayments,
    required this.todayExpenses,
    required this.netProfit,
    required this.stockValue,
    required this.invoiceCount,
    required this.vendorCount,
    required this.customerCount,
  });

  final double todayPurchaseKg;
  final double todayPurchaseValue;
  final double todaySalesKg;
  final double todaySalesValue;
  final double pendingPayments;
  final double todayExpenses;
  final double netProfit;
  final double stockValue;
  final int invoiceCount;
  final int vendorCount;
  final int customerCount;
}
