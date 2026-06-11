class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.createdAt,
    required this.createdBy,
    this.note,
  });

  final String id;
  final String category;
  final double amount;
  final DateTime createdAt;
  final String createdBy;
  final String? note;
}
