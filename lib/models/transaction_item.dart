class TransactionItem {
  const TransactionItem({
    required this.materialId,
    required this.materialName,
    required this.weightKg,
    required this.rate,
    this.discount = 0,
    this.wastageDeductionPercent = 0,
    double? effectiveWeight,
  }) : effectiveWeight = effectiveWeight ?? weightKg;

  final String materialId;
  final String materialName;
  final double weightKg;
  final double rate;
  final double discount;
  final double wastageDeductionPercent;
  final double effectiveWeight;

  double get actualWeight => weightKg;
  double get grossAmount => effectiveWeight * rate;
  double get amount => grossAmount - discount;

  TransactionItem copyWith({
    String? materialId,
    String? materialName,
    double? weightKg,
    double? rate,
    double? discount,
    double? wastageDeductionPercent,
    double? effectiveWeight,
  }) {
    return TransactionItem(
      materialId: materialId ?? this.materialId,
      materialName: materialName ?? this.materialName,
      weightKg: weightKg ?? this.weightKg,
      rate: rate ?? this.rate,
      discount: discount ?? this.discount,
      wastageDeductionPercent:
          wastageDeductionPercent ?? this.wastageDeductionPercent,
      effectiveWeight: effectiveWeight ?? this.effectiveWeight,
    );
  }
}
