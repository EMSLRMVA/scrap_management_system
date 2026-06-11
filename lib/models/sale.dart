import 'transaction_item.dart';

class Sale {
  const Sale({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    required this.items,
    required this.receivedAmount,
    required this.createdBy,
    this.vehicleNumber,
    this.notes,
  });

  final String id;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final List<TransactionItem> items;
  final double receivedAmount;
  final String createdBy;
  final String? vehicleNumber;
  final String? notes;

  double get totalWeightKg =>
      items.fold(0, (total, item) => total + item.weightKg);
  double get totalAmount => items.fold(0, (total, item) => total + item.amount);
  double get balanceAmount => totalAmount - receivedAmount;
  bool get isPaid => balanceAmount <= 0;
}
