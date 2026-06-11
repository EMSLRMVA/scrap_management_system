class ReportSummary {
  const ReportSummary({
    required this.title,
    required this.purchase,
    required this.sales,
    required this.expense,
    required this.profit,
    required this.generatedAt,
  });

  final String title;
  final double purchase;
  final double sales;
  final double expense;
  final double profit;
  final DateTime generatedAt;
}
