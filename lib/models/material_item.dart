class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.name,
    required this.category,
    required this.openingStockKg,
    required this.purchasedKg,
    required this.soldKg,
    required this.currentBuyingRate,
    required this.currentSellingRate,
    required this.lowStockThresholdKg,
    this.wastageDeductionPercent = 0,
  });

  final String id;
  final String name;
  final String category;
  final double openingStockKg;
  final double purchasedKg;
  final double soldKg;
  final double currentBuyingRate;
  final double currentSellingRate;
  final double lowStockThresholdKg;
  final double wastageDeductionPercent;

  double get currentStockKg => openingStockKg + purchasedKg - soldKg;
  double get stockValue => currentStockKg * currentBuyingRate;
  bool get isLowStock => currentStockKg <= lowStockThresholdKg;
  double get normalizedWastageDeductionPercent =>
      wastageDeductionPercent.clamp(0, 100).toDouble();

  MaterialItem copyWith({
    String? id,
    String? name,
    String? category,
    double? openingStockKg,
    double? purchasedKg,
    double? soldKg,
    double? currentBuyingRate,
    double? currentSellingRate,
    double? lowStockThresholdKg,
    double? wastageDeductionPercent,
  }) {
    return MaterialItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      openingStockKg: openingStockKg ?? this.openingStockKg,
      purchasedKg: purchasedKg ?? this.purchasedKg,
      soldKg: soldKg ?? this.soldKg,
      currentBuyingRate: currentBuyingRate ?? this.currentBuyingRate,
      currentSellingRate: currentSellingRate ?? this.currentSellingRate,
      lowStockThresholdKg: lowStockThresholdKg ?? this.lowStockThresholdKg,
      wastageDeductionPercent:
          wastageDeductionPercent ?? this.wastageDeductionPercent,
    );
  }
}
