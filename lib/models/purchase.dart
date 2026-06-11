import 'transaction_item.dart';

class Purchase {
  const Purchase({
    required this.id,
    required this.invoiceNumber,
    required this.sellerId,
    required this.sellerName,
    required this.createdAt,
    required this.items,
    required this.paidAmount,
    required this.createdBy,
    this.notes,
  });

  final String id;
  final String invoiceNumber;
  final String sellerId;
  final String sellerName;
  final DateTime createdAt;
  final List<TransactionItem> items;
  final double paidAmount;
  final String createdBy;
  final String? notes;

  double get totalWeightKg =>
      items.fold(0, (total, item) => total + item.weightKg);
  double get totalAmount => items.fold(0, (total, item) => total + item.amount);
  double get balanceAmount => totalAmount - paidAmount;
  bool get isPaid => balanceAmount <= 0;
}
