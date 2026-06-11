import '../domain/business_models.dart';

class SmartPricingSuggestion {
  const SmartPricingSuggestion({
    required this.material,
    required this.costRate,
    required this.averagePurchaseRate,
    required this.lastPurchaseRate,
    required this.averageSellingRate,
    required this.lastSellingRate,
    required this.safeMinimumSellingRate,
    required this.suggestedSellingRate,
  });

  final MaterialStock material;
  final double costRate;
  final double averagePurchaseRate;
  final double lastPurchaseRate;
  final double averageSellingRate;
  final double lastSellingRate;
  final double safeMinimumSellingRate;
  final double suggestedSellingRate;

  bool isBelowSafeRate(double rate) =>
      rate > 0 && rate < safeMinimumSellingRate;

  double marginPercentAt(double rate) {
    if (rate <= 0) {
      return 0;
    }
    return ((rate - costRate) / rate) * 100;
  }
}

class SmartPricingService {
  const SmartPricingService();

  SmartPricingSuggestion? suggestFor(
    BusinessState state,
    MaterialStock? selected,
  ) {
    if (selected == null) {
      return null;
    }
    final material = _stateMaterial(state, selected) ?? selected;
    final purchaseLines = <({DateTime date, LineItem item})>[];
    for (final purchase in state.activePurchases) {
      for (final item in purchase.items) {
        if (_sameMaterial(item, material)) {
          purchaseLines.add((date: purchase.createdAt, item: item));
        }
      }
    }
    final saleLines = <({DateTime date, LineItem item})>[];
    for (final sale in state.activeSales) {
      for (final item in sale.items) {
        if (_sameMaterial(item, material)) {
          saleLines.add((date: sale.createdAt, item: item));
        }
      }
    }
    purchaseLines.sort((a, b) => b.date.compareTo(a.date));
    saleLines.sort((a, b) => b.date.compareTo(a.date));

    final averagePurchaseRate = _weightedAverageRate(purchaseLines);
    final averageSellingRate = _weightedAverageRate(saleLines);
    final lastPurchaseRate = purchaseLines.isEmpty
        ? 0.0
        : purchaseLines.first.item.rate;
    final lastSellingRate = saleLines.isEmpty ? 0.0 : saleLines.first.item.rate;
    final configuredSellingRate = material.currentSellingRate > 0
        ? material.currentSellingRate
        : material.currentBuyingRate;
    final costRate = _firstPositive([
      lastPurchaseRate,
      averagePurchaseRate,
      material.currentBuyingRate,
    ]);
    final safeMinimumSellingRate = costRate <= 0
        ? configuredSellingRate
        : _roundRate(costRate * 1.05);
    final suggestedSellingRate = _roundRate(
      _maxPositive([
        configuredSellingRate,
        averageSellingRate,
        lastSellingRate,
        safeMinimumSellingRate,
      ]),
    );

    return SmartPricingSuggestion(
      material: material,
      costRate: costRate,
      averagePurchaseRate: averagePurchaseRate,
      lastPurchaseRate: lastPurchaseRate,
      averageSellingRate: averageSellingRate,
      lastSellingRate: lastSellingRate,
      safeMinimumSellingRate: safeMinimumSellingRate,
      suggestedSellingRate: suggestedSellingRate,
    );
  }

  MaterialStock? _stateMaterial(BusinessState state, MaterialStock selected) {
    for (final material in state.activeMaterials) {
      if (material.id == selected.id ||
          material.name.trim().toLowerCase() ==
              selected.name.trim().toLowerCase()) {
        return material;
      }
    }
    return null;
  }

  bool _sameMaterial(LineItem item, MaterialStock material) {
    if (item.materialId.trim().isNotEmpty && item.materialId == material.id) {
      return true;
    }
    return item.materialName.trim().toLowerCase() ==
        material.name.trim().toLowerCase();
  }

  double _weightedAverageRate(List<({DateTime date, LineItem item})> lines) {
    var weightedAmount = 0.0;
    var weight = 0.0;
    for (final line in lines) {
      final lineWeight = line.item.effectiveWeight <= 0
          ? line.item.weightKg
          : line.item.effectiveWeight;
      if (lineWeight <= 0 || line.item.rate <= 0) {
        continue;
      }
      weightedAmount += line.item.rate * lineWeight;
      weight += lineWeight;
    }
    return weight <= 0 ? 0 : weightedAmount / weight;
  }

  double _firstPositive(List<double> values) {
    for (final value in values) {
      if (value > 0) {
        return value;
      }
    }
    return 0;
  }

  double _maxPositive(List<double> values) {
    var result = 0.0;
    for (final value in values) {
      if (value > result) {
        result = value;
      }
    }
    return result;
  }

  double _roundRate(double value) => double.parse(value.toStringAsFixed(2));
}
